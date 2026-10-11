#!/usr/bin/env bash
# Gate 4: OWASP ZAP baseline scan (DAST) กับ app ที่ deploy แล้ว
# ใช้: bash ci/zap-gate.sh <target-url> <ระดับที่ทำให้ตก: High|Medium|Low|none>
#
# ทำแบบเดียวกับ zap-baseline.py: spider หา URL แล้วรอ passive scan (ดู request/response ไม่ส่ง payload โจมตี)
# สั่งผ่าน API ของ ZAP daemon ใน compose (ZAP_URL) Jenkins จึงไม่ต้องรัน container เอง
# ผลลัพธ์ (เก็บกับ build เหมือน Trivy):
#   reports/zap.html  report อ่านง่าย ดูในเมนู ZAP Report ของหน้า build
#   reports/zap.json  ผลดิบ ส่งต่อเครื่องมืออื่นได้
#
# baseline ไม่ยิง payload จึงไม่เจอ SQL injection ใน /tickets ต้องใช้ active scan (full scan) ซึ่งช้ากว่าและห้ามยิงใส่ระบบจริงโดยไม่ได้รับอนุญาต
set -euo pipefail
TARGET=${1:?ใส่ URL ของ app เช่น http://deploy-host:8088}
FAIL_ON=${2:-High}
ZAP=${ZAP_URL:-http://zap:8080}
MAX_SPIDER_SEC=${ZAP_SPIDER_SEC:-60}
mkdir -p reports

# ZAP daemon มีตัวเดียวใช้ร่วมกันทุก build ถ้า 2 build สแกนพร้อมกัน (เช่น push uat แล้วติด tag ทันที)
# newSession ของตัวหลังจะล้างงานของตัวแรกและได้ 500 จึงต่อคิวด้วย flock (ทุก build รันใน container Jenkins เดียวกัน)
LOCK="${JENKINS_HOME:-/tmp}/zap-gate.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "ZAP กำลังสแกนให้ build อื่นอยู่ รอคิว (สูงสุด 15 นาที)"
  flock -w 900 9 || { echo "รอคิว ZAP นานเกิน 15 นาที"; exit 1; }
fi

api() { curl -fsS --max-time 30 "$ZAP/$1"; }
enc() { jq -rn --arg v "$1" '$v|@uri'; }

echo "ZAP $(api JSON/core/view/version/ | jq -r .version) ที่ $ZAP  เป้าหมาย $TARGET  ตกเมื่อเจอ $FAIL_ON ขึ้นไป"

# เริ่ม session ใหม่ทุกครั้ง ผลของ build ก่อนจะได้ไม่ปนมา
api "JSON/core/action/newSession/?overwrite=true" >/dev/null
api "JSON/core/action/accessUrl/?url=$(enc "$TARGET")&followRedirects=true" >/dev/null

echo "--- spider (สูงสุด ${MAX_SPIDER_SEC} วินาที)"
sid=$(api "JSON/spider/action/scan/?url=$(enc "$TARGET")&recurse=true&subtreeOnly=true" | jq -r .scan)
for ((i = 0; i < MAX_SPIDER_SEC; i += 2)); do
  p=$(api "JSON/spider/view/status/?scanId=$sid" | jq -r .status)
  [ "$p" -ge 100 ] && break
  sleep 2
done
[ "$p" -ge 100 ] || api "JSON/spider/action/stop/?scanId=$sid" >/dev/null
echo "    เจอ $(api "JSON/spider/view/results/?scanId=$sid" | jq '.results | length') URL"

echo "--- รอ passive scan"
for ((i = 0; i < 120; i += 2)); do
  left=$(api JSON/pscan/view/recordsToScan/ | jq -r .recordsToScan)
  [ "$left" -eq 0 ] && break
  sleep 2
done

api OTHER/core/other/htmlreport/ > reports/zap.html
api OTHER/core/other/jsonreport/ > reports/zap.json

# นับตามระดับ เฉพาะ alert ของเป้าหมายนี้
summary=$(api "JSON/alert/view/alertsSummary/?baseurl=$(enc "$TARGET")" | jq -c .alertsSummary)
high=$(jq -r '.High // 0' <<<"$summary"); med=$(jq -r '.Medium // 0' <<<"$summary")
low=$(jq -r '.Low // 0' <<<"$summary"); info=$(jq -r '.Informational // 0' <<<"$summary")
echo "ผลทุกระดับ: High=$high  Medium=$med  Low=$low  Informational=$info"

echo "--- รายการ alert (ชื่อ / ระดับ / จำนวน URL)"
jq -r '[.site[]?.alerts[]?] | sort_by(-(.riskcode|tonumber)) | .[] | "  [\(.riskdesc | split(" ")[0])] \(.name)  (\(.instances | length) URL)"' reports/zap.json | head -30

case "$FAIL_ON" in
  High)   bad=$high ;;
  Medium) bad=$((high + med)) ;;
  Low)    bad=$((high + med + low)) ;;
  none)   bad=0 ;;
  *) echo "FAIL_ON ต้องเป็น High, Medium, Low หรือ none"; exit 2 ;;
esac
if [ "$bad" -gt 0 ]; then
  echo "Gate 4 ไม่ผ่าน: เจอ alert ระดับ $FAIL_ON ขึ้นไป $bad รายการ (ดู ZAP Report ในหน้า build)"
  exit 1
fi
echo "Gate 4 ผ่าน"
