#!/usr/bin/env bash
# เตรียมเครื่อง Linux (ทดสอบกับ Ubuntu 24.04) ให้พร้อมรัน workshop
#   1) ตรวจ docker + compose และสิทธิ์ของ user
#   2) ตรวจ RAM / CPU / ดิสก์
#   3) ตั้ง vm.max_map_count ให้ SonarQube (ถาวร)
#   4) สร้าง .env: หา IP ของเครื่องเอง และสุ่มรหัสทุกช่อง (ถ้ามี .env อยู่แล้วจะไม่ทับ แค่ตรวจ LAB_HOST)
#   5) โหลด image จากไฟล์ offline ถ้ามี (images/*.tar.gz), สร้าง config ของ Harbor, แล้วเช็คว่า image ครบไหม
#   6) ตรวจว่าออกเน็ตไปที่ที่ workshop ต้องใช้ได้ไหม
#
# ใช้:  bash setup.sh                      (หา IP เอง)
#       LAB_HOST=10.1.2.3 bash setup.sh    (กำหนด IP เอง เช่นเครื่องมีหลายการ์ดแลน)
set -euo pipefail
cd "$(dirname "$0")"

ok()   { printf '  \033[32m[OK]\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33m[WARN]\033[0m %s\n' "$*"; WARNS=$((WARNS+1)); }
fail() { printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; exit 1; }
WARNS=0
rand() { head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-"$1"; }

echo "== 1. docker"
command -v docker >/dev/null || fail "ยังไม่มี docker ติดตั้งด้วย:
         sudo apt update && sudo apt install -y docker.io docker-compose-v2
         sudo usermod -aG docker \$USER     แล้ว logout / login ใหม่ 1 ครั้ง"
docker info >/dev/null 2>&1 || fail "user นี้สั่ง docker ไม่ได้: sudo usermod -aG docker \$USER แล้ว logout / login ใหม่
         (หรือ docker ยังไม่รัน: sudo systemctl enable --now docker)"
docker compose version >/dev/null 2>&1 || fail "ไม่มี docker compose v2: sudo apt install -y docker-compose-v2"
ok "docker $(docker version -f '{{.Server.Version}}'), compose $(docker compose version --short)"

echo "== 2. ทรัพยากรเครื่อง"
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024 + 0.5}' /proc/meminfo)
cpus=$(nproc)
root_dir=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)
disk_gb=$(df -BG --output=avail "$root_dir" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
[ "$mem_gb" -ge 12 ] && ok "RAM ${mem_gb} GB" || warn "RAM ${mem_gb} GB น้อยกว่า 12 GB เปิดครบทุกตัวแล้ว GitLab / SonarQube อาจหยุดเอง (แนะนำ 16 GB)"
[ "$cpus" -ge 4 ] && ok "CPU ${cpus} core" || warn "CPU ${cpus} core GitLab เปิดครั้งแรกจะช้ามาก (แนะนำ 4 core ขึ้นไป)"
[ "${disk_gb:-0}" -ge 40 ] && ok "ดิสก์ว่าง ${disk_gb} GB ที่ $root_dir" || warn "ดิสก์ว่าง ${disk_gb} GB ที่ $root_dir (image + data ใช้ประมาณ 30-40 GB)"

echo "== 3. vm.max_map_count (SonarQube)"
cur=$(sysctl -n vm.max_map_count)
if [ "$cur" -ge 524288 ]; then
  ok "vm.max_map_count = $cur"
else
  echo "       ตอนนี้ $cur ต้องการ 524288 ขอ sudo เพื่อตั้งค่าแบบถาวร"
  sudo sysctl -q -w vm.max_map_count=524288
  echo 'vm.max_map_count=524288' | sudo tee /etc/sysctl.d/99-devsecops-workshop.conf >/dev/null
  ok "ตั้งแล้ว และจะคงอยู่หลัง reboot (/etc/sysctl.d/99-devsecops-workshop.conf)"
fi

# vault / jenkins อ่านไฟล์ที่ mount เข้าไปด้วย uid ของตัวเอง ไฟล์ต้องอ่านได้ทุกคน (กันกรณี umask 077)
chmod -R a+rX vault jenkins

echo "== 4. .env"
detect_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="src") {print $(i+1); exit}}'
}
# IP ของการ์ดแลนจริง ไม่นับ bridge ที่ docker สร้างเอง (docker0, br-xxxx) ไม่งั้นทุกเครื่องจะดูเหมือนมีหลาย IP
host_ips() { ip -4 -o addr show scope global 2>/dev/null | awk '$2 !~ /^(docker0|br-|veth|virbr)/ {split($4, a, "/"); print a[1]}' | xargs; }
local_ips=" $(host_ips) "
if [ ! -f .env ]; then
  host_ip=${LAB_HOST:-$(detect_ip)}
  [ -n "$host_ip" ] || host_ip=$(host_ips | awk '{print $1}')
  [ -n "$host_ip" ] || fail "หา IP ของเครื่องไม่เจอ ใส่เอง: LAB_HOST=x.x.x.x bash setup.sh"
  cp .env.example .env
  set_env() { sed -i "s|^$1=.*|$1=$2|" .env; }
  set_env LAB_HOST "$host_ip"
  set_env GITLAB_ROOT_PASSWORD "Gl$(rand 22)"
  set_env JENKINS_ADMIN_PASSWORD "$(rand 20)"
  set_env SONAR_DB_PASSWORD "$(rand 20)"
  # SonarQube บังคับรหัส 12 ตัวขึ้นไป มีตัวใหญ่ เล็ก ตัวเลข และอักขระพิเศษ ใช้ค่านี้ตอนเปลี่ยนรหัสครั้งแรกในหน้าเว็บ
  set_env SONAR_ADMIN_PASSWORD "'Sq1!$(rand 18)'"
  set_env VAULT_ROOT_TOKEN "root-$(rand 24)"
  set_env VAULT_JENKINS_SECRET_ID "$(rand 32)"
  # Harbor บังคับรหัส admin มีตัวใหญ่ ตัวเล็ก และตัวเลข
  set_env HARBOR_ADMIN_PASSWORD "Hb1$(rand 20)"
  set_env HARBOR_DB_PASSWORD "$(rand 20)"
  chmod 600 .env
  ok "สร้าง .env แล้ว LAB_HOST=$host_ip รหัสทุกช่องสุ่มใหม่"
  case "$(host_ips | wc -w)" in
    1) ;;
    *) warn "เครื่องนี้มีหลาย IP ($(host_ips)) ถ้าเบราว์เซอร์เปิด http://$host_ip:8929 ไม่ได้
         ให้ลบ .env แล้วรันใหม่ด้วย LAB_HOST=<IP ที่ถูก> bash setup.sh (ต้องทำก่อน up ครั้งแรก)" ;;
  esac
