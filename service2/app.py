#!/usr/bin/env python3
"""ShoeMart - Hack & Shield Service 2.
The /search route intentionally retains UNION-based SQL injection for the isolated CTF.
Do not deploy this challenge app to a public network.
"""
import os
import sqlite3
from flask import Flask, request, render_template, session, redirect, url_for

app = Flask(__name__)
app.secret_key = os.environ.get("SHOEMART_SESSION_SECRET") or os.urandom(32)
DB_PATH = os.environ.get("DB_PATH", "/var/lib/hackshield/service2/shop.sqlite3")
FLAG_PATH = "/opt/flags/flag2"
PORT = int(os.environ.get("PORT", "4444"))

def get_db():
    return sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=3)

@app.context_processor
def inject_globals():
    return {"cart_count": session.get("cart_count", 0)}

@app.get("/")
def index():
    return render_template("index.html", active="home")

@app.get("/products")
def products():
    conn = get_db()
    try:
        rows = conn.execute("SELECT id, product_name, price, sku FROM products ORDER BY id").fetchall()
    finally:
        conn.close()
    return render_template("products.html", products=rows, active="products")

@app.get("/product/<int:product_id>")
def product_detail(product_id):
    conn = get_db()
    try:
        product = conn.execute(
            "SELECT id, product_name, price, sku FROM products WHERE id = ?", (product_id,)
        ).fetchone()
    finally:
        conn.close()
    if product is None:
        return render_template("404.html"), 404
    return render_template("product_detail.html", product=product, active="products")

@app.get("/search")
def search():
    q = request.args.get("q", "")
    if len(q) > 300:
        return "Query too long", 400
    conn = get_db()
    try:
        # INTENTIONALLY VULNERABLE: preserve this string concatenation for the CTF.
        sql = f"SELECT id, product_name, price FROM products WHERE product_name LIKE '%{q}%'"
        rows = conn.execute(sql).fetchall()
        return render_template("search.html", q=q, products=rows, active="search")
    except sqlite3.Error:
        return render_template("search.html", q=q, products=[], search_error=True, active="search"), 400
    finally:
        conn.close()

@app.get("/about")
def about():
    return render_template("about.html", active="about")

@app.get("/contact")
def contact():
    return render_template("contact.html", active="contact")

@app.get("/admin/login")
def admin_login_form():
    return render_template("admin_login.html", error=False)

@app.post("/admin/login")
def admin_login():
    username = request.form.get("username", "")
    password = request.form.get("password", "")
    conn = get_db()
    try:
        # Intentionally safe: login uses parameterized SQL.
        row = conn.execute(
            "SELECT username FROM admin_users WHERE username = ? AND password = ?",
            (username, password),
        ).fetchone()
    finally:
        conn.close()
    if row is None:
        return render_template("admin_login.html", error=True), 403
    session["admin_user"] = row[0]
    try:
        with open(FLAG_PATH, encoding="utf-8") as f:
            flag = f.read().strip()
    except Exception:
        flag = "(flag file unreadable)"
    return render_template("admin_dashboard.html", user=row[0], flag=flag)

@app.get("/admin")
def admin_dashboard():
    if not session.get("admin_user"):
        return redirect(url_for("admin_login_form"))
    try:
        with open(FLAG_PATH, encoding="utf-8") as f:
            flag = f.read().strip()
    except Exception:
        flag = "(flag file unreadable)"
    return render_template("admin_dashboard.html", user=session["admin_user"], flag=flag)

@app.get("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))

@app.errorhandler(404)
def not_found(_error):
    return render_template("404.html"), 404

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT, debug=False)
