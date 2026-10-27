#!/usr/bin/env bash

set -Eeuo pipefail

# Resolve paths relative to the repository.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DIR="$REPO_DIR/service1"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service1.service"
DEST_DIR="/opt/hackshield/services/service1"
SERVICE_NAME="hackshield-service1.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"

# Logging
log_info()    { echo "[INFO] $*"; }
log_success() { echo "[SUCCESS] $*"; }
log_error()   { echo "[ERROR] $*" >&2; }

# Require root so commands and file permissions are consistent.
if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=PATH bash "$0" "$@"
fi

# Validate repository files.
[[ -d "$SOURCE_DIR" ]] || {
    log_error "Service source not found: $SOURCE_DIR"
    exit 1
}

[[ -f "$SOURCE_DIR/server.py" ]] || {
    log_error "Missing server.py in $SOURCE_DIR"
    exit 1
}

[[ -f "$UNIT_SOURCE" ]] || {
    log_error "Systemd unit not found: $UNIT_SOURCE"
    exit 1
}

# Verify the expected VM setup exists.
getent passwd user1 >/dev/null || {
    log_error "Account user1 does not exist. Run the VM setup first."
    exit 1
}

getent group hs-service-editors >/dev/null || {
    log_error "Group hs-service-editors does not exist. Run the VM setup first."
    exit 1
}

log_info "Installing required packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-pymysql

# Back up the currently deployed service before replacing it.
if [[ -d "$DEST_DIR" ]]; then
    BACKUP_ROOT="/opt/hackshield/backups/service1"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"

    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    install -d -o root -g root -m 0700 "$BACKUP_DIR"

    cp -a "$DEST_DIR/." "$BACKUP_DIR/"
    log_success "Backup created at $BACKUP_DIR"
fi

# Stop the service during deployment, if it already exists.
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Create destination and copy the complete website.
install -d -o root -g hs-service-editors -m 2775 "$DEST_DIR"
cp -a "$SOURCE_DIR/." "$DEST_DIR/"

# Allow the intended editor group to modify service files.
# The protected flag directory and systemd unit are NOT changed here.
chown -R root:hs-service-editors "$DEST_DIR"
find "$DEST_DIR" -type d -exec chmod 2775 {} +
find "$DEST_DIR" -type f -exec chmod 0664 {} +

log_success "Copied service files to $DEST_DIR"

# Install the systemd unit from the repository.
install -o root -g root -m 0644 "$UNIT_SOURCE" "$UNIT_DEST"

# Reload systemd and launch the service.
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# Fail deployment if the service did not start.
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager || true
    log_error "Service failed to start."
    exit 1
fi

systemctl --no-pager --full status "$SERVICE_NAME"

log_success "Service 1 deployment completed."
echo "Portal URL: http://127.0.0.1:9001/"
