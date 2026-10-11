"""แอปตัวอย่างสำหรับ workshop: ตั้งใจใส่จุดอ่อนไว้ให้ SonarQube กับ Trivy เจอ ห้ามนำไปใช้จริง"""
import hashlib
import os
import socket
import sqlite3
from html import escape
from string import Template

from flask import Flask, jsonify, request

app = Flask(__name__)
DB_PATH = os.environ.get("DB_PATH", "/tmp/lab.db")


def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS tickets (id INTEGER PRIMARY KEY, owner TEXT, number TEXT)")
        conn.execute("INSERT OR IGNORE INTO tickets VALUES (1, 'somchai', '123456')")


# สีและชื่อเต็มของแต่ละ env (ตรงกับ multibranch: develop=dev, uat=uat, git tag=prd)
ENVS = {
    "dev": {"name": "Development", "color": "#16a34a", "dark": "#14532d", "port": "8088", "from": "branch develop"},
    "uat": {"name": "UAT", "color": "#ea580c", "dark": "#7c2d12", "port": "8089", "from": "branch uat"},
    "prd": {"name": "Production", "color": "#dc2626", "dark": "#7f1d1d", "port": "8090", "from": "git tag"},
}
OTHER = {"name": "Local", "color": "#64748b", "dark": "#1e293b", "port": "", "from": "รันเอง"}

# ใช้ string.Template ($ชื่อ) แทน str.format เพราะ CSS มีปีกกาเต็มไปหมด
PAGE = Template("""<!doctype html>
<html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$env_upper · $version · glo-frontend</title>
<style>
:root{--c:$color;--d:$dark;--bg:#f1f5f9;--card:#fff;--ink:#0f172a;--mute:#64748b;--line:#e2e8f0}
@media (prefers-color-scheme:dark){:root{--bg:#0b1120;--card:#111827;--ink:#e5e7eb;--mute:#94a3b8;--line:#1f2937}}
*{box-sizing:border-box}
body{margin:0;font-family:"Segoe UI","Noto Sans Thai",Tahoma,sans-serif;background:var(--bg);color:var(--ink)}
.hero{background:linear-gradient(135deg,var(--c),var(--d));color:#fff;padding:36px 20px 72px}
.wrap{max-width:880px;margin:0 auto}
.top{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px}
.brand{font-weight:600;opacity:.9;letter-spacing:.3px}
.envs{display:flex;gap:6px;flex-wrap:wrap}
.envs a{color:#fff;text-decoration:none;font-size:13px;padding:5px 12px;border-radius:999px;border:1px solid rgba(255,255,255,.45)}
.envs a.on{background:#fff;color:var(--d);font-weight:700;border-color:#fff}
.label{margin-top:28px;font-size:14px;opacity:.9}
.caps{letter-spacing:3px;font-size:12px;font-weight:600}
h1{margin:4px 0 0;font-size:44px;line-height:1.1}
.ver{display:inline-block;margin-top:16px;font:600 22px/1 ui-monospace,Consolas,monospace;background:rgba(0,0,0,.25);
  padding:10px 16px;border-radius:10px;border:1px solid rgba(255,255,255,.35)}
.ver small{font:500 12px "Segoe UI",sans-serif;opacity:.8;margin-right:8px;letter-spacing:1px}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin-top:-44px}
@media (max-width:640px){.grid{grid-template-columns:minmax(0,1fr)}h1{font-size:34px}.row{flex-direction:column;gap:2px}.row code{text-align:left}}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px;box-shadow:0 6px 18px rgba(15,23,42,.08)}
.card h2{margin:0 0 12px;font-size:15px;color:var(--c)}
.row{display:flex;justify-content:space-between;gap:12px;padding:7px 0;border-bottom:1px dashed var(--line);font-size:14px}
.row:last-child{border-bottom:0}
.row span{color:var(--mute);flex:none}
code{font-family:ui-monospace,Consolas,monospace;font-size:13px;overflow-wrap:anywhere;text-align:right;min-width:0}
.ok{color:#16a34a;font-weight:600}.no{color:#dc2626;font-weight:600}
.full{grid-column:1/-1}
form{display:flex;gap:8px;flex-wrap:wrap}
input{flex:1;min-width:180px;padding:10px 12px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--ink);font-size:14px}
button{padding:10px 18px;border:0;border-radius:8px;background:var(--c);color:#fff;font-weight:600;cursor:pointer}
.note{font-size:12px;color:var(--mute);margin-top:10px}
footer{text-align:center;font-size:12px;color:var(--mute);padding:28px 16px}
</style></head><body>
<div class="hero"><div class="wrap">
  <div class="top"><div class="brand">DevSecOps Workshop · glo-frontend</div><nav class="envs">$env_links</nav></div>
  <div class="label"><span class="caps">ENVIRONMENT</span> · deploy จาก $env_from</div>
  <h1>$env_name</h1>
  <div class="ver"><small>VERSION</small>$version</div>
</div></div>
<div class="wrap" style="padding:0 16px">
<div class="grid">
  <div class="card"><h2>Release</h2>
    <div class="row"><span>version</span><code>$version</code></div>
    <div class="row"><span>image</span><code>$image</code></div>
    <div class="row"><span>commit</span><code>$commit</code></div>
    <div class="row"><span>Jenkins build</span><code>$build</code></div>
    <div class="row"><span>deploy เมื่อ</span><code>$deployed_at</code></div>
  </div>
  <div class="card"><h2>Runtime</h2>
    <div class="row"><span>environment</span><code>$env</code></div>
    <div class="row"><span>container</span><code>$host</code></div>
    <div class="row"><span>log level</span><code>$log_level</code></div>
    <div class="row"><span>health</span><code class="ok">/healthz ok</code></div>
  </div>
  <div class="card full"><h2>Secret จาก Vault (secret/$env/app-env)</h2>
    <div class="row"><span>APP_SECRET_KEY</span>$secret</div>
    <div class="row"><span>APP_DB_HOST</span><code>$db_host</code></div>
    <div class="note">หน้านี้แสดงแค่ความยาวและ sha256 ของ secret ไว้เทียบกับค่าใน Vault ไม่แสดงค่าจริง</div>
  </div>
  <div class="card full"><h2>ค้นหา ticket</h2>
    <form action="/tickets"><input name="owner" placeholder="owner เช่น somchai"><button>ค้นหา</button></form>
  </div>
</div></div>
<footer>แอปตัวอย่างที่ตั้งใจใส่ช่องโหว่ไว้ให้ security gate จับ ห้ามนำไปใช้จริง</footer>
</body></html>""")


