#!/usr/bin/env bash
# Hack & Shield — Service 5 deployment (HackMart coupon race-condition lab)
# Expected repository layout:
#   script/service/05_service.sh
#   service5/app.py, requirements.txt, templates/, static/
#   sql/service5_seed.sql
#   systemd/hackshield-service5.service
# UI templates, CSS, JS and SVG files are copied unchanged.

set -Eeuo pipefail
umask 027

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DIR="$REPO_DIR/service5"
SQL_SOURCE="$REPO_DIR/sql/service5_seed.sql"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service5.service"
DEST_DIR="/opt/hackshield/services/service5"
SERVICE_NAME="hackshield-service5.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"
VENV_DIR="$DEST_DIR/.venv"
STATE_DIR="/var/lib/hackshield/service5"
DB_FILE="$STATE_DIR/hackmart.db"
FLAG_DIR="/opt/flag"
FLAG_FILE="$FLAG_DIR/flag5"
LEGACY_FLAG_FILE="/opt/flags/flag5"

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=SERVICE5_FLAG bash "$SCRIPT_PATH" "$@"
fi

[[ -d "$SOURCE_DIR" ]] || { log_error "Missing service source: $SOURCE_DIR"; exit 1; }
[[ -f "$SOURCE_DIR/app.py" ]] || { log_error "Missing $SOURCE_DIR/app.py"; exit 1; }
[[ -f "$SOURCE_DIR/requirements.txt" ]] || { log_error "Missing $SOURCE_DIR/requirements.txt"; exit 1; }
[[ -d "$SOURCE_DIR/templates" ]] || { log_error "Missing templates directory: $SOURCE_DIR/templates"; exit 1; }
[[ -d "$SOURCE_DIR/static" ]] || { log_error "Missing static directory: $SOURCE_DIR/static"; exit 1; }
[[ -f "$SQL_SOURCE" ]] || { log_error "Missing SQL seed file: $SQL_SOURCE"; exit 1; }
[[ -f "$UNIT_SOURCE" ]] || { log_error "Missing systemd unit: $UNIT_SOURCE"; exit 1; }

grep -Fq '/opt/hackshield/services/service5/.venv/bin/python' "$UNIT_SOURCE" || {
    log_error 'Systemd unit ExecStart must use /opt/hackshield/services/service5/.venv/bin/python.'
    exit 1
}
grep -Fq '/opt/hackshield/services/service5/app.py' "$UNIT_SOURCE" || {
    log_error 'Systemd unit must launch /opt/hackshield/services/service5/app.py.'
    exit 1
}
grep -Fq '/var/lib/hackshield/service5' "$UNIT_SOURCE" || {
    log_error 'Systemd unit must include /var/lib/hackshield/service5 in ReadWritePaths.'
    exit 1
}

getent passwd user5 >/dev/null || { log_error 'Account user5 is missing. Run the VM setup script first.'; exit 1; }
getent group hs-service-editors >/dev/null || { log_error 'Group hs-service-editors is missing. Run the VM setup script first.'; exit 1; }

log_info 'Installing Python runtime dependencies...'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip acl

# Stop the service before backing up SQLite so the DB and WAL are consistent.
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Back up the deployed app and private database before modifying either.
BACKUP_ROOT='/opt/hackshield/backups/service5'
if [[ -d "$DEST_DIR" || -f "$DB_FILE" ]]; then
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    install -d -o root -g root -m 0700 "$BACKUP_ROOT" "$BACKUP_DIR"
    if [[ -d "$DEST_DIR" ]]; then
        install -d -o root -g root -m 0700 "$BACKUP_DIR/application"
        cp -a "$DEST_DIR/." "$BACKUP_DIR/application/"
    fi
    if [[ -f "$DB_FILE" ]]; then
        install -d -o root -g root -m 0700 "$BACKUP_DIR/database"
        cp -a "$DB_FILE" "$BACKUP_DIR/database/hackmart.db"
        [[ ! -f "$DB_FILE-wal" ]] || cp -a "$DB_FILE-wal" "$BACKUP_DIR/database/"
        [[ ! -f "$DB_FILE-shm" ]] || cp -a "$DB_FILE-shm" "$BACKUP_DIR/database/"
    fi
    log_success "Existing deployment/state backed up to $BACKUP_DIR"
fi