else
  env_ip=$(sed -n 's/^LAB_HOST=//p' .env | tr -d "'\"")
  if [[ "$local_ips" == *" $env_ip "* ]]; then
    ok ".env มีอยู่แล้ว LAB_HOST=$env_ip ตรงกับเครื่องนี้"
  else
    warn ".env มีอยู่แล้ว แต่ LAB_HOST=$env_ip ไม่ใช่ IP ของเครื่องนี้ ($(host_ips))
         ยังไม่เคย up: ลบ .env แล้วรัน bash setup.sh ใหม่
         up ไปแล้ว: แก้ LAB_HOST ใน .env แล้ว docker compose --profile all up -d (GitLab จะ reconfigure เอง)"
  fi
fi

# .env ที่สร้างก่อนมี Harbor ยังไม่มีค่าของ Harbor: เติมให้ ไม่แตะค่าอื่น
if ! grep -q '^HARBOR_ADMIN_PASSWORD=' .env; then
  printf '
# ---- Harbor (เติมโดย setup.sh) ----
HARBOR_HTTP_PORT=8085
HARBOR_ADMIN_PASSWORD=Hb1%s
HARBOR_DB_PASSWORD=%s
' "$(rand 20)" "$(rand 20)" >> .env
  ok "เติมค่าของ Harbor ลง .env แล้ว"
fi

