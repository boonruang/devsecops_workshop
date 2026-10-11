#!/usr/bin/env bash
# สร้าง config + key ของ Harbor จาก .env ด้วย goharbor/prepare (ตัวเดียวกับที่ install.sh ของ Harbor เรียก)
# ผลลัพธ์อยู่ใน harbor/generated/ (gitignore ไว้ เพราะมี secret ของเครื่องนี้) docker-compose.yml mount จากที่นี่
#
# รันซ้ำได้: key เดิมใน generated/secret ถูกใช้ต่อ ไม่สร้างใหม่ (สร้างใหม่ = login / token เดิมใช้ไม่ได้)
# ต้องรันใหม่เมื่อเปลี่ยน LAB_HOST หรือ HARBOR_HTTP_PORT ใน .env แล้ว docker compose --profile harbor up -d --force-recreate
#
# ไฟล์ใน generated/config และ generated/secret เป็นของ root / uid 10000 (Harbor ต้องการแบบนั้น)
# การจัดไฟล์ทั้งหมดจึงทำใน container ถ้าจะลบทิ้งต้องใช้ sudo rm -rf harbor/generated
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "ยังไม่มี .env รัน bash setup.sh ก่อน"; exit 1; }
set -a; . ./.env; set +a
: "${LAB_HOST:?ตั้ง LAB_HOST ใน .env}" "${HARBOR_ADMIN_PASSWORD:?ตั้ง HARBOR_ADMIN_PASSWORD ใน .env}" "${HARBOR_DB_PASSWORD:?ตั้ง HARBOR_DB_PASSWORD ใน .env}"
HARBOR_HTTP_PORT=${HARBOR_HTTP_PORT:-8085}

gen=harbor/generated
mkdir -p "$gen"
( umask 077
  sed -e "s|__LAB_HOST__|$LAB_HOST|g" -e "s|__HARBOR_HTTP_PORT__|$HARBOR_HTTP_PORT|g" \
      -e "s|__HARBOR_ADMIN_PASSWORD__|$HARBOR_ADMIN_PASSWORD|g" -e "s|__HARBOR_DB_PASSWORD__|$HARBOR_DB_PASSWORD|g" \
      harbor/harbor.yml.tpl > "$gen/harbor.yml" )

# prepare สุ่มรหัสภายในใหม่ทุกครั้ง (core secret, รหัสที่ core ใช้คุยกับ registry ฯลฯ) และไฟล์ที่ mount อยู่เปลี่ยนทันที
# ถ้า Harbor เปิดอยู่จะได้ 401 ทั่วระบบจนกว่าจะ recreate จึงสร้างใหม่เฉพาะเมื่อค่าใน .env หรือ template เปลี่ยน
sum=$(sha256sum "$gen/harbor.yml" | cut -c1-64)
if [ -f "$gen/config/core/env" ] && [ "$(cat "$gen/.input.sha256" 2>/dev/null)" = "$sum" ] && [ "${1:-}" != "--force" ]; then
  echo "Harbor config เดิมยังใช้ได้ (ค่าใน .env ไม่เปลี่ยน) ข้าม  [สร้างใหม่: bash harbor/prepare.sh --force]"
  exit 0
fi
regen=0; [ -f "$gen/config/core/env" ] && regen=1

# Git Bash บน Windows ต้องส่ง path แบบ C:/... ให้ docker
here=$(pwd -W 2>/dev/null || pwd)
# ใน container: prepare อ่าน /input เขียน config ลง /config เขียน key ลง /data/secret
# เราเก็บแค่ config กับ secret ส่วนข้อมูลจริงของ Harbor อยู่ใน named volume ของ compose
# ไฟล์ */env ตัว docker compose (รันเป็น user เรา) ต้องอ่านเองตอน up จึง chown ให้ user ที่รันสคริปต์ (สิทธิ์ 600 คงเดิม)
# ไฟล์อื่น container ของ Harbor อ่านผ่าน bind mount ด้วย uid ของมันเอง ปล่อยตามที่ prepare ตั้ง
MSYS_NO_PATHCONV=1 docker run --rm -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -v "$here/$gen:/gen" \
  --entrypoint sh goharbor/prepare:v2.14.2 -c '
  set -e
  mkdir -p /input /data /compose_location /gen/config
  cp /gen/harbor.yml /input/harbor.yml
  [ -d /gen/secret/keys ] && cp -a /gen/secret /data/
  rm -rf /config && ln -s /gen/config /config
  python3 main.py prepare --with-trivy
  rm -rf /gen/secret && cp -a /data/secret /gen/secret
  chown "$HOST_UID:$HOST_GID" /gen/config/*/env
' >"$gen/prepare.log" 2>&1 || { tail -20 "$gen/prepare.log"; exit 1; }
echo "$sum" > "$gen/.input.sha256"

echo "Harbor config พร้อม: http://$LAB_HOST:$HARBOR_HTTP_PORT  (admin / HARBOR_ADMIN_PASSWORD ใน .env)"
if [ "$regen" = 1 ]; then
  echo "สร้าง config ใหม่ทับของเดิม ถ้า Harbor เปิดอยู่ต้องสั่ง: docker compose --profile harbor up -d --force-recreate"
fi
