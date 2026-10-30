#!/usr/bin/env bash
# Hack & Shield — Service 10 deployment
# Patient records / IDOR / share abuse lab with backup download endpoint.

set -Eeuo pipefail
umask 027

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SERVICE_ID="${SERVICE_ID:-10}"
SERVICE_USER="${SERVICE_USER:-user${SERVICE_ID}}"
SERVICE_GROUP="${SERVICE_GROUP:-user${SERVICE_ID}}"
SERVICE_NAME="${SERVICE_NAME:-hackshield-service${SERVICE_ID}.service}"

SOURCE_DIR="${SOURCE_DIR:-$REPO_DIR/service${SERVICE_ID}}"
SQL_SOURCE="${SQL_SOURCE:-$REPO_DIR/sql/service${SERVICE_ID}_seed.sql}"
UNIT_SOURCE="${UNIT_SOURCE:-$REPO_DIR/systemd/hackshield-service${SERVICE_ID}.service}"

DEST_DIR="${DEST_DIR:-/opt/hackshield/services/service${SERVICE_ID}}"
VENV_DIR="$DEST_DIR/.venv"
DB_DIR="/var/lib/hackshield/service${SERVICE_ID}"
DB_FILE="$DB_DIR/service${SERVICE_ID}.sqlite3"
FLAG_DIR="/opt/flags"
FLAG_ZIP="$FLAG_DIR/flag${SERVICE_ID}.zip"
SERVICE_BUNDLE_SEED="$DEST_DIR/seed.sql"
SERVICE_DB_MODULE="$DEST_DIR/database.py"

SERVICE_PORT="${SERVICE_PORT:-5000}"

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=SERVICE10_FLAG bash "$SCRIPT_PATH" "$@"
fi

[[ -d "$SOURCE_DIR" ]] || { log_error "Missing source directory: $SOURCE_DIR"; exit 1; }
[[ -f "$SOURCE_DIR/app.py" ]] || { log_error "Missing app.py"; exit 1; }
[[ -f "$SOURCE_DIR/requirements.txt" ]] || { log_error "Missing requirements.txt"; exit 1; }
[[ -d "$SOURCE_DIR/templates" ]] || { log_error "Missing templates directory"; exit 1; }
[[ -d "$SOURCE_DIR/static" ]] || { log_error "Missing static directory"; exit 1; }
[[ -f "$SQL_SOURCE" ]] || { log_error "Missing SQL seed file: $SQL_SOURCE"; exit 1; }
[[ -f "$UNIT_SOURCE" ]] || { log_error "Missing systemd unit: $UNIT_SOURCE"; exit 1; }

getent passwd "$SERVICE_USER" >/dev/null || {
    log_error "$SERVICE_USER does not exist. Run the VM setup first."
    exit 1
}
getent group "$SERVICE_GROUP" >/dev/null || {
    log_error "$SERVICE_GROUP does not exist. Run the VM setup first."
    exit 1
}

log_info "Installing Python, venv, ACL and zip tools..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip acl curl zip

BACKUP_ROOT="/opt/hackshield/backups/service${SERVICE_ID}"
if [[ -d "$DEST_DIR" ]]; then
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    install -d -o root -g root -m 0700 "$BACKUP_ROOT" "$BACKUP_DIR"
    cp -a "$DEST_DIR/." "$BACKUP_DIR/"
    log_success "Existing deployment backed up to $BACKUP_DIR"
fi

systemctl stop "$SERVICE_NAME" 2>/dev/null || true

log_info "Deploying application to $DEST_DIR..."
install -d -o root -g "$SERVICE_GROUP" -m 2775 "$DEST_DIR"
tar --exclude='./.venv' -C "$SOURCE_DIR" -cf - . | tar -C "$DEST_DIR" -xf -

chown -R root:"$SERVICE_GROUP" "$DEST_DIR"
find "$DEST_DIR" -type d -exec chmod 2775 {} +
find "$DEST_DIR" -type f -exec chmod 0664 {} +

install -d -o root -g user10 -m 0750 "$DB_DIR"
install -d -o root -g root -m 0755 "$DEST_DIR/documents"
install -d -o root -g root -m 0755 "$DEST_DIR/backups"

