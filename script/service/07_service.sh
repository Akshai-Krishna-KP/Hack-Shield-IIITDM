#!/usr/bin/env bash
# Deploy Service 7, preserving its intentionally forgeable auth cookie.
set -Eeuo pipefail
umask 027

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="$REPO_DIR/service7"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service7.service"
DEST_DIR="/opt/hackshield/services/service7"
VENV_DIR="$DEST_DIR/.venv"
SERVICE_NAME="hackshield-service7.service"
FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag7"
PORT=5007
BACKUP_ROOT="/opt/hackshield/backups/service7"

if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=SERVICE7_FLAG bash "$SCRIPT_PATH" "$@"
fi

for required in "$SOURCE_DIR/app.py" "$SOURCE_DIR/requirements.txt" "$UNIT_SOURCE"; do
    [[ -f "$required" ]] || { log_error "Required file is missing: $required"; exit 1; }
done
[[ -d "$SOURCE_DIR/templates" && -d "$SOURCE_DIR/static" ]] || {
    log_error "Service 7 templates or static assets are missing."; exit 1;
}
getent passwd user7 >/dev/null || { log_error "user7 does not exist; run script/setup.sh first."; exit 1; }
getent group hs-service-editors >/dev/null || { log_error "hs-service-editors does not exist; run script/setup.sh first."; exit 1; }

log_info "Installing Service 7 dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y acl curl python3 python3-pip python3-venv

if [[ -d "$DEST_DIR" ]]; then
    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    install -d -o root -g root -m 0700 "$BACKUP_DIR"
    cp -a "$DEST_DIR/." "$BACKUP_DIR/"
    log_info "Existing Service 7 deployment backed up to $BACKUP_DIR."
fi
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

install -d -o root -g hs-service-editors -m 2775 "$DEST_DIR"
tar --exclude='./.venv' -C "$SOURCE_DIR" -cf - . | tar -C "$DEST_DIR" -xf -
usermod -a -G hs-service-editors user7
chown -R root:hs-service-editors "$DEST_DIR"
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type d -exec chmod 2775 {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type f -exec chmod 0664 {} +

install -d -o root -g root -m 0711 "$FLAG_DIR"
setfacl -m u:user7:--x "$FLAG_DIR"
if [[ ! -f "$FLAG_FILE" ]]; then
    FLAG_VALUE="${SERVICE7_FLAG:-HS{service7_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
fi
chown user7:user7 "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    install -d -o user7 -g user7 -m 0750 "$VENV_DIR"
    runuser -u user7 -- python3 -m venv "$VENV_DIR"
fi
chown -R user7:user7 "$VENV_DIR"
runuser -u user7 -- "$VENV_DIR/bin/python" -m pip install --upgrade pip
runuser -u user7 -- "$VENV_DIR/bin/python" -m pip install -r "$DEST_DIR/requirements.txt"

install -o root -g root -m 0644 "$UNIT_SOURCE" /etc/systemd/system/"$SERVICE_NAME"
systemctl daemon-reload

log_success "Service 7 files deployed; startup is managed externally (port ${PORT})."
log_info "Protected flag: $FLAG_FILE; systemd unit: $SERVICE_NAME."
