#!/bin/bash
# สแกนครั้งเดียว แล้วแตกผลเป็น 3 อย่าง:
#   reports/<name>.json  ผลดิบทุกระดับความรุนแรง (archive ไว้ใน Jenkins)
#   reports/<name>.html  report ให้คนอ่าน เปิดจากเมนู "Trivy Report" ของ build
#   ตารางใน console      เฉพาะระดับที่ gate สนใจ และ exit 1 ถ้าเจอ
# ใช้: ci/trivy-gate.sh <name> <severity ที่ทำให้ตก> <คำสั่ง trivy...>
#   ci/trivy-gate.sh trivy-fs    HIGH,CRITICAL fs .
#   ci/trivy-gate.sh trivy-image CRITICAL      image --insecure "$IMAGE:$IMAGE_TAG"
set -uo pipefail
name=$1; severity=$2; shift 2
mkdir -p reports

trivy "$@" --server "$TRIVY_SERVER" --format json --output "reports/$name.json" --quiet || exit 2
trivy convert --format template --template @/opt/trivy/html.tpl --output "reports/$name.html" "reports/$name.json"

echo "ผลทุกระดับ: $(jq -r '[.Results[]?.Vulnerabilities[]?.Severity] | group_by(.) | map("\(.[0])=\(length)") | join("  ") | if .=="" then "ไม่เจอช่องโหว่" else . end' "reports/$name.json")"
echo "gate ตกเมื่อเจอ: $severity"
trivy convert --format table --severity "$severity" --exit-code 1 "reports/$name.json"