cat > "$SERVICE_BUNDLE_SEED" <<'SEED'
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS doctors (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    specialty TEXT NOT NULL,
    email TEXT NOT NULL,
    office TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS patients (
    uuid TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    doctor_id INTEGER NOT NULL,
    dob TEXT NOT NULL,
    gender TEXT NOT NULL,
    phone TEXT NOT NULL,
    diagnosis TEXT NOT NULL,
    last_visit TEXT NOT NULL,
    FOREIGN KEY (doctor_id) REFERENCES doctors(id)
);

CREATE TABLE IF NOT EXISTS documents (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS shares (
    share_id INTEGER PRIMARY KEY,
    owner_id INTEGER NOT NULL,
    document_id INTEGER NOT NULL,
    expiry TEXT NOT NULL,
    FOREIGN KEY (document_id) REFERENCES documents(id)
);

INSERT OR REPLACE INTO doctors (id, name, specialty, email, office) VALUES
(1, 'Dr. Nadia Iyer', 'Internal Medicine', 'nadia.iyer@byteforge.local', 'Block A - 204'),
(2, 'Dr. Sameer Bose', 'Cardiology', 'sameer.bose@byteforge.local', 'Block B - 118'),
(3, 'Dr. Tara Menon', 'Orthopedics', 'tara.menon@byteforge.local', 'Block C - 302');

INSERT OR REPLACE INTO patients (uuid, name, doctor_id, dob, gender, phone, diagnosis, last_visit) VALUES
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1001', 'Ananya Rao', 1, '1991-02-14', 'Female', '9876501001', 'Hypertension', '2026-10-12'),
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1002', 'Mohit Varma', 2, '1987-07-03', 'Male', '9876501002', 'Arrhythmia follow-up', '2026-10-08'),
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1003', 'Sahana Krish', 3, '1994-11-26', 'Female', '9876501003', 'Knee injury rehab', '2026-10-15'),
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1004', 'Arjun Nair', 1, '1989-05-09', 'Male', '9876501004', 'Diabetes management', '2026-10-18');

INSERT OR REPLACE INTO documents (id, title, filename, file_path) VALUES
(21, 'Reception Schedule', 'reception_schedule.txt', 'documents/reception_schedule.txt'),
(22, 'Patient Transfer Notes', 'patient_transfer_notes.txt', 'documents/patient_transfer_notes.txt'),
(23, 'Vendor List', 'vendor_list.txt', 'documents/vendor_list.txt'),
(51, 'October Backup Manifest', 'october_backup_manifest.txt', 'documents/october_backup_manifest.txt'),
(52, 'Payroll Snapshot', 'payroll_snapshot.txt', 'documents/payroll_snapshot.txt'),
(53, 'Executive Contacts', 'executive_contacts.txt', 'documents/executive_contacts.txt');

INSERT OR REPLACE INTO shares (share_id, owner_id, document_id, expiry) VALUES
(908, 1, 21, '2026-12-31'),
(909, 2, 22, '2026-12-31'),
(910, 3, 23, '2026-12-31');
SEED

cat > "$DEST_DIR/documents/reception_schedule.txt" <<'TXT'
Reception schedule
- Morning shift: 08:00 to 14:00
- Evening shift: 14:00 to 20:00
TXT

cat > "$DEST_DIR/documents/patient_transfer_notes.txt" <<'TXT'
Patient transfer notes
- Verify patient wristband
- Confirm ward and receiving doctor
- Attach transport summary
TXT

cat > "$DEST_DIR/documents/vendor_list.txt" <<'TXT'
Vendor list
- Facility supplies
- Catering
- Maintenance
TXT

cat > "$DEST_DIR/documents/october_backup_manifest.txt" <<'TXT'
October backup manifest
- Archive checksum verified
- Backup rotation completed
TXT

cat > "$DEST_DIR/documents/payroll_snapshot.txt" <<'TXT'
Payroll snapshot
- Internal finance document
- Access restricted to HR
TXT

cat > "$DEST_DIR/documents/executive_contacts.txt" <<'TXT'
Executive contacts
- CEO office
- Operations lead
- Legal contact
TXT

cat > "$SERVICE_DB_MODULE" <<'PY'
from pathlib import Path
import os
import sqlite3

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("DB_PATH", "/var/lib/hackshield/service10/service10.sqlite3"))
SEED_SQL = BASE_DIR / "seed.sql"

def get_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    if DB_PATH.exists():
        return
    conn = get_db()
    try:
        conn.executescript(SEED_SQL.read_text(encoding="utf-8"))
        conn.commit()
    finally:
        conn.close()
PY

python3 - "$DB_FILE" "$SERVICE_BUNDLE_SEED" <<'PY'
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1])
seed_path = Path(sys.argv[2])

