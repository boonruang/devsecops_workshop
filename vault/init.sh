#!/bin/sh
# ตั้งค่า Vault สำหรับ workshop: KV, audit log, policy, AppRole ของ Jenkins, secret ตั้งต้น
# entrypoint.sh เรียกทุกครั้งที่ Vault เปิด รันซ้ำได้ ไม่ทับ secret ที่ผู้เรียนใส่ไว้แล้ว
set -eu

echo "[init] KV v2 ที่ secret/"
vault secrets list | grep -q '^secret/' || vault secrets enable -path=secret kv-v2

# audit log: ทุก request ที่เข้า Vault (ใครขอ, path ไหน, ผ่านหรือไม่) ค่า secret ถูก hash ไม่เห็นตัวจริง
# ดูด้วย: docker compose exec vault sh /workshop/audit-view.sh
echo "[init] audit log"
vault audit list 2>/dev/null | grep -q '^file/' || vault audit enable file file_path=/vault/logs/audit.log

echo "[init] policy jenkins"
vault policy write jenkins /workshop/jenkins-policy.hcl >/dev/null

echo "[init] AppRole ของ Jenkins"
vault auth list | grep -q '^approle/' || vault auth enable approle
vault write auth/approle/role/jenkins \
  token_policies=jenkins token_ttl=20m token_max_ttl=1h secret_id_ttl=0 >/dev/null
# role_id / secret_id กำหนดตายตัวจาก .env ให้ credential ใน Jenkins ใช้ได้ทุกครั้งที่ restart
vault write auth/approle/role/jenkins/role-id role_id="$VAULT_JENKINS_ROLE_ID" >/dev/null
if ! vault write auth/approle/role/jenkins/secret-id/lookup secret_id="$VAULT_JENKINS_SECRET_ID" 2>/dev/null | grep -q secret_id_accessor; then
  vault write auth/approle/role/jenkins/custom-secret-id secret_id="$VAULT_JENKINS_SECRET_ID" >/dev/null
fi

echo "[init] secret ตั้งต้น (ใส่เฉพาะตัวที่ยังไม่มี)"
put_if_missing() {
  path="$1"; shift
  if vault kv get "$path" >/dev/null 2>&1; then
    echo "       $path มีอยู่แล้ว ข้าม"
  else
    vault kv put "$path" "$@" >/dev/null
    echo "       $path ใส่ค่าตั้งต้นแล้ว"
  fi
}
# ผู้เรียนต้องแทนค่า CHANGE-ME เองระหว่าง lab
put_if_missing secret/workshop/gitlab username=root password=CHANGE-ME
put_if_missing secret/workshop/sonar token=CHANGE-ME
put_if_missing secret/workshop/demo  db_password="demo-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')" api_key="key-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

# env ของ app แยกตาม environment แบบเดียวกับ secret/<env>/backend-env ของ glo-portal
# Jenkins เขียนทุก key ลง env-file แล้วส่งเข้า container ตอน deploy หน้าแรกของ app แสดง sha256 ของ APP_SECRET_KEY ไว้เทียบ
for env in dev uat prd; do
  put_if_missing "secret/$env/app-env" \
    APP_SECRET_KEY="$env-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
    APP_DB_HOST="db-$env.workshop.local" \
    APP_LOG_LEVEL="$( [ "$env" = prd ] && echo warning || echo debug )"
done

# secret ของทีมอื่น policy ตั้ง deny ไว้ ใช้สาธิตว่า Jenkins อ่านไม่ได้ (ให้ใน Vault เหลือแค่ dev/ uat/ prd/ workshop/)
put_if_missing secret/workshop/restricted/dba-db password="dba-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
