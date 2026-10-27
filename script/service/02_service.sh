#!/usr/bin/env bash
# Hack & Shield — Service 2 ShoeMart deployment.
# Database schema and synthetic seed data live separately in sql/service2_seed.sql.
set -Eeuo pipefail
umask 027

log_info()    { printf '\033[0;34m[INFO]\033[0m %s\n' "$*"; }
log_success() { printf '\033[0;32m[SUCCESS]\033[0m %s\n' "$*"; }
log_warn()    { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
log_error()   { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="$REPO_DIR/service2"
SEED_SQL="$REPO_DIR/sql/service2_seed.sql"
SOURCE_UNIT="$REPO_DIR/systemd/hackshield-service2.service"
DEST_DIR="/opt/hackshield/services/service2"
DB_DIR="/var/lib/hackshield/service2"
DB_FILE="$DB_DIR/shop.sqlite3"
FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag2"
SESSION_ENV_DIR="/etc/hackshield"
SESSION_ENV_FILE="$SESSION_ENV_DIR/service2.env"
SERVICE_NAME="hackshield-service2.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"
EDITORS_GROUP="hs-service-editors"
SERVICE_USER="user2"
PORT="4444"
RESEED="${SERVICE2_RESEED:-0}"

if [[ "$EUID" -ne 0 ]]; then
    log_info "Re-running with sudo. For overrides, use sudo -E with SERVICE2_FLAG / SERVICE2_ADMIN_PASSWORD / SERVICE2_RESEED."
    exec sudo --preserve-env=SERVICE2_FLAG,SERVICE2_ADMIN_PASSWORD,SERVICE2_RESEED bash "$SCRIPT_PATH" "$@"
fi

# 1. Validate required source files
[[ -f "$SOURCE_DIR/app.py" && -d "$SOURCE_DIR/templates" && -d "$SOURCE_DIR/static" ]] || {
    log_error "Missing Service 2 application files under $SOURCE_DIR"; exit 1;
}
[[ -f "$SEED_SQL" ]] || { log_error "Missing external SQL seed file: $SEED_SQL"; exit 1; }
[[ -f "$SOURCE_UNIT" ]] || { log_error "Missing existing systemd unit: $SOURCE_UNIT"; exit 1; }

# 2. Install system dependencies
log_info "Installing Python, venv, SQLite CLI and ACL dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip sqlite3 acl curl

# 3. Deploy UI and application code
log_info "Deploying ShoeMart application/templates/static..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
install -d -o root -g "$EDITORS_GROUP" -m 2775 "$DEST_DIR"
cp -a "$SOURCE_DIR/." "$DEST_DIR/"
chown -R root:"$EDITORS_GROUP" "$DEST_DIR"
find "$DEST_DIR" -type d -exec chmod 2775 {} +
find "$DEST_DIR" -type f -exec chmod 0664 {} +

# 4. Initialize or reseed database from SQL file (Backup logic removed)
install -d -o root -g "$SERVICE_USER" -m 0710 "$DB_DIR"

if [[ -f "$DB_FILE" && "$RESEED" == "1" ]]; then
    log_warn "SERVICE2_RESEED=1: removing existing database and rebuilding from $SEED_SQL"
    rm -f "$DB_FILE"
fi

if [[ ! -f "$DB_FILE" ]]; then
    log_info "Seeding SQLite database using $SEED_SQL..."
    ADMIN_PASSWORD="${SERVICE2_ADMIN_PASSWORD:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')}"
    python3 - "$DB_FILE" "$SEED_SQL" "$ADMIN_PASSWORD" <<'PY'
import sqlite3, sys
from pathlib import Path

db_path, seed_path, admin_password = sys.argv[1:4]
seed_sql = Path(seed_path).read_text(encoding="utf-8")
conn = sqlite3.connect(db_path)
try:
    conn.executescript(seed_sql)
    conn.execute("UPDATE admin_users SET password = ? WHERE username = 'admin'", (admin_password,))
    conn.commit()
    
    required = {
        "products": {"id", "product_name", "price", "sku"},
        "admin_users": {"username", "password"},
    }
    for table, expected in required.items():
        actual = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
        missing = expected - actual
        if missing:
            raise RuntimeError(f"{table} is missing required columns: {sorted(missing)}")
            
    count = conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    if count < 10:
        raise RuntimeError(f"Expected a realistic product catalogue; found only {count} products")
except Exception:
    conn.rollback()
    conn.close()
    Path(db_path).unlink(missing_ok=True)
    raise
finally:
    try: conn.close()
    except Exception: pass
PY
    log_success "Database seeded from the external SQL file ($DB_FILE)"
else
    log_warn "Database exists; preserving its contents. Set SERVICE2_RESEED=1 to rebuild from the SQL file."
fi

chown root:"$SERVICE_USER" "$DB_FILE"
chmod 0440 "$DB_FILE"
chown root:"$SERVICE_USER" "$DB_DIR"
chmod 0710 "$DB_DIR"

# 5. Configure protected flag
install -d -o root -g root -m 0711 "$FLAG_DIR"
if [[ ! -f "$FLAG_FILE" ]]; then
    FLAG_VALUE="${SERVICE2_FLAG:-HS{service2_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
    log_success "Created protected flag at $FLAG_FILE"
else
    log_warn "Existing flag preserved: $FLAG_FILE"
fi
chown "$SERVICE_USER":"$SERVICE_USER" "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"
setfacl -m "u:${SERVICE_USER}:--x" "$FLAG_DIR"

# Flask's cookie signing key must not be a published constant. systemd reads
# this root-owned file and passes the value to the service process.
install -d -o root -g root -m 0755 "$SESSION_ENV_DIR"
if [[ ! -f "$SESSION_ENV_FILE" ]]; then
    SESSION_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
    (umask 077; printf 'SHOEMART_SESSION_SECRET=%s\n' "$SESSION_SECRET" > "$SESSION_ENV_FILE")
fi
chown root:root "$SESSION_ENV_FILE"
chmod 0600 "$SESSION_ENV_FILE"

# 6. Prepare virtual environment & install dependencies
log_info "Preparing Flask virtual environment..."
if [[ ! -x "$DEST_DIR/.venv/bin/python" ]]; then 
    python3 -m venv "$DEST_DIR/.venv" 
fi
"$DEST_DIR/.venv/bin/python" -m pip install --upgrade pip
"$DEST_DIR/.venv/bin/python" -m pip install 'Flask>=3.0,<4.0'
chown -R root:"$EDITORS_GROUP" "$DEST_DIR/.venv"
find "$DEST_DIR/.venv" -type d -exec chmod 2775 {} +
find "$DEST_DIR/.venv" -type f -exec chmod 0664 {} +
find "$DEST_DIR/.venv/bin" -maxdepth 1 -type f -exec chmod 0775 {} +

# 7. Configure systemd unit
log_info "Copying systemd unit from $SOURCE_UNIT..."
cp -- "$SOURCE_UNIT" "$UNIT_DEST"
chown root:root "$UNIT_DEST"
chmod 0644 "$UNIT_DEST"

# 8. Start and verify service
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
sleep 2

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
    log_error "Service 2 failed to start; inspect the journal above."
    exit 1
fi
if ! curl --fail --silent --show-error --max-time 5 http://127.0.0.1:4444/products >/dev/null; then
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
    log_error "Service 2 storefront/database check failed on port 4444."
    exit 1
fi

log_success "Service 2 deployed and active."
printf '\nStorefront:   http://127.0.0.1:%s/\nProducts:     http://127.0.0.1:%s/products\nSearch:       http://127.0.0.1:%s/search?q=runner\nAdmin login:  http://127.0.0.1:%s/admin/login\nDatabase:     %s\nSeed SQL:     %s\nFlag file:    %s\nSystemd unit: %s\nUnit source:  %s\n\n' "$PORT" "$PORT" "$PORT" "$PORT" "$DB_FILE" "$SEED_SQL" "$FLAG_FILE" "$SERVICE_NAME" "$SOURCE_UNIT"
echo "Default seeded admin username: admin"
echo "Admin password is generated per VM and is not printed; obtain it from the organizer if required."
echo "The flag is generated per VM. Keep this intentionally vulnerable service on the isolated competition network."
systemctl --no-pager --full status "$SERVICE_NAME"