conn = sqlite3.connect(db_path)
try:
    conn.executescript(seed_path.read_text(encoding="utf-8"))
    conn.commit()
finally:
    conn.close()
PY

chown -R user10:user10 "$DB_DIR"
chmod 0750 "$DB_DIR"
chmod 0640 "$DB_FILE"

install -d -o root -g root -m 0711 "$FLAG_DIR"
setfacl -m u:user10:--x "$FLAG_DIR"

if [[ ! -f "$FLAG_ZIP" ]]; then
    FLAG_VALUE="${SERVICE10_FLAG:-HS{service10_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    tmpdir="$(mktemp -d)"
    printf '%s\n' "$FLAG_VALUE" > "$tmpdir/flag10.txt"
    (cd "$tmpdir" && zip -qj "$FLAG_ZIP" flag10.txt)
    rm -rf "$tmpdir"
fi

chown user10:user10 "$FLAG_ZIP"
chmod 0400 "$FLAG_ZIP"

python3 - "$DEST_DIR/app.py" <<'PY'
from pathlib import Path
import re
import sys

app = Path(sys.argv[1])
text = app.read_text(encoding="utf-8")

if 'from zipfile import ZipFile' not in text:
    text = text.replace(
        'from pathlib import Path\n',
        'from pathlib import Path\nfrom zipfile import ZipFile\n',
        1,
    )

text = text.replace(
    'FLAG = "FLAG{client_side_trust_is_dangerous}"',
    'FLAG_ARCHIVE = Path("/opt/flags/flag10.zip")\nwith ZipFile(FLAG_ARCHIVE) as zf:\n    FLAG = zf.read("flag10.txt").decode("utf-8").strip()',
    1,
)

text = text.replace(
    '    path = BASE_DIR / "backups" / "october_backup.zip"\n',
    '    path = Path("/opt/flags/flag10.zip")\n',
    1,
)

app.write_text(text, encoding="utf-8")
PY

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 "$VENV_DIR"
    runuser -u "$SERVICE_USER" -- python3 -m venv "$VENV_DIR"
fi

chown -R "$SERVICE_USER":"$SERVICE_USER" "$VENV_DIR"
runuser -u "$SERVICE_USER" -- "$VENV_DIR/bin/python" -m pip install --upgrade pip
runuser -u "$SERVICE_USER" -- "$VENV_DIR/bin/python" -m pip install -r "$DEST_DIR/requirements.txt"

install -o root -g root -m 0644 "$UNIT_SOURCE" "/etc/systemd/system/$SERVICE_NAME"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 100 --no-pager || true
    log_error "$SERVICE_NAME did not start."
    exit 1
fi

if ! curl --fail --silent --show-error --max-time 5 \
    http://127.0.0.1:"$SERVICE_PORT"/backups/october_backup.zip >/dev/null; then
    journalctl -u "$SERVICE_NAME" -n 100 --no-pager || true
    log_error "Backup endpoint check failed."
    exit 1
fi

log_success "Service ${SERVICE_ID} deployed successfully."
printf '\nURL:       http://127.0.0.1:%s/\n' "$SERVICE_PORT"
printf 'App path:  %s\n' "$DEST_DIR"
printf 'Database:  %s\n' "$DB_FILE"
printf 'Flag zip:  %s\n' "$FLAG_ZIP"
printf 'Systemd:   %s\n\n' "$SERVICE_NAME"
systemctl --no-pager --full status "$SERVICE_NAME"