echo "== 5. image + config ของ Harbor"
shopt -s nullglob
for b in images/*.tar.gz; do
  mark="images/.loaded-$(basename "$b")"
  # โหลดแล้วข้าม (ไฟล์ gitlab ใหญ่ 1.5 GB โหลดซ้ำเสียเวลาเปล่า) ลบ images/.loaded-* ถ้าต้องการโหลดใหม่
  if [ -f "$mark" ]; then echo "       ข้าม $b (โหลดไปแล้ว)"; continue; fi
  echo "       โหลด $b"
  docker load -q -i "$b" | sed 's/^/       /'
  touch "$mark" 2>/dev/null || true   # images/ อาจเป็น USB แบบอ่านอย่างเดียว
done
# Harbor ต้องมี config ที่สร้างจาก .env ก่อน compose ถึงจะอ่าน service ของ Harbor ได้
if bash harbor/prepare.sh >/dev/null 2>harbor-prepare.err; then
  rm -f harbor-prepare.err
  ok "สร้าง config ของ Harbor แล้ว (harbor/generated/)"
  profiles="--profile all --profile harbor"
else
  warn "สร้าง config ของ Harbor ไม่ได้ (ดู harbor-prepare.err) ส่วนอื่นของ workshop ใช้ได้ตามปกติ"
  profiles="--profile all"
fi
# อ่านรายการ image จาก compose (ต้องมี .env แล้ว ไม่งั้นตัวแปรบังคับทำให้ config พัง)
images_list=$(docker compose $profiles config --images 2>&1) || fail "docker compose อ่าน docker-compose.yml ไม่ได้:
$images_list"
[ -n "$images_list" ] || fail "docker compose ไม่คืนรายการ image เลย ตรวจ docker-compose.yml"
missing=()
for img in $images_list goharbor/prepare:v2.14.2; do
  docker image inspect "$img" >/dev/null 2>&1 || missing+=("$img")
done
if [ ${#missing[@]} -eq 0 ]; then
  ok "image ครบทั้ง $(( $(echo $images_list | wc -w) + 1 )) ตัว เปิดระบบได้โดยไม่ต้อง pull"
  NEED_BUILD=""
else
  warn "ยังไม่มี image ${#missing[@]} ตัว ตอน up จะ pull จาก internet (และ build Jenkins): ${missing[*]}"
  NEED_BUILD=" --build"
fi

echo "== 6. ออก internet"
check() {  # ชื่อ  url  ใช้ทำอะไร
  code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "$2" 2>/dev/null || true)
  if [ "$code" != "000" ] && [ -n "$code" ]; then ok "$1"; else warn "$1 ออกไม่ได้: $3"; fi
}
if ! command -v curl >/dev/null; then
  warn "ไม่มี curl ข้ามการตรวจ (sudo apt install -y curl)"
else
  [ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ] && warn "เครื่องนี้ใช้ proxy: docker daemon ต้องตั้ง proxy แยก (README หัวข้อ เครือข่ายของลูกค้า)"
  check "Docker Hub"   https://registry-1.docker.io/v2/  "pull image และ BuildKit ดึง python:3.12-slim ตอน build sample-app"
  check "mirror.gcr.io" https://mirror.gcr.io/v2/        "Trivy โหลดฐานข้อมูลช่องโหว่ (Gate 2, 3 จะตก)"
  check "ghcr.io"      https://ghcr.io/v2/               "ทางสำรองของฐานข้อมูล Trivy"
  check "pypi.org"     https://pypi.org/simple/          "pip install ตอน build sample-app"
  if [ -n "$NEED_BUILD" ]; then
    check "Jenkins plugins" https://updates.jenkins.io/update-center.json "build image ของ Jenkins (ใช้ไฟล์ offline แทนได้)"
  fi
  tok=$(curl -fsS -m 10 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" 2>/dev/null | sed -n 's/.*"token":"\([^"]*\)".*/\1/p' || true)
  if [ -n "$tok" ]; then
    left=$(curl -fsS -m 10 -I -H "Authorization: Bearer $tok" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>/dev/null \
           | tr -d '\r' | sed -n 's/^ratelimit-remaining: *\([0-9]*\).*/\1/Ip' | head -1 || true)
    if [ -n "$left" ]; then
      if [ "$left" -ge 20 ] || [ ${#missing[@]} -eq 0 ]; then ok "Docker Hub เหลือ pull ได้อีก $left ครั้งในชั่วโมงนี้ (นับต่อ IP ขาออก)"
      else warn "Docker Hub เหลือ pull ได้อีก $left ครั้งในชั่วโมงนี้ ไม่พอ ให้ใช้ไฟล์ image offline"; fi
    fi
  fi
fi

lab=$(sed -n 's/^LAB_HOST=//p' .env | tr -d "'\"")
echo
echo "เสร็จแล้ว (คำเตือน $WARNS ข้อ) เปิดระบบด้วย:"
echo "  docker compose --profile all up -d$NEED_BUILD"
echo
echo "รอ GitLab ประมาณ 5 นาที แล้วเปิด:"
echo "  GitLab    http://$lab:8929   root / ดู GITLAB_ROOT_PASSWORD ใน .env"
echo "  Jenkins   http://$lab:8080   admin / ดู JENKINS_ADMIN_PASSWORD ใน .env"
echo "  SonarQube http://$lab:9000   admin / admin แล้วเปลี่ยนเป็น SONAR_ADMIN_PASSWORD ใน .env"
echo "  Vault     http://$lab:8200   Token = VAULT_ROOT_TOKEN ใน .env"
echo
echo "Harbor (เปิดแยก): docker compose --profile harbor up -d"
echo "  Harbor    http://$lab:$(sed -n 's/^HARBOR_HTTP_PORT=//p' .env)   admin / ดู HARBOR_ADMIN_PASSWORD ใน .env"
