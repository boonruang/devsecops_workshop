# ต้นแบบ config ของ Harbor สำหรับ workshop (harbor/prepare.sh เติมค่าจาก .env แล้วส่งให้ goharbor/prepare)
# ตัดมาจาก harbor.yml.tmpl ของ harbor-online-installer-v2.14.2 เหลือเฉพาะที่ใช้ และใช้ http ไม่มี cert (เฉพาะ lab)
# ของจริงที่ลูกค้าใช้เปิด https 443 พร้อม cert
hostname: __LAB_HOST__
http:
  port: 8080
external_url: http://__LAB_HOST__:__HARBOR_HTTP_PORT__
harbor_admin_password: __HARBOR_ADMIN_PASSWORD__
database:
  password: __HARBOR_DB_PASSWORD__
  max_idle_conns: 100
  max_open_conns: 900
  conn_max_lifetime: 5m
  conn_max_idle_time: 0
data_volume: /data
trivy:
  ignore_unfixed: false
  skip_update: false
  skip_java_db_update: false
  offline_scan: false
  security_check: vuln
  insecure: false
  timeout: 5m0s
jobservice:
  max_job_workers: 4
  max_job_duration_hours: 24
  job_loggers:
    - STD_OUTPUT
  logger_sweeper_duration: 1
notification:
  webhook_job_max_retry: 3
  webhook_job_http_client_timeout: 3
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor
_version: 2.14.0
proxy:
  http_proxy:
  https_proxy:
  no_proxy:
  components:
    - core
    - jobservice
    - trivy
upload_purging:
  enabled: true
  age: 168h
  interval: 24h
  dryrun: false
cache:
  enabled: false
  expire_hours: 24
