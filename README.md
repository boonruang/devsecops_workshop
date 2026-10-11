# DevSecOps Workshop

ชุด lab สำหรับหลักสูตร DevSecOps CI/CD ทุกเครื่องมืออยู่ใน compose project เดียวชื่อ `devsecops_workshop`
ปลายทาง deploy คือ `deploy-host` container ที่จำลองเครื่อง server (docker daemon แยกของตัวเอง) ไม่ต้องมี Kubernetes

pipeline หลักเป็น **Multibranch Pipeline** แบบเดียวกับ glo-portal ของจริง branch กับ tag กำหนดว่าไป env ไหน

| push อะไร | env | TAG ของ image | เปิดดู |
|---|---|---|---|
| branch `develop` | dev | `dev-build-<N>` | `http://LAB_HOST:8088` |
| branch `uat` | uat | `uat-build-<N>` | `http://LAB_HOST:8089` |
| git tag เช่น `v1.0.0` | prd | ชื่อ tag | `http://LAB_HOST:8090` |
| branch อื่น (`main`, `feature/*`) | ci | ไม่ build image | รันแค่ Vault + Gate 1-2 |

ชื่อ image และ container ตั้งตามแบบ pipeline จริง (`${REGISTRY}/${PROJECT}/glo-backend-net`, release `${APP_PREFIX}-backend`):

| env | image | container |
|---|---|---|
| dev | `LAB_HOST:5000/dev/glo-frontend:dev-build-<N>` | `glo-dev-frontend` |
| uat | `LAB_HOST:5000/uat/glo-frontend:uat-build-<N>` | `glo-uat-frontend` |
| prd | `LAB_HOST:5000/prd/glo-frontend:<tag>` | `glo-prd-frontend` |

ส่วนแรกของ path คือ env (ใน Harbor คือชื่อ project) ส่วนที่สองคือชื่อ app ดูทั้งหมดใน registry: `curl http://LAB_HOST:5000/v2/_catalog`

```
GitLab --webhook (push / tag)--> Jenkins multibranch "sample-app"
   Prepare            branch/tag -> ENV_NAME, TAG, container, port
   Environment Check  Vault, SonarQube, Trivy, registry, BuildKit, deploy-host ต้องพร้อม ไม่งั้นหยุด
   Vault              สาธิตการดึง secret (A1-A5, B)
   Gate 1             SonarQube Quality Gate   (project แยกตาม env)
   Gate 2             trivy fs                 (dependency)
   Build              BuildKit --push--> registry          ┐
   Gate 3             trivy image              (CRITICAL)  │ เฉพาะ develop / uat / tag
   Helm               package + push chart                 │
   Deploy             secret/<env>/app-env -> docker run บน deploy-host
   Verify             /version ต้องตรงกับ TAG               ┘
   post               แจ้งผล (ของจริงส่ง LINE) + Trivy Report
```

| บริการ | URL | เข้าระบบ |
|---|---|---|
| GitLab | `http://LAB_HOST:8929` | `GITLAB_ROOT_USER` / `GITLAB_ROOT_PASSWORD` ใน `.env` (ตั้งให้ตอนเปิดครั้งแรก) |
| Jenkins | `http://LAB_HOST:8080` | `JENKINS_ADMIN_ID` / `JENKINS_ADMIN_PASSWORD` ใน `.env` |
| SonarQube | `http://LAB_HOST:9000` | ครั้งแรก `admin` / `admin` ระบบบังคับเปลี่ยน แล้วจดรหัสใหม่ไว้ที่ `SONAR_ADMIN_PASSWORD` ใน `.env` |
| Vault | `http://LAB_HOST:8200` | Token = `VAULT_ROOT_TOKEN` ใน `.env` |
| Harbor (profile `harbor` เปิดแยก) | `http://LAB_HOST:8085` | `admin` / `HARBOR_ADMIN_PASSWORD` ใน `.env` |
| Trivy server | `http://LAB_HOST:4954` | ไม่มีหน้าเว็บ report ดูในหน้า build ของ Jenkins เมนู **Trivy Report** |
| Registry | `http://LAB_HOST:5000/v2/_catalog` | เปิดโล่ง ไม่มีรหัส (เฉพาะ lab) |
| BuildKit | ไม่เปิดพอร์ตออกนอก | Jenkins เรียกผ่าน `tcp://buildkitd:1234` |
| sample-app dev / uat / prd | `http://LAB_HOST:8088` / `:8089` / `:8090` | ไม่มีหน้า login หน้าแรกแสดง env, version และ sha256 ของ secret ที่ได้จาก Vault |
| deploy-host | ไม่เปิดพอร์ต 2375 ออกนอก | Jenkins สั่งผ่าน `DOCKER_HOST=tcp://deploy-host:2375` |

## ความต้องการของเครื่อง

| | ขั้นต่ำ | แนะนำ |
|---|---|---|
| OS | Ubuntu 24.04 (ทดสอบแล้ว) หรือ Linux ที่มี Docker Engine 24+ และ Compose v2 | |
| CPU | 4 vCPU | 4-8 vCPU |
| RAM | 12 GB (GitLab ~4 GB, SonarQube ~2.5 GB, Jenkins ~1.5 GB) | 16 GB |
| ดิสก์ | 40 GB ว่าง | 60 GB (image ~12 GB + data) |
| เครือข่าย VMware | **Bridged** ให้ VM ได้ IP ในวงเดียวกับเครื่องที่เปิดเบราว์เซอร์ | ถ้าใช้ NAT เครื่องอื่นจะเข้า VM ไม่ได้ |

## เปิดระบบ (Ubuntu 24.04)

### 1. ติดตั้ง Docker Engine และ Docker Compose

