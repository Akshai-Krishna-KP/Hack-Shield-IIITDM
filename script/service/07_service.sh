#!/usr/bin/env bash
# Hack & Shield — Service 7 deployment (Client-side Trust / Cookie Tampering Lab)

set -Eeuo pipefail
umask 027

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DIR="$REPO_DIR/service7"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service7.service"

DEST_DIR="/opt/hackshield/services/service7"
VENV_DIR="$DEST_DIR/.venv"

SERVICE_NAME="hackshield-service7.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"

FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag7"

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=SERVICE7_FLAG bash "$SCRIPT_PATH" "$@"
fi

# --------------------------------------------------
# Validate repository
# --------------------------------------------------

[[ -d "$SOURCE_DIR" ]] || {
    log_error "Missing service directory: $SOURCE_DIR"
    exit 1
}

[[ -f "$SOURCE_DIR/app.py" ]] || {
    log_error "Missing app.py"
    exit 1
}

[[ -f "$SOURCE_DIR/requirements.txt" ]] || {
    log_error "Missing requirements.txt"
    exit 1
}

[[ -d "$SOURCE_DIR/templates" ]] || {
    log_error "Missing templates directory"
    exit 1
}

[[ -f "$UNIT_SOURCE" ]] || {
    log_error "Missing systemd unit"
    exit 1
}

getent passwd user7 >/dev/null || {
    log_error "user7 does not exist."
    exit 1
}

getent group hs-service-editors >/dev/null || {
    log_error "hs-service-editors does not exist."
    exit 1
}

# --------------------------------------------------
# Install dependencies
# --------------------------------------------------

log_info "Installing Python dependencies..."

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-venv \
    python3-pip \
    acl \
    curl

# --------------------------------------------------
# Backup existing deployment
# --------------------------------------------------

if [[ -d "$DEST_DIR" ]]; then

    BACKUP_ROOT="/opt/hackshield/backups/service7"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"

    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    install -d -o root -g root -m 0700 "$BACKUP_DIR"

    cp -a "$DEST_DIR/." "$BACKUP_DIR/"

    log_success "Existing deployment backed up."

fi

systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# --------------------------------------------------
# Deploy application
# --------------------------------------------------

install -d -o root -g hs-service-editors -m 2775 "$DEST_DIR"

tar --exclude='./.venv' \
    -C "$SOURCE_DIR" \
    -cf - . | tar -C "$DEST_DIR" -xf -

find "$DEST_DIR" \
    -path "$VENV_DIR" -prune \
    -o -exec chown root:hs-service-editors {} +

find "$DEST_DIR" \
    -path "$VENV_DIR" -prune \
    -o -type d -exec chmod 2775 {} +

find "$DEST_DIR" \
    -path "$VENV_DIR" -prune \
    -o -type f -exec chmod 0664 {} +

# --------------------------------------------------
# Create venv
# --------------------------------------------------

if [[ ! -x "$VENV_DIR/bin/python" ]]; then

    install -d -o user7 -g user7 -m 0750 "$VENV_DIR"

    runuser -u user7 -- python3 -m venv "$VENV_DIR"

fi

chown -R user7:user7 "$VENV_DIR"

runuser -u user7 -- "$VENV_DIR/bin/python" \
    -m pip install --upgrade pip

runuser -u user7 -- "$VENV_DIR/bin/python" \
    -m pip install -r "$DEST_DIR/requirements.txt"

# --------------------------------------------------
# Protected flag
# --------------------------------------------------

install -d -o root -g root -m 0711 "$FLAG_DIR"

setfacl -m u:user7:--x "$FLAG_DIR"

if [[ ! -f "$FLAG_FILE" ]]; then

    FLAG_VALUE="${SERVICE7_FLAG:-HS{service7_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"

    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"

fi

chown user7:user7 "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

# --------------------------------------------------
# Patch app.py
# --------------------------------------------------

python3 - "$DEST_DIR/app.py" <<'PY'
from pathlib import Path
import re
import sys

app = Path(sys.argv[1])

text = app.read_text()

text = re.sub(
    r'FLAG\s*=\s*"[^"]+"',
    '''FLAG_FILE = Path("/opt/flags/flag7")
FLAG = FLAG_FILE.read_text(encoding="utf-8").strip()''',
    text,
    count=1
)

app.write_text(text)
PY

# --------------------------------------------------
# Install systemd unit
# --------------------------------------------------

install -o root -g root -m 0644 \
    "$UNIT_SOURCE" \
    "$UNIT_DEST"

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# --------------------------------------------------
# Verify deployment
# --------------------------------------------------

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager
    exit 1
fi

if ! curl --fail --silent \
    --show-error \
    --max-time 5 \
    http://127.0.0.1:5000/ >/dev/null
then
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager
    exit 1
fi

log_success "Service 7 deployed successfully."

echo
echo "Portal:      http://127.0.0.1:5000/"
echo "App path:    $DEST_DIR"
echo "Python:      $VENV_DIR/bin/python"
echo "Flag path:   $FLAG_FILE"
echo "Systemd:     $SERVICE_NAME"
echo

systemctl --no-pager --full status "$SERVICE_NAME"
