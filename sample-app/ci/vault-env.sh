#!/bin/bash
# ดึงทุก key ใน secret/<path> ของ Vault มาเขียนเป็น env-file (KEY=VALUE) สำหรับ docker run --env-file
# แบบเดียวกับที่ glo-portal ดึง secret/<env>/backend-env แต่แก้จุดอ่อนของของเดิม:
#   - parse JSON ด้วย jq (ของเดิมใช้ grep/sed พังทันทีถ้าค่ามี , : หรือ })
#   - token อยู่แค่ในตัวแปร shell ไม่ผ่าน Groovy string และ revoke ทันทีที่อ่านเสร็จ
#   - ไฟล์สิทธิ์ 600 และพิมพ์แค่ชื่อ key ไม่พิมพ์ค่า
# ใช้: ci/vault-env.sh dev/app-env "$WORKSPACE/.app.env"   (ต้องมี ROLE_ID / SECRET_ID ใน environment)
set -euo pipefail
path=$1; out=$2
V=${VAULT_ADDR:-http://vault:8200}

TOKEN=$(curl -sf -X POST -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" "$V/v1/auth/approle/login" | jq -r .auth.client_token)
trap 'curl -s -o /dev/null -X POST -H "X-Vault-Token: $TOKEN" "$V/v1/auth/token/revoke-self"' EXIT

body=$(curl -s -w '\n%{http_code}' -H "X-Vault-Token: $TOKEN" "$V/v1/secret/data/$path")
code=${body##*$'\n'}
if [ "$code" != 200 ]; then
  echo "[FAIL] อ่าน secret/$path ไม่ได้ HTTP $code" >&2
  exit 1
fi

umask 077
jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"' <<<"${body%$'\n'*}" > "$out"
echo "secret/$path -> $(basename "$out") ($(wc -l < "$out") keys: $(cut -d= -f1 "$out" | paste -sd' ' -))"