**แบบ A (แนะนำ ทดสอบแล้ว):** ติดตั้งจาก apt ของ Ubuntu เอง ใช้ mirror ของ Ubuntu ซึ่งเครือข่ายองค์กรส่วนใหญ่เปิดไว้อยู่แล้ว

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 git curl
sudo systemctl enable --now docker       # ให้ docker เปิดเองทุกครั้งที่ boot
sudo usermod -aG docker $USER            # ให้ user นี้สั่ง docker ได้โดยไม่ต้อง sudo
```

แล้ว **logout / login ใหม่ 1 ครั้ง** (หรือพิมพ์ `newgrp docker` ใน terminal เดิม) เพื่อให้สิทธิ์กลุ่ม docker มีผล ตรวจว่าใช้ได้:

```bash
docker version --format 'engine {{.Server.Version}}'   # ต้องได้ 24 ขึ้นไป (Ubuntu 24.04 ได้ 29.x)
docker compose version                                 # v2 ขึ้นไป (แบบ A ได้ 2.40, แบบ B ได้ v5.x ใช้ได้ทั้งคู่)
docker info >/dev/null && echo OK                      # ถ้าขึ้น permission denied แปลว่ายังไม่ได้ logout / login
```

**แบบ B:** ติดตั้งจาก repo ของ Docker (ได้รุ่นใหม่กว่า แต่ต้องออก `download.docker.com` ได้) ใช้แทนแบบ A ห้ามลงทั้งสองแบบ
ถ้าเคยลงแบบ A ไว้ ให้ถอนก่อน `sudo apt remove -y docker.io docker-compose-v2`

```bash
sudo apt update
sudo apt install -y ca-certificates curl git
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable"   | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER            # แล้ว logout / login ใหม่ 1 ครั้ง
```

คำสั่งที่ใช้ใน workshop คือ `docker compose` (เว้นวรรค เป็น plugin รุ่นปัจจุบัน) ไม่ใช่ `docker-compose` (มีขีด เป็น v1 รุ่นเก่าที่เลิกพัฒนาแล้ว)
ทดสอบติดตั้งทั้งสองแบบบน Ubuntu 24.04 แล้ว: แบบ A ได้ engine 29.1 + compose 2.40 (รัน workshop ทดสอบครบ), แบบ B ได้ engine 29.9 + compose 5.6 (workshop พัฒนาบน compose 5.5)

### 2. clone workshop จาก GitHub

```bash
cd ~
git clone https://github.com/boonruang/devsecops_workshop.git
cd devsecops_workshop
```

ถ้าเครือข่ายออก github.com ไม่ได้ ใช้ไฟล์ที่ผู้สอนแจกแทน (เนื้อหาเหมือนกัน):

```bash
tar xzf devsecops_workshop-2026-10-11.tar.gz
cd devsecops_workshop
```

ผู้สอนแก้ไฟล์ระหว่างอบรมแล้วอยากได้ของใหม่: `git pull` (ไม่ทับ `.env` และ `images/` เพราะอยู่ใน `.gitignore`)

### 3. วางไฟล์ image offline (ถ้าผู้สอนแจก)

```bash
mkdir -p images
cp /media/$USER/<ชื่อ USB>/images/* images/      # หรือคัดลอกจาก file share ที่ผู้สอนบอก
cd images && sha256sum -c --quiet SHA256SUMS && echo "ไฟล์ครบ" && cd ..
```

ไม่มีไฟล์ offline ก็ข้ามขั้นนี้ได้ ระบบจะ pull จาก internet แทน (ช้ากว่า และชนโควต้า Docker Hub ได้ถ้าทั้งห้องใช้ IP เดียวกัน)

### 4. เตรียมเครื่อง แล้วเปิดระบบ

```bash
bash setup.sh
docker compose --profile all up -d   # ไม่มีไฟล์ image offline ให้เติม --build (setup.sh บอกให้)
docker compose --profile all ps      # รอจน gitlab ขึ้น (healthy) ประมาณ 5 นาที
```

`bash setup.sh` ทำให้ทั้งหมดนี้ รันซ้ำได้ ไม่ทับ `.env` ที่มีอยู่แล้ว:
- ตรวจ docker, compose, สิทธิ์ของ user, RAM, CPU, ดิสก์
- ตั้ง `vm.max_map_count=524288` แบบถาวร (ไม่ตั้ง SonarQube จะหยุดเองภายในไม่กี่วินาที) ขั้นนี้ถาม sudo
- `docker load` ไฟล์ใน `images/` แล้วเช็คว่า image ครบไหม
- สร้าง `.env` จาก `.env.example` หา IP ของเครื่องใส่ `LAB_HOST` และสุ่มรหัสทุกช่องใหม่ ดูรหัสได้ใน `.env`
- ตรวจว่าออก internet ไปที่ที่ lab ต้องใช้ได้ไหม และ Docker Hub เหลือโควต้า pull เท่าไร

เครื่องมีหลายการ์ดแลน และ IP ที่หาได้ไม่ใช่ตัวที่เบราว์เซอร์เข้าถึง: ลบ `.env` แล้วรัน `LAB_HOST=<IP> bash setup.sh` **ก่อน** up ครั้งแรก
(GitLab ใช้ `LAB_HOST` สร้าง clone URL และ deploy-host ใช้ pull image)

Docker Desktop บน Windows ใช้ได้เหมือนกัน แต่ไม่มี setup.sh: `cp .env.example .env` แก้เอง แล้วตั้ง
`wsl -d docker-desktop sysctl -w vm.max_map_count=524288` (ต้องทำใหม่ทุกครั้งที่ restart Docker)

### ไฟล์ image offline (สำหรับผู้สอน)

Docker Hub ให้ pull แบบไม่ login ได้ **100 ครั้งต่อชั่วโมงต่อ IP ขาออก** (วัดจาก header `ratelimit-limit: 100;w=3600`)
ห้องอบรมที่ทุกเครื่องออกเน็ตผ่าน IP เดียวกัน ใช้เครื่องละ ~10 image แค่ 10 เครื่องก็ชนเพดานแล้ว และ Jenkins ต้อง build เอง (โหลด plugin จาก internet)

บนเครื่องที่ up ระบบได้แล้ว รัน `bash save-images.sh` ได้ `images/*.tar.gz` หนึ่งไฟล์ต่อ image (20 ไฟล์ รวม ~4.2 GB นับ Jenkins ที่ build แล้วและ Harbor ด้วย) พร้อม `SHA256SUMS`
แจกผ่าน USB หรือ file share ผู้เรียนวางในโฟลเดอร์ `images/` แล้วรัน `bash setup.sh`

### เครือข่ายของลูกค้า: ปลายทางที่ lab ต้องออกไปถึง

| ปลายทาง | ใช้ตอนไหน | ถ้าโดนบล็อก |
|---|---|---|
| `registry-1.docker.io`, `auth.docker.io` | pull image (ไม่ต้องถ้าใช้ไฟล์ offline) และ BuildKit ดึง `python:3.12-slim` ตอน build sample-app ครั้งแรก | stage Build ตก |
| `pypi.org`, `files.pythonhosted.org` | `pip install` ตอน build sample-app | stage Build ตก |
| `mirror.gcr.io` (สำรอง `ghcr.io`) | Trivy โหลดฐานข้อมูลช่องโหว่ | Gate 2, 3 ตก |
| `updates.jenkins.io` และ mirror | build image ของ Jenkins (ไม่ต้องถ้าใช้ไฟล์ offline) | `up --build` ตก |

ถ้าต้องออกผ่าน proxy มีสองที่ต้องตั้ง:
- docker daemon (ใช้ตอน pull): สร้าง `/etc/systemd/system/docker.service.d/http-proxy.conf`
  ```ini
  [Service]
  Environment="HTTP_PROXY=http://proxy:8080" "HTTPS_PROXY=http://proxy:8080" "NO_PROXY=localhost,127.0.0.1"
  ```
  แล้ว `sudo systemctl daemon-reload && sudo systemctl restart docker`
- container ที่ออก internet เอง (buildkitd, trivy-server): สร้าง `docker-compose.override.yml`
  ```yaml
  services:
    buildkitd:
      environment: { HTTPS_PROXY: "http://proxy:8080", NO_PROXY: "LAB_HOST_IP,registry,gitlab,jenkins,vault,sonarqube" }
    trivy-server:
      environment: { HTTPS_PROXY: "http://proxy:8080" }
  ```

ครั้งแรก GitLab ใช้เวลาประมาณ 3-5 นาทีกว่าจะเข้าเว็บได้ รอจนกว่า `docker compose --profile all ps` จะขึ้น `gitlab ... (healthy)`

เปิดเฉพาะบางส่วนได้ด้วย profile: `gitlab` · `jenkins` · `sonar` · `trivy` · `build` · `vault` · `deploy` · `harbor` (Harbor ไม่รวมใน `all`)
(profile `jenkins` จะเปิด sonar, trivy, buildkit, registry, vault, deploy-host ไปด้วย เพราะ pipeline ต้องใช้ครบ)

## ปลายทาง deploy: deploy-host

แทน Kubernetes ด้วย container `deploy-host` (`docker:29.8.2-dind`) ทำหน้าที่เป็นเครื่อง server ที่ app ไปรัน
- เป็น docker daemon **แยก** จากของเครื่อง host Jenkins มีแค่ docker CLI และสั่งงานผ่าน `DOCKER_HOST=tcp://deploy-host:2375`
  Jenkins จึงไม่ต้อง mount `/var/run/docker.sock` ของเครื่องจริง (ถ้า mount = Jenkins มีสิทธิ์เท่า root ของ host)
- deploy-host pull image จาก registry ของ lab แบบ http ได้เพราะตั้ง `--insecure-registry=LAB_HOST:5000` ไว้ใน compose แล้ว
- แต่ละ env เป็น container ของตัวเอง `glo-dev-frontend`, `glo-uat-frontend`, `glo-prd-frontend`
  พอร์ต 8088 / 8089 / 8090 เปลี่ยนได้ที่ `WEBAPP_PORT_DEV/UAT/PRD` ใน `.env`

ดูว่าบน deploy-host มีอะไรรันอยู่:
```bash
docker compose exec deploy-host docker ps
docker compose exec deploy-host docker logs glo-dev-frontend
```

## ขั้นตอน Lab

### 1. GitLab: สร้าง project แล้ว push แอปตัวอย่างขึ้น 3 branch
สร้าง project ชื่อ `sample-app` แล้ว push เนื้อหาในโฟลเดอร์ `sample-app/` ขึ้นไปเป็น `main`, `develop` และ `uat`
```bash
cd sample-app
git init -b main && git add -A && git commit -m "sample app"
git push http://root:<รหัสหรือ token>@LAB_HOST:8929/root/sample-app.git main main:develop main:uat
```

### 2. SonarQube: ออก token แล้วเก็บเข้า Vault
SonarQube > My Account > Security > Generate Token (ชนิด Global Analysis Token)
```bash
docker compose exec -e VAULT_TOKEN=<VAULT_ROOT_TOKEN> vault \
  vault kv put secret/workshop/sonar token=<sonar token>
```

### 3. GitLab: เก็บ token ที่ Jenkins ใช้ clone เข้า Vault
GitLab > User Settings > Access tokens > สร้าง token scope `read_repository`
```bash
docker compose exec -e VAULT_TOKEN=<VAULT_ROOT_TOKEN> vault \
  vault kv put secret/workshop/gitlab username=root password=<glpat-...>
```
credential `gitlab` ใน Jenkins ถูกประกาศไว้ใน JCasC แล้ว เป็นชนิด **Vault Username-Password Credential**
Jenkins ไม่ได้เก็บรหัส GitLab ไว้ที่ตัวเอง ทุกครั้งที่ clone มันไปอ่านจาก `secret/workshop/gitlab`

Jenkins ไม่เคยเห็นรหัสพวกนี้ใน job มันใช้ AppRole ที่อ่านได้อย่างเดียว และอ่านได้แค่ `secret/workshop/*`
stage `Vault: Jenkins ดึง secret` พิสูจน์เรื่องนี้ให้ดูใน log (ดูหัวข้อ "สาธิต Vault" ด้านล่าง)

### 4. Jenkins: สร้าง Multibranch Pipeline และต่อ webhook
1. ไม่ต้องเพิ่ม credential ของ GitLab ในหน้าเว็บ Jenkins ใช้ `gitlab` ที่ชี้ไป Vault จากขั้น 3
   (ถ้าเพิ่มผ่านหน้าเว็บ จะหายตอน Jenkins restart เพราะ JCasC เขียนทับ credential ของระบบทั้งชุด)
2. New Item > **Multibranch Pipeline** ชื่อ `sample-app`
   - Branch Sources > Add source > **Git** > `http://gitlab:8929/root/sample-app.git` > credential `gitlab`
   - Behaviours: Discover branches (มีอยู่แล้ว) > Add > **Discover tags**
   - Build strategies > Add > **Regular branches** และ Add > **Tags** (Ignore tags older than `3` วัน)
     ถ้าไม่เพิ่ม Tags Jenkins จะเห็น tag แต่ไม่ build เอง ต้องกดมือ
   - Build Configuration > Script Path `Jenkinsfile`
   - Scan Multibranch Pipeline Triggers > ติ๊ก **Scan by webhook** > Trigger token `sample-app`
   - Orphaned Item Strategy > Discard old items (ลบ job ของ branch ที่ถูกลบใน GitLab)
   - Save แล้ว Jenkins จะ scan เจอ `main`, `develop`, `uat` และเริ่ม build ทั้งสาม
3. GitLab (root) > Admin > Settings > Network > Outbound requests > เปิด
   **Allow requests to the local network from webhooks and integrations**
   ถ้าไม่เปิด GitLab จะไม่ยอมบันทึก webhook (`Invalid url given`) หรือบันทึกได้แต่ยิงไม่ออก (`URL is blocked`)
   เปิดแล้วรอประมาณ 2 นาที GitLab ถึงจะใช้ค่าใหม่
4. GitLab > project > Settings > Webhooks
   - URL `http://jenkins:8080/multibranch-webhook-trigger/invoke?token=sample-app`
   - ติ๊ก **Push events** และ **Tag push events** · ปิด SSL verification · ไม่ต้องใส่ Secret token
   - กด Test > Push events ต้องได้ HTTP 200 (Jenkins จะ scan branch ใหม่ทันที และ build เฉพาะ branch ที่มี commit ใหม่)
5. ปล่อย release ขึ้น prd ด้วย tag
   ```bash
   git tag -a v1.0.0 -m "release v1.0.0" && git push origin v1.0.0
   ```
   Jenkins จะสร้าง job `v1.0.0` ใต้ `sample-app` เอง แล้ว deploy ไปที่ `http://LAB_HOST:8090`

### 5. รันแล้วดู security gate ทำงาน
รอบแรก **ต้องตก** ที่ Gate 2 เพราะ `requirements.txt` ตั้งใจ pin รุ่นเก่าไว้ trivy เจอ HIGH 3 ตัว
(flask CVE-2023-30861, werkzeug CVE-2023-25577 และ CVE-2024-34069)

แบบฝึกหัด: อัปเดต `requirements.txt` เป็นรุ่นที่แก้แล้ว push ใหม่ webhook จะเริ่ม build เอง
pipeline ของ `develop` ต้องผ่านทุก stage แล้วเปิด `http://LAB_HOST:8088` ได้ หน้าแรกขึ้น `dev` และ version `dev-build-<N>`
จากนั้น merge เข้า `uat` (ขึ้น :8089) แล้วติด tag (ขึ้น :8090) ให้เห็นของชิ้นเดียวเดินผ่านครบสาม env

```
flask==3.1.3
werkzeug==3.1.9
requests==2.34.2
```

แบบฝึกหัดต่อ (SonarQube): เปิด project `workshop-sample-app-dev` จะเห็น issue ด้าน security 3 จุด
ได้แก่ CSRF ไม่ได้เปิด (S4502), ใช้ `/tmp` (S5443) และ bind `0.0.0.0` (S8392)
แต่ **ไม่เห็น SQL injection** ใน endpoint `/tickets` ทั้งที่มีอยู่จริง เพราะ taint analysis มีเฉพาะ Developer Edition ขึ้นไป
ใช้เป็นตัวอย่างว่า SAST ฉบับ Community ไม่ได้เห็นทุกอย่าง ยังต้องมี code review และ DAST
ให้ผู้เรียนแก้เป็น parameterized query เอง

Quality Gate ผ่านตั้งแต่รอบแรก เพราะ Sonar way ตรวจเฉพาะ new code และการวิเคราะห์ครั้งแรกยังไม่มี new code ให้เทียบ
Sonar แยก project ตาม env (`workshop-sample-app-dev`, `-uat`, `-prd`, `-ci`) เพราะ Community Edition ไม่มี branch analysis
แบบเดียวกับที่ glo-portal ตั้ง `glo-portal-backend-dev/uat/prd`

## เทียบกับ pipeline จริงของ glo-portal

`Jenkinsfile` ยกโครงมาจาก pipeline จริง (Prepare, Environment Check, Vault: Pull Secrets, Verify App Version, แจ้งผล LINE
และ `FAILED_STAGE` / `FAILED_MSG`) แต่แก้จุดที่เจอตอนรีวิวไว้ ใช้เป็นโจทย์ให้ผู้เรียนหาว่าของเดิมเสี่ยงตรงไหน

| เรื่อง | ของจริง | ใน workshop |
|---|---|---|
| Sonar / Quality Gate | ปิดด้วย `when { expression { false } }` | เปิดทุก env และ branch อื่นต้องผ่าน gate ก่อน merge |
| branch อื่นนอกจาก develop/uat | `NOT_BUILT` ข้ามไปเลย | env `ci` รัน Vault + Gate 1-2 |
| trivy image | สแกนหลัง push | ตกที่ CRITICAL ก่อน deploy |
| อ่าน secret จาก Vault | grep/sed (พังถ้าค่ามี `,` หรือ `:`) และ token ผ่าน Groovy string | `ci/vault-env.sh` ใช้ jq, token อยู่ใน shell และ revoke ทุกครั้ง |
| Environment Check | พิมพ์ `[FAIL]` แล้วไปต่อ | ตกทันทีถ้า server ไม่พร้อม |
| สั่ง BuildKit | `docker exec buildkitd` (Jenkins ต้องเข้า docker.sock) | `buildctl` ผ่าน TCP ไม่แตะ docker.sock |
| kubeconfig | `kubeconfig-dev` ใช้กับทุก env | แต่ละ env เป็น container แยก ชี้ secret แยก path |
| try/catch | ซ้ำทุก stage | function `tracked { }` เขียนครั้งเดียว |

สิ่งที่ยังเหมือนของจริงโดยตั้งใจ ให้ผู้เรียนเสนอทางแก้เอง:
- AppRole ตัวเดียวอ่าน secret ได้ทุก env (`secret/dev/*`, `uat/*`, `prd/*`) ควรแยก role ต่อ env
- tag ไหนก็ขึ้น prd ได้ทันที ไม่มีขั้นอนุมัติ ลองเพิ่ม `input` ก่อน Deploy เมื่อ `ENV_NAME == 'prd'`

## ดู Trivy report

trivy-server ไม่มีหน้าเว็บ pipeline จึงเก็บ report ไว้กับ build ใน Jenkins ทุกครั้ง แม้ gate จะตก
`ci/trivy-gate.sh` สแกนครั้งเดียว แล้วแตกผลออกเป็นสามแบบ

| ดูที่ไหน | ได้อะไร |
|---|---|
| หน้า build > เมนู **Trivy Report** (แท็บ `trivy fs` / `trivy image`) | report HTML ทุกระดับความรุนแรง แยกตาม package พร้อม CVE, รุ่นที่แก้แล้ว และลิงก์อ่านต่อ |
| หน้า build > **Build Artifacts** > `reports/*.json` | ผลดิบ JSON เอาไปเข้า tool อื่นต่อได้ (DefectDojo, Excel) |
| Console Output | บรรทัดสรุป `ผลทุกระดับ: HIGH=44 LOW=62 ...` และตารางเฉพาะระดับที่ gate ใช้ตัดสิน |

ตัวอย่างจาก build จริง: Gate 3 (`trivy image`) **ผ่าน** ทั้งที่ report มี HIGH 44 ตัว เพราะ gate นี้ตั้งให้ตกเฉพาะ CRITICAL
HIGH ส่วนใหญ่มาจาก base image `python:3.12-slim` ที่ทีมแก้เองไม่ได้ ใช้ report นี้คุยกับผู้เรียนเรื่องการเลือกเกณฑ์ gate

report จะเปิดได้เพราะ compose ตั้ง `-Dhudson.model.DirectoryBrowserSupport.CSP=` ให้ Jenkins แล้ว
(report มี inline style/script ค่านี้ใช้เฉพาะ lab งานจริงให้ตั้ง Resource Root URL ของ Jenkins แทน)

สแกนเองนอก pipeline แล้วได้ report HTML (คำสั่ง trivy อยู่ใน Jenkins เท่านั้น ไม่มี container trivy แยก):
```bash
docker compose exec jenkins trivy image --server http://trivy-server:4954 --insecure \
  --format template --template @/opt/trivy/html.tpl -o /tmp/trivy-report.html LAB_HOST:5000/prd/glo-frontend:v1.1.0
docker compose cp jenkins:/tmp/trivy-report.html ./trivy-report.html
```

## Jenkins แบบ Scripted Pipeline

pipeline หลักคือ Multibranch (`Jenkinsfile`) ส่วน `Jenkinsfile.scripted` มีไว้ฝึกเขียน Groovy
ล็อกไว้ที่ branch `develop` และ deploy ทับ env dev (TAG `scripted-build-<N>`) แล้วสั่ง build develop ใน multibranch อีกรอบ dev ก็จะกลับมา

| ไฟล์ | แบบ | เหมาะกับ |
|---|---|---|
| `Jenkinsfile` | Declarative (`pipeline { stages { } }`) ใช้ใน Multibranch | อ่านง่าย มีโครงตายตัว ใช้เป็นหลักใน lab |
| `Jenkinsfile.scripted` | Scripted (`node { }` เป็น Groovy ทั้งไฟล์) | เขียน logic เองได้: ตัวแปร, `if`, function, `try/catch/finally`, `parallel`, `retry` |

สิ่งที่ `Jenkinsfile.scripted` โชว์เพิ่ม:
- Gate 1 (Sonar) กับ Gate 2 (trivy fs) รัน **พร้อมกัน** ด้วย `parallel` และ `failFast: false` ให้เห็นผลครบทั้งสอง gate
- function `gate()` ของเราเอง จดผลแต่ละ gate แล้วพิมพ์สรุป PASS/FAIL ท้าย build ใน `finally`
- parameter `TRIVY_FS_SEVERITY` เลือกเกณฑ์ Gate 2 ตอนกด Build with Parameters
- `retry(12)` + `sleep` ของ Jenkins แทน loop ใน shell ตอนเช็คว่า app ขึ้น
- `currentBuild.description` แสดง commit กับ tag ในหน้ารายการ build

สร้าง job ที่แก้ script ในหน้า Jenkins ได้:
1. New Item > Pipeline ชื่อ `sample-app-scripted`
2. Pipeline > Definition: **Pipeline script** แล้ววางเนื้อหาทั้งไฟล์ `Jenkinsfile.scripted` ลงไป (ติ๊ก Use Groovy Sandbox ไว้)
3. Save > **Build Now** ครั้งแรก (ครั้งแรกยังไม่มีเมนู parameter เพราะ `properties()` เพิ่งถูกตั้ง ครั้งต่อไปจะเป็น Build with Parameters)

script ที่วางในหน้า Jenkins ไม่ได้มาจาก Git จึงต่อ webhook ไม่ได้และไม่มีประวัติการแก้ ใช้สำหรับทดลองเขียน
ถ้าต้องการให้ webhook สั่งได้ ให้ใช้ Definition: Pipeline script from SCM แล้วตั้ง Script Path เป็น `Jenkinsfile.scripted`
ทั้งสองแบบเรียก `ci/vault-demo.sh` และ `ci/trivy-gate.sh` ตัวเดียวกัน แก้ที่เดียวได้ผลทั้งคู่

## สาธิต Vault: Jenkins เอา secret มาได้อย่างไร

ทุก build มี stage `Vault: Jenkins ดึง secret` ก่อน security gate แสดงใน Console Output ทีละขั้น

| ขั้น | request ที่ Jenkins ยิงไป Vault | สิ่งที่เห็นใน log |
|---|---|---|
| A1 | `POST /v1/auth/approle/login` | login ด้วย role_id + secret_id (Jenkins ปิดเป็น `****`) ได้ token อายุ 20 นาที policy `jenkins` |
| A2 | `GET /v1/secret/data/workshop/{demo,sonar}` และ `<env>/app-env` | version, เวลาสร้าง, ชื่อ key, ความยาว และ sha256 ของแต่ละค่า ไม่พิมพ์ค่าจริง |
| A3 | `GET /v1/secret/data/workshop/restricted/dba-db` | **HTTP 403** secret ของทีม DBA policy ตั้ง `deny` ทับ `workshop/*` ไว้ |
| A4 | `POST /v1/secret/data/workshop/sonar` | **HTTP 403** policy ให้แค่ read แก้ไม่ได้ |
| A5 | `POST /v1/auth/token/revoke-self` | ยกเลิก token ทันที ใช้ token เดิมซ้ำได้ 403 |
| B | plugin `withVault` | `echo $DB_PASSWORD` ใน log ออกมาเป็น `****` แต่โปรแกรมใน stage ได้ค่าจริงไปใช้ |

ฝั่ง Vault เห็นทุก request เดียวกันใน audit log เปิดหน้าต่างนี้ค้างไว้ข้างๆ Jenkins ระหว่าง build:
```bash
docker compose exec vault sh /workshop/audit-view.sh -f     # ดูสด
docker compose exec vault sh /workshop/audit-view.sh        # 40 รายการล่าสุด
```
```
TIME      WHO              OP      PATH                               RESULT POLICIES
07:36:06  approle          update  auth/approle/login                 OK [default,jenkins]
07:36:06  approle          read    secret/data/workshop/sonar         OK [default,jenkins]
07:36:06  approle          read    secret/data/workshop/restricted/dba-db DENIED (permission denied) [default,jenkins]
07:36:06  approle          update  secret/data/workshop/sonar         DENIED (permission denied) [default,jenkins]
07:36:06  approle          update  auth/token/revoke-self             OK [default,jenkins]
```

เทียบ sha256 ใน log Jenkins กับค่าใน Vault (ยืนยันว่าเป็นค่าเดียวกันโดยไม่ต้องเปิดเผยค่า):
```bash
docker compose exec -e VAULT_TOKEN=<VAULT_ROOT_TOKEN> vault \
  sh -c 'vault kv get -field=db_password secret/workshop/demo | sha256sum | cut -c1-12'
```

secret ตั้งต้นที่ Vault สร้างให้เองตอนเปิดครั้งแรก:
`secret/workshop/demo` (ค่าสุ่ม ไว้สาธิต), `secret/workshop/restricted/dba-db` (policy ตั้ง deny ไว้สาธิตว่าโดนปฏิเสธ)
และ `secret/dev/app-env`, `secret/uat/app-env`, `secret/prd/app-env` (env ของ app แต่ละ env:
`APP_SECRET_KEY` ค่าสุ่ม, `APP_DB_HOST`, `APP_LOG_LEVEL`) เหมือน `secret/<env>/backend-env` ของ glo-portal
ส่วน `gitlab`, `sonar` เป็น `CHANGE-ME` จนกว่าผู้เรียนจะใส่ค่าจริงในขั้น 2 และ 3

### secret เดินทางจาก Vault ไปถึง app ที่รันอยู่
stage `Deploy` เรียก `ci/vault-env.sh` อ่าน **ทุก key** ใน `secret/<env>/app-env` เขียนเป็น env-file ชั่วคราว (สิทธิ์ 600)
ส่งเข้า `docker run --env-file` แล้วลบไฟล์ทิ้งทันที log แสดงแค่ชื่อ key ไม่แสดงค่า
เพิ่ม key ใหม่ใน Vault แล้ว build ใหม่ app จะได้ตัวแปรนั้นเอง ไม่ต้องแก้ Jenkinsfile

เปิดหน้าแรกของแต่ละ env จะเห็น sha256 ของ `APP_SECRET_KEY` และค่า `APP_DB_HOST` ที่ container ได้รับ
เทียบได้สามจุด: log ของ Jenkins (stage A2), หน้าเว็บ และคำสั่งนี้
```bash
docker compose exec -e VAULT_TOKEN=<VAULT_ROOT_TOKEN> vault \
  sh -c 'vault kv get -field=APP_SECRET_KEY secret/dev/app-env | sha256sum | cut -c1-12'
```
ข้อจำกัดที่ควรบอกผู้เรียน: คนที่เข้าถึง deploy-host ได้ยังเห็นค่าผ่าน `docker inspect glo-dev-frontend`
งานจริงจึงให้ app ไปอ่าน Vault เอง (Vault Agent) หรือใช้ secret ของ orchestrator แทน env

## สาธิต Harbor (เปิดแยกด้วย profile harbor)

Harbor v2.14.2 (9 container ตามแบบติดตั้งมาตรฐาน) แยกจาก registry ที่ pipeline ใช้ เปิดเฉพาะตอนสาธิต:

```bash
bash harbor/prepare.sh                     # setup.sh เรียกให้แล้ว ต้องรันใหม่เมื่อเปลี่ยน LAB_HOST
docker compose --profile harbor up -d      # ประมาณ 1 นาที (RAM เพิ่ม ~1 GB)
```

เปิด `http://LAB_HOST:8085` login `admin` / `HARBOR_ADMIN_PASSWORD` ใน `.env` แล้วทำตามนี้

| ขั้น | ทำอะไร | เห็นอะไร |
|---|---|---|
| 1 | Projects > New Project ชื่อ `prd` (ชื่อ project = env เหมือนชื่อ image) > เข้า project > Configuration ติ๊ก **Automatically scan images on push** | |
| 2 | push image จาก deploy-host (คำสั่งด้านล่าง) | Repositories มี `prd/glo-frontend` คอลัมน์ Vulnerabilities ขึ้นผลสแกนเองภายในไม่กี่นาที (ทดสอบได้ High 44) |
| 3 | Configuration ติ๊ก **Prevent vulnerable images from running** เลือก High แล้ว pull ซ้ำ | pull ไม่ได้ `412 Precondition Failed` image ที่มีช่องโหว่ถูกกันไว้ที่ registry |
| 4 | Robot Accounts > New Robot Account สิทธิ์ push/pull เฉพาะ project นี้ | รหัสของ robot เอาไปเก็บใน Vault แทนรหัส admin (โจทย์ต่อยอด) |

```bash
docker compose exec deploy-host sh
# ข้างใน deploy-host (ตั้ง --insecure-registry ของ Harbor ไว้แล้ว)
docker login LAB_HOST:8085 -u admin
docker tag LAB_HOST:5000/prd/glo-frontend:v1.1.0 LAB_HOST:8085/prd/glo-frontend:v1.1.0
docker push LAB_HOST:8085/prd/glo-frontend:v1.1.0
docker image rm LAB_HOST:8085/prd/glo-frontend:v1.1.0 && docker pull LAB_HOST:8085/prd/glo-frontend:v1.1.0   # ขั้น 3
```

ประเด็นคุยในห้อง: ติดตั้ง Harbor ด้วย `install.sh` โดยไม่ใส่ `--with-trivy` จะไม่มี container `trivy-adapter`
image ที่ push เข้าไปจะไม่ถูกสแกนเลยถ้าไม่ได้ต่อ scanner อื่น ให้ผู้เรียนเช็ค Harbor ขององค์กรตัวเองที่ Administration > Interrogation Services

ต่างจาก Harbor ที่ติดตั้งด้วย `install.sh`:
- **ใช้ http พอร์ต 8085** ไม่มี cert
- **เก็บข้อมูลใน named volume แทน `/data`** มี `harbor-volume-init` คอย chown ให้ uid 10000
- **ไม่มี `harbor-log`** ดู log ด้วย `docker compose logs harbor-core`

## ใช้เครื่องมือด้วยมือ (นอก Jenkins)

```bash
# Trivy: คำสั่งอยู่ใน Jenkins เท่านั้น (ไม่มี container trivy แยก) สแกน image ใน registry ด้วยมือผ่าน container jenkins
docker compose exec jenkins trivy image --server http://trivy-server:4954 --insecure --severity HIGH,CRITICAL LAB_HOST:5000/prd/glo-frontend:v1.1.0

# BuildKit: build แล้ว push (รันซ้ำรอบสองจะเห็น cache ทำให้เร็วขึ้น)
docker compose run --rm buildctl build --frontend dockerfile.v0 --local context=/src --local dockerfile=/src \
  --output type=image,name=registry:5000/dev/glo-frontend:manual,push=true,registry.insecure=true

# Helm ไม่มี container: chart คือไฟล์ source ใน sample-app/chart ที่อยู่ใน repo GitLab เดียวกับโค้ด
# pipeline ตรวจด้วย helm lint (คำสั่ง helm อยู่ใน image ของ Jenkins) ถ้ามี helm ในเครื่องก็ลองเองได้
helm lint sample-app/chart
helm template demo sample-app/chart --set image.tag=1.0.0

# SonarQube: สแกนจากเครื่องโดยไม่ผ่าน Jenkins
SONAR_TOKEN=<token> docker compose run --rm sonar-scanner

# Vault
docker compose exec -e VAULT_TOKEN=<VAULT_ROOT_TOKEN> vault vault kv get secret/dev/app-env
```

## ปัญหาที่เจอตอนทดสอบ

| อาการ | สาเหตุ / ทางแก้ |
|---|---|
| build รอบแรกขึ้น `ERROR: failed to configure registry cache importer ... buildcache: not found` | ปกติ ยังไม่มี cache รอบแรก build ยังผ่าน รอบต่อไปจะหายเอง |
| ลิงก์ผลสแกนใน log Jenkins เป็น `http://sonarqube:9000/...` กดไม่ได้ | เป็นชื่อในเครือข่าย docker เปลี่ยนเป็น `http://LAB_HOST:9000/...` เอง |
| container `sonarqube` หยุดเองหลังเปิด | ยังไม่ได้ตั้ง `vm.max_map_count` (Docker Desktop ต้องตั้งใหม่ทุกครั้งที่ restart Docker) |
| webhook ขึ้น `Invalid url given` หรือ `URL is blocked` | ยังไม่ได้เปิด outbound local requests ในขั้นที่ 4 หรือเพิ่งเปิดแต่ยังไม่ครบ 2 นาที |
| Deploy ตกที่ `docker pull` ขึ้น `dial tcp LAB_HOST:5000: connect: no route to host` | วง IP ของ docker0 ข้างใน deploy-host ทับวงของ LAB_HOST (ตั้งไว้ `172.31.255.1/24`) เปลี่ยน `DEPLOY_HOST_BIP` ใน `.env` เป็นวงอื่น แล้ว `docker compose --profile all up -d deploy-host` |
| container เรียก `LAB_HOST` ไม่ถึงเลย (BuildKit push ไม่ได้) ทั้งที่เบราว์เซอร์เปิดได้ | network ที่ docker สร้าง (172.17-31.x / 192.168.x) ทับวง LAN ของลูกค้า ดูวงด้วย `docker network inspect devsecops_workshop` แล้วตั้ง `default-address-pools` ใน `/etc/docker/daemon.json` ให้พ้นวงของลูกค้า |
| `setup.sh` เตือนว่าเครื่องมีหลาย IP | VM มีหลายการ์ดแลน (เช่น NAT + Bridged) เลือก IP ที่เครื่องอื่นเข้าถึง: ลบ `.env` แล้ว `LAB_HOST=<IP> bash setup.sh` |
| `./setup.sh: Permission denied` | ไฟล์เสีย bit execute ระหว่างคัดลอก ใช้ `bash setup.sh` แทน |
| Gate 1 ตก `QUALITY GATE STATUS: FAILED` เงื่อนไข `new_coverage` (Coverage on New Code < 80%) | Quality Gate ค่าเริ่มต้น (Sonar way) บังคับ coverage ของโค้ดใหม่ แต่ lab ไม่ได้ส่งผล coverage ไปให้ Sonar ค่าจึงเป็น 0 Sonar ข้ามเงื่อนไขนี้ถ้าโค้ดใหม่ไม่ถึง 20 บรรทัด ถ้าแก้ทีละมากจะตก pipeline ส่ง `sonar.projectVersion=TAG` ให้นับโค้ดใหม่เทียบกับ build ก่อนแล้ว ใช้เป็นโจทย์ได้: เขียน test + ส่ง coverage (`pytest --cov --cov-report xml` แล้วตั้ง `sonar.python.coverage.reportPaths`) หรือใน lab สร้าง Quality Gate ของตัวเองใน SonarQube |
| `docker compose ps` ไม่เห็นอะไรเลย | ต้องใส่ `--profile all` ด้วย เพราะทุก service ผูกกับ profile |
| credential ที่เพิ่มในหน้าเว็บ Jenkins หายหลัง restart | JCasC เขียนทับ credential ของระบบทั้งชุดทุกครั้งที่ Jenkins เปิด ให้ประกาศใน `jenkins/casc/jenkins.yaml` และเก็บค่าจริงใน Vault |
| เมนู Trivy Report เปิดแล้วหน้าเปล่าหรือไม่มีสี | Jenkins ยังใช้ CSP ค่าเดิม เช็คว่า `JAVA_OPTS` ใน compose มี `DirectoryBrowserSupport.CSP=` แล้ว `up -d jenkins` |
| job Scripted ขึ้น `Scripts not permitted to use method ...` | ใช้ method ที่ Groovy Sandbox ไม่อนุญาต ไปกด Approve ที่ Manage Jenkins > In-process Script Approval หรือเปลี่ยนไปใช้ step ของ Jenkins แทน |
| ใน Docker Desktop เห็น Vault แค่ container เดียว | ถูกแล้ว init (policy, AppRole, audit, secret ตั้งต้น) รันอยู่ใน container `vault` เอง healthy แปลว่า init เสร็จแล้ว |
| Verify App ตก `app ไม่ขึ้น หรือยังเป็นเวอร์ชันเก่า` | ดู log ที่ stage พิมพ์ให้ หรือ `docker compose exec deploy-host docker logs glo-<env>-frontend` |
| push tag แล้ว Jenkins ไม่ build | ยังไม่ได้เพิ่ม Build strategy **Tags** หรือ tag เก่ากว่า 3 วัน หรือ webhook ไม่ได้ติ๊ก Tag push events |
| branch `main` ขึ้น SUCCESS แต่ไม่มี container | ถูกแล้ว branch อื่นนอกจาก develop/uat เป็น env `ci` รันแค่ gate |
| deploy-host pull image ไม่ได้ `http: server gave HTTP response to HTTPS client` | `LAB_HOST` ใน `.env` ไม่ตรงกับชื่อ registry ใน image ทำให้ `--insecure-registry` ไม่ครอบ แก้ `.env` แล้ว `up -d deploy-host` |
| Vault ข้อมูลหายไหมถ้า restart | ไม่หาย เก็บใน volume `vault-data` และ unseal เองตอนเปิด (key อยู่ใน volume เดียวกัน ใช้ได้เฉพาะ workshop) |

## ปิดระบบ

```bash
docker compose --profile all down        # หยุด เก็บข้อมูลไว้
docker compose --profile all down -v     # หยุดและล้างข้อมูลทั้งหมด เริ่มใหม่จากศูนย์
```

## เวอร์ชันที่ใช้ (ตรวจกับ registry เมื่อ 11 ต.ค. 2569)

| เครื่องมือ | image |
|---|---|
| GitLab CE | `gitlab/gitlab-ce:19.4.1-ce.0` |
| Jenkins LTS | `jenkins/jenkins:2.580.1-lts-jdk21` + JCasC + hashicorp-vault-plugin |
| SonarQube Community | `sonarqube:26.9.0.129388-community` + `postgres:17.11-alpine` |
| Trivy | `aquasec/trivy:0.75.0` |
| BuildKit | `moby/buildkit:v0.33.1` |
| Helm (คำสั่งใน image ของ Jenkins ไม่มี container) | `3.22.0` (คัดลอกจาก `alpine/helm:3.22.0` ตอน build) |
| Vault | `hashicorp/vault:2.1.1` |
| Harbor | `goharbor/*:v2.14.2` |
| Registry | `registry:3.1.2` |
| deploy-host | `docker:29.8.2-dind` (docker CLI ใน Jenkins: `docker:29.8.2-cli`) |
