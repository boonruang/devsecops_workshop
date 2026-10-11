"""แอปตัวอย่างสำหรับ workshop: ตั้งใจใส่จุดอ่อนไว้ให้ SonarQube กับ Trivy เจอ ห้ามนำไปใช้จริง"""
import hashlib
import os
import socket
import sqlite3
from html import escape

from flask import Flask, jsonify, request

app = Flask(__name__)
DB_PATH = os.environ.get("DB_PATH", "/tmp/lab.db")


def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS tickets (id INTEGER PRIMARY KEY, owner TEXT, number TEXT)")
        conn.execute("INSERT OR IGNORE INTO tickets VALUES (1, 'somchai', '123456')")


PAGE = """<!doctype html>
<html lang="th"><head><meta charset="utf-8"><title>Workshop Sample App</title>
<style>body{{font-family:sans-serif;max-width:640px;margin:40px auto;padding:0 16px;color:#222}}
table{{border-collapse:collapse}}td{{padding:6px 12px;border-bottom:1px solid #ddd}}code{{background:#f3f3f3;padding:2px 4px}}</style>
</head><body>
<h1>Workshop Sample App <span style="background:{color};color:#fff;padding:2px 10px;border-radius:4px;font-size:.6em">{env}</span></h1>
<table>
<tr><td>environment</td><td><code>{env}</code></td></tr>
<tr><td>version</td><td><code>{version}</code></td></tr>
<tr><td>container</td><td><code>{host}</code></td></tr>
<tr><td>APP_SECRET_KEY จาก Vault</td><td>{secret}</td></tr>
<tr><td>APP_DB_HOST จาก Vault</td><td><code>{db_host}</code></td></tr>
</table>
<h2>ค้นหา ticket</h2>
<form action="/tickets"><input name="owner" placeholder="owner เช่น somchai"> <button>ค้นหา</button></form>
</body></html>"""


ENV_COLORS = {"dev": "#2e7d32", "uat": "#ef6c00", "prd": "#c62828"}


@app.get("/")
def index():
    # ค่าจาก secret/<env>/app-env ไปถึง container ทางเดียว: Jenkins อ่านจาก Vault ตอน deploy แล้วส่งเข้า --env-file
    # หน้าเว็บแสดงแค่ความยาวกับ sha256 ไว้เทียบกับ Vault ไม่แสดงค่าจริง
    secret = os.environ.get("APP_SECRET_KEY", "")
    if secret:
        fp = hashlib.sha256(secret.encode()).hexdigest()[:12]
        secret_html = f"ได้รับแล้ว ยาว {len(secret)} ตัวอักษร · sha256 <code>{fp}</code>"
    else:
        secret_html = "ยังไม่ได้รับ"
    env = os.environ.get("APP_ENV", "local")
    return PAGE.format(env=escape(env), color=ENV_COLORS.get(env, "#666"),
                       version=escape(os.environ.get("APP_VERSION", "dev")),
                       host=escape(socket.gethostname()), secret=secret_html,
                       db_host=escape(os.environ.get("APP_DB_HOST", "-")))


@app.get("/version")
def version():
    return jsonify(version=os.environ.get("APP_VERSION", "dev"), env=os.environ.get("APP_ENV", "local"))


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
