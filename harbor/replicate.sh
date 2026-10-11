#!/usr/bin/env bash
# ให้ Harbor ดึง image ที่ pipeline push เข้า registry ของ workshop (LAB_HOST:5000) มาเก็บเองอัตโนมัติ
#   dev/glo-frontend:dev-build-N  ->  Harbor project dev
#   uat/glo-frontend:uat-build-N  ->  Harbor project uat
#   prd/glo-frontend:v1.2.0       ->  Harbor project prd
# Harbor สแกนทุก image ที่เข้ามา (auto scan) ดูผลได้ในหน้าเว็บ Harbor โดยไม่ต้องแก้ pipeline
#
# ใช้หลัง docker compose --profile harbor up -d (Harbor ต้อง healthy ก่อน) รันซ้ำได้ ของที่มีอยู่แล้วจะข้าม
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
HARBOR="http://localhost:${HARBOR_HTTP_PORT:-8085}/api/v2.0"
AUTH="admin:$HARBOR_ADMIN_PASSWORD"
SRC="http://$LAB_HOST:${REGISTRY_PORT:-5000}"

# อ่าน id ตัวบนสุดของรายการแรกใน JSON (python3 มีใน Ubuntu ทุกเครื่อง, Git Bash ใช้ python)
for PY in python3 python ""; do [ -n "$PY" ] && "$PY" -c '' 2>/dev/null && break; done
[ -n "$PY" ] || { echo "ต้องมี python3 (sudo apt install -y python3)"; exit 1; }
first_id() { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[0]["id"] if d else "")' /tmp/harbor-api.out; }

api() {  # method path [json]  -> พิมพ์ http code
  curl -s -o /tmp/harbor-api.out -w '%{http_code}' -u "$AUTH" -H 'Content-Type: application/json' -X "$1" "$HARBOR$2" ${3:+-d "$3"}
}

code=$(curl -s -o /dev/null -w '%{http_code}' "$HARBOR/ping" || true)
[ "$code" = 200 ] || { echo "Harbor ยังไม่พร้อม (ping ได้ $code) เปิดด้วย docker compose --profile harbor up -d แล้วรอสักครู่"; exit 1; }

echo "== project dev / uat / prd (สแกนอัตโนมัติเมื่อมี image เข้า)"
for p in dev uat prd; do
  c=$(api POST /projects "{\"project_name\":\"$p\",\"metadata\":{\"public\":\"false\",\"auto_scan\":\"true\"}}")
  case $c in 201) echo "   $p สร้างแล้ว";; 409) echo "   $p มีอยู่แล้ว";; *) echo "   $p ไม่สำเร็จ ($c) $(cat /tmp/harbor-api.out)"; exit 1;; esac
done

echo "== endpoint ของ registry workshop ($SRC)"
c=$(api POST /registries "{\"name\":\"workshop-registry\",\"type\":\"docker-registry\",\"url\":\"$SRC\",\"insecure\":true}")
case $c in 201) echo "   สร้างแล้ว";; 409) echo "   มีอยู่แล้ว";; *) echo "   ไม่สำเร็จ ($c) $(cat /tmp/harbor-api.out)"; exit 1;; esac
api GET "/registries?q=name%3Dworkshop-registry" >/dev/null
reg_id=$(first_id)
[ -n "$reg_id" ] || { echo "   หา id ของ endpoint ไม่เจอ: $(cat /tmp/harbor-api.out)"; exit 1; }

echo "== replication rule (ดึงทุก 2 นาที เฉพาะ dev/** uat/** prd/**)"
policy='{"name":"pipeline-images","description":"ดึง image ที่ pipeline push เข้า registry ของ workshop",
 "src_registry":{"id":'"$reg_id"'},"dest_namespace":"","dest_namespace_replace_count":-1,
 "filters":[{"type":"name","value":"{dev,uat,prd}/**"}],
 "trigger":{"type":"scheduled","trigger_settings":{"cron":"0 */2 * * * *"}},
 "override":true,"enabled":true,"speed":-1}'
c=$(api POST /replication/policies "$policy")
case $c in 201) echo "   สร้างแล้ว";; 409) echo "   มีอยู่แล้ว";; *) echo "   ไม่สำเร็จ ($c) $(cat /tmp/harbor-api.out)"; exit 1;; esac
api GET "/replication/policies?name=pipeline-images" >/dev/null
pol_id=$(first_id)

echo "== สั่งดึงรอบแรกทันที"
c=$(api POST /replication/executions "{\"policy_id\":$pol_id}")
[ "$c" = 201 ] && echo "   เริ่มแล้ว ดูความคืบหน้าที่ Harbor > Administration > Replications" || echo "   สั่งไม่สำเร็จ ($c) รอรอบอัตโนมัติภายใน 2 นาที"
rm -f /tmp/harbor-api.out
echo "เสร็จ: เปิด http://$LAB_HOST:${HARBOR_HTTP_PORT:-8085} > Projects > prd > glo-frontend"