def env_links(current):
    # ลิงก์ไป env อื่นบนเครื่องเดียวกัน (พอร์ตเปลี่ยนได้ด้วย APP_PORT_DEV / APP_PORT_UAT / APP_PORT_PRD)
    host = escape(request.host.split(":")[0])
    links = []
    for key, info in ENVS.items():
        port = os.environ.get("APP_PORT_" + key.upper(), info["port"])
        cls = ' class="on"' if key == current else ""
        links.append(f'<a{cls} href="http://{host}:{escape(port)}/">{key}</a>')
    return "".join(links)


@app.get("/")
def index():
    # ค่าจาก secret/<env>/app-env ไปถึง container ทางเดียว: Jenkins อ่านจาก Vault ตอน deploy แล้วส่งเข้า --env-file
    # หน้าเว็บแสดงแค่ความยาวกับ sha256 ไว้เทียบกับ Vault ไม่แสดงค่าจริง
    secret = os.environ.get("APP_SECRET_KEY", "")
    if secret:
        fp = hashlib.sha256(secret.encode()).hexdigest()[:12]
        secret_html = f'<code><span class="ok">ได้รับแล้ว</span> · ยาว {len(secret)} · sha256 {fp}</code>'
    else:
        secret_html = '<code class="no">ยังไม่ได้รับ</code>'
    env = os.environ.get("APP_ENV", "local")
    info = ENVS.get(env, OTHER)
    val = lambda k, d="-": escape(os.environ.get(k, d))  # noqa: E731
    return PAGE.substitute(
        env=escape(env), env_upper=escape(env.upper()), env_name=info["name"], env_from=info["from"],
        color=info["color"], dark=info["dark"], env_links=env_links(env),
        version=val("APP_VERSION", "dev"), image=val("APP_IMAGE"), commit=val("APP_COMMIT"),
        build=val("APP_BUILD"), deployed_at=val("APP_DEPLOYED_AT"), log_level=val("APP_LOG_LEVEL"),
        host=escape(socket.gethostname()), secret=secret_html, db_host=val("APP_DB_HOST"))


@app.get("/version")
def version():
    return jsonify(version=os.environ.get("APP_VERSION", "dev"), env=os.environ.get("APP_ENV", "local"),
                   image=os.environ.get("APP_IMAGE", ""), commit=os.environ.get("APP_COMMIT", ""))


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


@app.get("/tickets")
def tickets():
    owner = request.args.get("owner", "")
    with sqlite3.connect(DB_PATH) as conn:
        # SQL injection: ต่อ string เข้า SQL ตรงๆ
        # SonarQube Community จับบรรทัดนี้ไม่ได้ (taint analysis มีเฉพาะ Developer Edition ขึ้นไป)
        # ใช้เป็นตัวอย่างว่า SAST ไม่ได้เห็นทุกอย่าง ยังต้องมี code review และ DAST
        # วิธีที่ถูก: conn.execute("SELECT ... WHERE owner = ?", (owner,))
        rows = conn.execute("SELECT id, owner, number FROM tickets WHERE owner = '" + owner + "'").fetchall()
    return jsonify([{"id": r[0], "owner": r[1], "number": r[2]} for r in rows])


def add(a, b):
    return a + b


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8000)
