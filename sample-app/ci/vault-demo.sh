#!/bin/bash
# สาธิตทีละขั้นว่า Jenkins เอา secret มาจาก Vault อย่างไร โดยยิง Vault HTTP API เอง ให้เห็น request จริงทุกตัว
# ต้องมี ROLE_ID / SECRET_ID ใน environment (Jenkinsfile ส่งมาจาก credential vault-approle-cli)
# ENV_NAME (dev/uat/prd) บอกว่าจะอ่าน secret ของ env ไหน ถ้าไม่มีจะอ่านแค่ของ workshop
# ฝั่ง Vault ดูคู่กันได้: docker compose exec vault sh /workshop/audit-view.sh -f
set -euo pipefail
V=${VAULT_ADDR:-http://vault:8200}
hr() { printf '\n──── %s ────\n' "$1"; }
fp() { printf '%s' "$1" | sha256sum | cut -c1-12; }

hr "A1  POST $V/v1/auth/approle/login"
echo "ส่ง role_id + secret_id (Jenkins ปิดเป็น ****): role_id=$ROLE_ID secret_id=$SECRET_ID"
LOGIN=$(curl -sf -X POST -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" "$V/v1/auth/approle/login")
TOKEN=$(jq -r .auth.client_token <<<"$LOGIN")
echo "ได้ token ชั่วคราวกลับมา (ไม่พิมพ์ตัว token) รายละเอียด:"
jq '{token_policies: .auth.token_policies, ttl_seconds: .auth.lease_duration, renewable: .auth.renewable, accessor: .auth.accessor}' <<<"$LOGIN"

echo "(sha256 คือ fingerprint ไว้เทียบกับค่าใน Vault โดยไม่ต้องเปิดเผยค่าจริง วิธีเทียบดู README)"
paths="workshop/demo workshop/sonar"
[ -n "${ENV_NAME:-}" ] && paths="$paths $ENV_NAME/app-env"
for p in $paths; do
  hr "A2  GET $V/v1/secret/data/$p"
  R=$(curl -sf -H "X-Vault-Token: $TOKEN" "$V/v1/secret/data/$p")
  jq '{version: .data.metadata.version, created_time: .data.metadata.created_time, keys: (.data.data | keys)}' <<<"$R"
  for k in $(jq -r '.data.data | keys[]' <<<"$R"); do
    val=$(jq -r --arg k "$k" '.data.data[$k]' <<<"$R")
    echo "  $k: ได้ค่ามาแล้ว ยาว ${#val} ตัวอักษร · sha256 ${val:+$(fp "$val")}"
  done
done

hr "A3  GET $V/v1/secret/data/workshop/restricted/dba-db   (policy ตั้ง deny ไว้)"
deny=$(mktemp)
code=$(curl -s -o "$deny" -w '%{http_code}' -H "X-Vault-Token: $TOKEN" "$V/v1/secret/data/workshop/restricted/dba-db")
echo "HTTP $code $(jq -c .errors "$deny")"
[ "$code" = 403 ] && echo "ถูกต้อง: Jenkins อ่าน secret ของทีมอื่นไม่ได้"

hr "A4  POST $V/v1/secret/data/workshop/sonar   (ลองเขียนทับ)"
code=$(curl -s -o "$deny" -w '%{http_code}' -X POST -H "X-Vault-Token: $TOKEN" -d '{"data":{"token":"hacked"}}' "$V/v1/secret/data/workshop/sonar")
echo "HTTP $code $(jq -c .errors "$deny")"
[ "$code" = 403 ] && echo "ถูกต้อง: policy ให้แค่ read Jenkins แก้ secret ไม่ได้"
rm -f "$deny"

hr "A5  POST $V/v1/auth/token/revoke-self"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "X-Vault-Token: $TOKEN" "$V/v1/auth/token/revoke-self")
echo "HTTP $code ยกเลิก token ทันทีที่ใช้เสร็จ"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "X-Vault-Token: $TOKEN" "$V/v1/secret/data/workshop/demo")
echo "ลองใช้ token เดิมอีกครั้ง: HTTP $code (ใช้ไม่ได้แล้ว)"
