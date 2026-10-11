#!/bin/sh
# Vault แบบ server mode เก็บข้อมูลลง volume (restart แล้ว secret ไม่หาย)
# ครั้งแรก: init ด้วย unseal key 1 ชิ้น แล้วเก็บ key ไว้ใน volume
# ทุกครั้งที่เปิด: unseal เอง แล้วรัน init.sh (policy, AppRole, audit, secret ตั้งต้น)
# healthcheck จะผ่านก็ต่อเมื่อทุกขั้นเสร็จ Jenkins จึงไม่เริ่มก่อน Vault พร้อมจริง
#
# ⚠️ เก็บ unseal key ไว้ข้างข้อมูลแบบนี้ใช้ได้เฉพาะ workshop เท่านั้น
#    ของจริงต้องแบ่ง key หลายชิ้นให้หลายคนถือ หรือใช้ auto-unseal ผ่าน KMS
set -eu

export VAULT_ADDR=http://127.0.0.1:8200
INIT_FILE=/vault/file/workshop-init.txt
READY=/tmp/workshop-ready
rm -f "$READY"

vault server -config=/workshop/config.hcl &
PID=$!
trap 'kill -TERM "$PID"; wait "$PID"' TERM INT

# vault status: 0 = unsealed, 2 = sealed, อื่นๆ = ยังไม่พร้อม
until vault status >/dev/null 2>&1 || [ $? -eq 2 ]; do sleep 1; done

if vault status 2>/dev/null | grep -q 'Initialized *false'; then
  echo "[workshop] init Vault ครั้งแรก"
  vault operator init -key-shares=1 -key-threshold=1 > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
fi

UNSEAL_KEY=$(awk -F': ' '/Unseal Key 1/ {print $2}' "$INIT_FILE")
INIT_ROOT=$(awk -F': ' '/Initial Root Token/ {print $2}' "$INIT_FILE")
vault operator unseal "$UNSEAL_KEY" >/dev/null
echo "[workshop] unseal แล้ว"

# ให้ root token จาก .env (VAULT_ROOT_TOKEN) ใช้ได้ ผู้เรียนจะได้ไม่ต้องไปขุด token ที่ init สร้าง
if ! VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault token lookup >/dev/null 2>&1; then
  VAULT_TOKEN="$INIT_ROOT" vault token create -id="$VAULT_ROOT_TOKEN" -policy=root -orphan -display-name=workshop-root >/dev/null
  echo "[workshop] สร้าง root token จาก .env แล้ว"
fi

VAULT_TOKEN="$VAULT_ROOT_TOKEN" sh /workshop/init.sh
touch "$READY"
echo "[workshop] Vault พร้อมใช้งาน"

wait "$PID"
