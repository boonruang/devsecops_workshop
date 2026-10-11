#!/bin/sh
# อ่าน audit log ของ Vault ให้คนอ่านรู้เรื่อง: เวลา · ใคร · ทำอะไร · path · ผล
#   docker compose exec vault sh /workshop/audit-view.sh        # 40 รายการล่าสุด
#   docker compose exec vault sh /workshop/audit-view.sh -f     # ดูสดระหว่าง Jenkins รัน
# ค่า secret ใน audit log ถูก hash (hmac-sha256) ไว้แล้ว ไฟล์นี้ไม่มีค่าจริงหลุดออกมา
LOG=/vault/logs/audit.log

field() { echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }

show() {
  while IFS= read -r line; do
    case "$line" in *'"type":"response"'*) ;; *) continue ;; esac
    path=$(field "$line" path)
    case "$path" in sys/*) continue ;; esac   # ข้าม health/status ที่ healthcheck ยิงทุก 5 วินาที
    t=$(field "$line" time | cut -c12-19)
    op=$(field "$line" operation)
    who=$(field "$line" display_name)
    pol=$(echo "$line" | grep -o '"policies":\[[^]]*\]' | head -1 | sed 's/"policies"://; s/"//g')
    err=$(field "$line" error)
    # "1 error occurred:\n\t* permission denied\n\n" -> "permission denied"
    err=$(echo "$err" | sed 's/^[0-9]* errors* occurred://; s/\\n\\t\* /, /g; s/\\n//g; s/^, //')
    if [ -n "$err" ]; then res="DENIED ($err)"; else res="OK"; fi
    printf '%s  %-16s %-7s %-34s %s %s\n' "$t" "${who:--}" "$op" "$path" "$res" "$pol"
  done
}

printf '%s  %-16s %-7s %-34s %s\n' "TIME" "WHO" "OP" "PATH" "RESULT POLICIES"
if [ "${1:-}" = "-f" ]; then
  tail -n 0 -F "$LOG" | show
else
  tail -n 400 "$LOG" | show | tail -n 40
fi