# Copy source into the final VM location; never copy a developer's local venv.
# Templates, CSS, JS and SVG files are copied byte-for-byte without modification.
install -d -o root -g hs-service-editors -m 2775 "$DEST_DIR"
tar --exclude='./.venv' -C "$SOURCE_DIR" -cf - . | tar -C "$DEST_DIR" -xf -
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -exec chown root:hs-service-editors {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type d -exec chmod 2775 {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type f -exec chmod 0664 {} +
usermod -a -G hs-service-editors user5

# Create/reuse the venv at the exact path referenced by systemd.
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    if [[ -e "$VENV_DIR" ]]; then
        log_warn "$VENV_DIR exists but has no executable Python; recreating it."
        rm -rf -- "$VENV_DIR"
    fi
    install -d -o user5 -g user5 -m 0750 "$VENV_DIR"
    runuser -u user5 -- python3 -m venv "$VENV_DIR"
fi
chown -R user5:user5 "$VENV_DIR"
log_info 'Installing Flask dependencies...'
runuser -u user5 -- "$VENV_DIR/bin/python" -m pip install --upgrade pip
runuser -u user5 -- "$VENV_DIR/bin/python" -m pip install -r "$DEST_DIR/requirements.txt"

# The app's live DB is private and writable only by user5, not by service editors.
install -d -o user5 -g user5 -m 0750 "$STATE_DIR"

# Seed catalogue tables and product data without deleting user/game state.
log_info 'Creating/updating HackMart catalogue tables and seed data...'
/usr/bin/python3 - "$SQL_SOURCE" "$DB_FILE" <<'PYSEED'
import sqlite3, sys
from pathlib import Path
sql_path, db_path = map(Path, sys.argv[1:3])
connection = sqlite3.connect(db_path, timeout=30)
try:
    connection.execute('PRAGMA journal_mode=WAL')
    connection.executescript(sql_path.read_text())
    connection.commit()
finally:
    connection.close()
PYSEED
chown user5:user5 "$DB_FILE"
chmod 0640 "$DB_FILE"
for state_file in "$DB_FILE-wal" "$DB_FILE-shm"; do
    [[ ! -e "$state_file" ]] || chown user5:user5 "$state_file"
done

# Keep the challenge flag outside participant-editable application files.
install -d -o root -g root -m 0711 "$FLAG_DIR"
setfacl -m u:user5:--x "$FLAG_DIR"
if [[ ! -f "$FLAG_FILE" && -f "$LEGACY_FLAG_FILE" ]]; then
    mv -- "$LEGACY_FLAG_FILE" "$FLAG_FILE"
    log_info "Migrated the existing Service 5 flag to $FLAG_FILE."
fi
if [[ ! -f "$FLAG_FILE" ]] || [[ "$(<"$FLAG_FILE")" == 'flag{hackmart_coupon_race_condition}' ]]; then
    FLAG_VALUE="${SERVICE5_FLAG:-HS{service5_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
else
    log_info "Preserving existing Service 5 flag at $FLAG_FILE."
fi
chown user5:user5 "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

# Install root-owned unit from the repository and restart.
install -o root -g root -m 0644 "$UNIT_SOURCE" "$UNIT_DEST"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 100 --no-pager || true
    log_error "$SERVICE_NAME did not start. Check the unit and application logs."
    exit 1
fi

log_info 'Waiting for the Service 5 HTTP health endpoint...'
/usr/bin/python3 - <<'PYHEALTH'
import time
import urllib.error
import urllib.request

url = 'http://127.0.0.1:8005/health'
last_error = None
for _ in range(30):
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            if response.status == 200 and b'"status":"ok"' in response.read():
                print('[INFO] Service 5 health check passed.')
                break
            last_error = f'unexpected response status {response.status}'
    except (OSError, urllib.error.URLError) as error:
        last_error = str(error)
    time.sleep(1)
else:
    raise SystemExit(f'Service 5 health check failed: {last_error}')
PYHEALTH

/usr/bin/python3 - "$DB_FILE" <<'PYVERIFY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
try:
    count = con.execute('SELECT COUNT(*) FROM products WHERE active = 1').fetchone()[0]
    print(f'[INFO] Active catalogue products: {count}')
    if count < 11:
        raise SystemExit('Expected at least 11 active products in the seeded catalogue.')
finally:
    con.close()
PYVERIFY

log_success 'Service 5 deployed successfully.'
printf '\nURL:       http://127.0.0.1:8005/\n'
printf 'App path:  %s\n' "$DEST_DIR"
printf 'Python:    %s/bin/python\n' "$VENV_DIR"
printf 'Database:  %s\n' "$DB_FILE"
printf 'SQL seed:  %s\n' "$SQL_SOURCE"
printf 'Unit:      %s\n' "$UNIT_DEST"
printf 'Flag path: %s (flag value not displayed)\n\n' "$FLAG_FILE"
systemctl --no-pager --full status "$SERVICE_NAME"
