#!/usr/bin/python3
"""Northstar corporate portal web server."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from pathlib import Path
from html import escape
import hashlib
import mimetypes
import pymysql

ROOT = Path("/opt/hackshield/services/service1")
PAGES = ROOT / "pages"
STATIC = ROOT / "static"
HOST, PORT = "0.0.0.0", 9001
FLAG_PATH = "/opt/flags/flag1"

def db_connect():
    return pymysql.connect(
        host="127.0.0.1", user="northstar", password="",
        database="employees", connect_timeout=3,
        cursorclass=pymysql.cursors.DictCursor
    )

def render_page(filename, **values):
    defaults = {"notice": "", "username": "", "person_name": "Colleague",
                "department": "General", "role": "Employee", "secure_item": ""}
    defaults.update(values)
    text = (PAGES / filename).read_text(encoding="utf-8")
    for key, value in defaults.items():
        text = text.replace("{{" + key + "}}", str(value))
    return text

class Handler(BaseHTTPRequestHandler):
    def send_body(self, status, body, content_type="text/html; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store" if content_type.startswith("text/html") else "public, max-age=3600")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        routes = {
            "/": ("index.html", "200"),
            "/about": ("about.html", "200"),
            "/help": ("help.html", "200"),
            "/privacy": ("privacy.html", "200"),
            "/terms": ("terms.html", "200"),
            "/status": ("status.html", "200"),
        }
        if path.startswith("/static/"):
            rel = path.removeprefix("/static/")
            target = (STATIC / rel).resolve()
            if not str(target).startswith(str(STATIC.resolve())) or not target.is_file():
                return self.send_body(404, "Not found", "text/plain; charset=utf-8")
            ctype = mimetypes.guess_type(str(target))[0] or "application/octet-stream"
            return self.send_body(200, target.read_bytes(), ctype)
        if path in routes:
            filename, _ = routes[path]
            return self.send_body(200, render_page(filename))
        if path == "/dashboard":
            return self.send_body(200, render_page("dashboard.html",
                person_name="Raihan", department="Administration",
                role="Administrator", secure_item=""))
        if path == "/directory":
            return self.send_body(200, render_page("directory.html"))
        return self.send_body(404, render_page("404.html"), "text/html; charset=utf-8")

    def do_POST(self):
        if urlparse(self.path).path != "/login":
            return self.send_body(404, render_page("404.html"))
        try:
            length = min(int(self.headers.get("Content-Length", "0")), 16384)
            form = parse_qs(self.rfile.read(length).decode("utf-8", errors="replace"))
            username = form.get("user", [""])[0].strip()
            password = form.get("pass", [""])[0]
            digest = hashlib.sha256(password.encode()).hexdigest()
            conn = db_connect()
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT username, full_name, department, role FROM staff "
                        "WHERE username=%s AND password_hash=%s",
                        (username, digest)
                    )
                    account = cur.fetchone()
            finally:
                conn.close()
        except Exception as exc:
            print("Identity service error:", type(exc).__name__, flush=True)
            return self.send_body(503, render_page("index.html",
                notice='<div class="notice notice-error">Sign-in is temporarily unavailable. Please try again shortly.</div>'))

        if not account:
            safe_user = escape(username, quote=True)
            notice = '<div class="notice notice-error" role="alert">We could not verify those details. Please try again.</div>'
            return self.send_body(403, render_page("index.html", notice=notice, username=safe_user))

        if username.lower() == "raihan":
            try:
                with open(FLAG_PATH, encoding="utf-8") as handle:
                    flag = escape(handle.read().strip())
                secure_item = '<div class="secure-record"><span class="eyebrow">Restricted account record</span><code>' + flag + '</code></div>'
            except OSError:
                secure_item = '<div class="notice notice-error">Your account is active, but this record is currently unavailable.</div>'
            body = render_page("dashboard.html",
                person_name=escape(account.get("full_name") or username),
                department=escape(account.get("department") or "Administration"),
                role=escape(account.get("role") or "Administrator"),
                secure_item=secure_item)
        else:
            body = render_page("dashboard.html",
                person_name=escape(account.get("full_name") or username),
                department=escape(account.get("department") or "General"),
                role=escape(account.get("role") or "Employee"),
                secure_item="")
        self.send_body(200, body)

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} - {fmt % args}", flush=True)

if __name__ == "__main__":
    print(f"Northstar portal listening on {HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
