#!/usr/bin/env bash
# ผู้สอนรันบนเครื่องที่ up ระบบได้แล้ว (มี image ครบ รวม jenkins ที่ build แล้ว)
# ได้ไฟล์ images/*.tar.gz หนึ่งไฟล์ต่อ image ไปแจกผู้เรียน (USB / file share)
# ผู้เรียนวางไว้ในโฟลเดอร์ images/ แล้วรัน bash setup.sh มันจะ docker load ให้เอง
#
# ทำไมต้องมี: Docker Hub ให้ pull แบบไม่ login ได้ 100 ครั้งต่อชั่วโมงต่อ IP ขาออก
# ห้องอบรม 20 เครื่องที่ออกเน็ต IP เดียวกัน ใช้คนละ ~10 image ชนเพดานตั้งแต่ชั่วโมงแรก
# และ jenkins ที่ build แล้วไม่ต้องโหลด plugin จาก internet อีก
#
# ถ้า docker save ของ image ไหนได้ไฟล์เปล่า (Docker Desktop แบบ containerd ทิ้ง layer หลังแตกไฟล์แล้ว)
# จะดึงจาก registry ตรงด้วย skopeo แทน (ใช้ pull 1 ครั้ง)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p images

mapfile -t imgs < <(docker compose --profile all config --images | sort -u)
for img in "${imgs[@]}"; do
  docker image inspect "$img" >/dev/null 2>&1 || { echo "ไม่มี $img ในเครื่อง: docker compose --profile all pull แล้ว build ก่อน"; exit 1; }
done

for img in "${imgs[@]}"; do
  name=$(echo "$img" | tr '/:' '__')
  out="images/$name.tar.gz"
  if [ -s "$out" ]; then echo "มีแล้ว  $out"; continue; fi
  echo "บันทึก  $img"
  if docker save --platform linux/amd64 "$img" 2>/dev/null | gzip -1 > "$out.part" && [ "$(stat -c %s "$out.part")" -gt 1000000 ]; then
    mv "$out.part" "$out"
  else
    rm -f "$out.part"
    case "$img" in devsecops_workshop/*) echo "docker save $img ไม่ได้ และเป็น image ที่ build เอง ดึงจาก registry ไม่ได้"; exit 1;; esac
    echo "        docker save ได้ไฟล์เปล่า ดึงจาก registry ด้วย skopeo แทน"
    docker run --rm -v "$PWD/images:/out" quay.io/skopeo/stable:v1.20.0 copy -q \
      --override-os linux --override-arch amd64 \
      "docker://docker.io/$img" "docker-archive:/out/$name.tar:$img"
    gzip -1 "images/$name.tar"
  fi
done

( cd images && sha256sum ./*.tar.gz > SHA256SUMS )
ls -lh images
du -sh images
