import base64
import binascii
import os
from functools import wraps
from pathlib import Path

from flask import (
    Flask, render_template, request,
    redirect, url_for, make_response
)

app = Flask(__name__)

COMPANY = "ByteForge Technologies"
FLAG_FILE = Path("/opt/flags/flag7")
FLAG = FLAG_FILE.read_text(encoding="utf-8").strip()

# Intentionally simple credentials for this isolated CTF.
USERNAME = "employee"
PASSWORD = "employee"


def encode_role(role):
    # The newline is intentional to match the challenge story.
    raw = f"role={role}\n".encode("utf-8")
    return base64.b64encode(raw).decode("ascii")


def get_role():
    """
    INTENTIONALLY VULNERABLE:
    The application trusts a client-controlled, unsigned cookie.
    Base64 encoding does not provide integrity or authentication.
    """
    cookie = request.cookies.get("auth")

    if not cookie:
        return None

    try:
        decoded = base64.b64decode(
            cookie, validate=True
        ).decode("utf-8")

        # Only explicitly recognized roles are accepted.
        if decoded == "role=user\n":
            return "user"

        if decoded == "role=admin\n":
            return "admin"

        return None

    except (binascii.Error, UnicodeDecodeError, ValueError):
        return None


def require_login(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        role = get_role()

        if role not in ("user", "admin"):
            if request.cookies.get("auth"):
                return render_template(
                    "error.html",
                    message="Invalid authentication cookie."
                ), 401

            return redirect(url_for("login"))

        return view(*args, **kwargs)

    return wrapped


@app.after_request
def identify_company(response):
    # Secondary discovery objective for Nmap HTTP service detection.
    response.headers["Server"] = (
        "ByteForge Technologies Employee Portal"
    )
    response.headers["X-Company"] = COMPANY
    return response


@app.route("/")
def index():
    return render_template("index.html", company=COMPANY)


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None

    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")

        if username == USERNAME and password == PASSWORD:
            response = make_response(
                redirect(url_for("dashboard"))
            )

            # INTENTIONALLY VULNERABLE:
            # The role is stored in a modifiable browser cookie.
            response.set_cookie(
                "auth",
                encode_role("user"),
                httponly=True,
                samesite="Lax"
            )

            return response

        error = "Invalid username or password."

    return render_template("login.html", error=error)


@app.route("/dashboard")
@require_login
def dashboard():
    role = get_role()

    if role == "admin":
        return render_template(
            "dashboard.html",
            company=COMPANY,
            role="Administrator",
            flag=FLAG
        )

    return render_template(
        "dashboard.html",
        company=COMPANY,
        role="Employee",
        flag=None
    )



@app.route("/profile")
@require_login
def profile():
    role = get_role()

    if role == "admin":
        return render_template(
            "profile.html",
            company=COMPANY,
            role="Administrator",
            employee_id="BF-0001",
            department="Human Resources",
            access_level="Full Administrative Access"
        )

    return render_template(
        "profile.html",
        company=COMPANY,
        role="Employee",
        employee_id="BF-1042",
        department="Engineering",
        access_level="Standard Employee Access"
    )



@app.route("/announcements")
@require_login
def announcements():
    return render_template(
        "announcements.html", company=COMPANY
    )


@app.route("/documents")
@require_login
def documents():
    return render_template("documents.html", company=COMPANY)


@app.route("/logout")
def logout():
    response = make_response(redirect(url_for("index")))
    response.delete_cookie("auth")
    return response


if __name__ == "__main__":
    # Accessible to other machines on the challenge network.
    # Restrict the port to your isolated CTF network/firewall.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5007")), debug=False)
