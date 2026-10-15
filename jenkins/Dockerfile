# Jenkins พร้อม CLI ที่ pipeline ใช้ ไม่ต้องมี docker daemon หรือ privileged container
# build ทำผ่าน buildkitd, deploy สั่ง docker daemon ของ deploy-host, เครื่องมืออื่นเรียก server กลางใน compose
FROM moby/buildkit:v0.33.1 AS buildkit
FROM aquasec/trivy:0.75.0 AS trivy
# helm ไม่มี image ทางการ โหลด binary จาก get.helm.sh (แหล่งทางการ) แล้วตรวจ sha256 ก่อนใช้
FROM alpine:3.22 AS helm
ARG TARGETARCH=amd64
ARG HELM_VERSION=v3.22.0
RUN cd /tmp && f=helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz \
 && wget -q https://get.helm.sh/$f https://get.helm.sh/$f.sha256sum \
 && sha256sum -c $f.sha256sum \
 && tar xzf $f && mv linux-${TARGETARCH}/helm /usr/bin/helm
FROM sonarsource/sonar-scanner-cli:12.2.0.4256_8.1.0 AS scanner
FROM docker:29.8.2-cli AS dockercli

FROM jenkins/jenkins:2.580.1-lts-jdk21
USER root
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
COPY --from=trivy    /usr/local/bin/trivy /usr/local/bin/trivy
# template ที่ trivy ใช้สร้าง report HTML (ci/trivy-gate.sh)
COPY --from=trivy    /contrib/html.tpl /opt/trivy/html.tpl
COPY --from=helm     /usr/bin/helm /usr/local/bin/helm
COPY --from=scanner  /opt/sonar-scanner /opt/sonar-scanner
# docker CLI อย่างเดียว ไม่มี daemon: ใช้สั่ง deploy-host ผ่าน DOCKER_HOST
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
# jq ใช้ใน stage สาธิต Vault (อ่าน JSON จาก Vault HTTP API)
RUN apt-get update && apt-get install -y --no-install-recommends jq && rm -rf /var/lib/apt/lists/* \
 && ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner
USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
