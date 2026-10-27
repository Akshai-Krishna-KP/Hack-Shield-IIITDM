#!/usr/bin/env bash
# Hack & Shield — Service 3 deployment (Name Spookifier / Mako SSTI lab)
# Repository layout expected:
#   script/service/03_service.sh
#   service3/run.py
#   service3/application/...
#   systemd/hackshield-service3.service
#
# Copies the application into /opt/hackshield/services/service3 and installs
# the separate systemd unit into /etc/systemd/system. The venv is created at
# /opt/hackshield/services/service3/.venv and is deliberately excluded from
# application permission changes so its executable bits remain intact.

set -Eeuo pipefail
umask 027

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DIR="$REPO_DIR/service3"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service3.service"
DEST_DIR="/opt/hackshield/services/service3"
SERVICE_NAME="hackshield-service3.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"
FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag3"
VENV_DIR="$DEST_DIR/.venv"

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$SCRIPT_PATH" "$@"
fi

# Validate repository inputs before making system changes.
[[ -d "$SOURCE_DIR" ]] || { log_error "Missing service source: $SOURCE_DIR"; exit 1; }
[[ -f "$SOURCE_DIR/run.py" ]] || { log_error "Missing $SOURCE_DIR/run.py"; exit 1; }
[[ -f "$SOURCE_DIR/application/main.py" ]] || { log_error "Missing $SOURCE_DIR/application/main.py"; exit 1; }
[[ -f "$SOURCE_DIR/application/blueprints/routes.py" ]] || { log_error "Missing $SOURCE_DIR/application/blueprints/routes.py"; exit 1; }
[[ -f "$SOURCE_DIR/application/util.py" ]] || { log_error "Missing $SOURCE_DIR/application/util.py"; exit 1; }
[[ -f "$SOURCE_DIR/application/templates/index.html" ]] || { log_error "Missing $SOURCE_DIR/application/templates/index.html"; exit 1; }
[[ -f "$UNIT_SOURCE" ]] || { log_error "Missing systemd unit: $UNIT_SOURCE"; exit 1; }

getent passwd user3 >/dev/null || {
    log_error 'Account user3 is missing. Run the VM setup script first.'
    exit 1
}
getent group hs-service-editors >/dev/null || {
    log_error 'Group hs-service-editors is missing. Run the VM setup script first.'
    exit 1
}

log_info 'Installing Python and build dependencies...'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip build-essential acl curl

# Back up the existing deployed application before replacing its source.
if [[ -d "$DEST_DIR" ]]; then
    BACKUP_ROOT='/opt/hackshield/backups/service3'
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    install -d -o root -g root -m 0700 "$BACKUP_ROOT" "$BACKUP_DIR"
    cp -a "$DEST_DIR/." "$BACKUP_DIR/"
    log_success "Existing deployment backed up to $BACKUP_DIR"
fi

systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Create the deployment directory and copy repository application files.
install -d -o root -g hs-service-editors -m 2775 "$DEST_DIR"
# Do not copy a developer's local virtual environment from the repository.
tar --exclude='./.venv' -C "$SOURCE_DIR" -cf - . | tar -C "$DEST_DIR" -xf -

# Make application code editable by hs-service-editors, but leave .venv out
# of recursive chmod/chown operations (changing its executable bits breaks it).
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -exec chown root:hs-service-editors {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type d -exec chmod 2775 {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type f -exec chmod 0664 {} +

# Create/reuse the virtual environment at the exact path used by systemd.
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    if [[ -e "$VENV_DIR" ]]; then
        log_warn "$VENV_DIR exists but has no executable Python; recreating it."
        rm -rf -- "$VENV_DIR"
    fi
    install -d -o user3 -g user3 -m 0750 "$VENV_DIR"
    runuser -u user3 -- python3 -m venv "$VENV_DIR"
fi
chown -R user3:user3 "$VENV_DIR"

log_info 'Installing Flask and Mako into the service virtual environment...'
runuser -u user3 -- "$VENV_DIR/bin/python" -m pip install --upgrade pip
runuser -u user3 -- "$VENV_DIR/bin/python" -m pip install \
    'Flask>=3.0,<4.0' 'Mako>=1.2,<2.0'

# Install/update the protected challenge flag BEFORE starting the service.
install -d -o root -g root -m 0711 "$FLAG_DIR"
setfacl -m u:user3:--x "$FLAG_DIR"
if [[ ! -f "$FLAG_FILE" ]]; then
    FLAG_VALUE="${SERVICE3_FLAG:-HS{service3_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
fi
chown user3:user3 "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

# Install the separate, root-owned systemd unit from the repository.
install -o root -g root -m 0644 "$UNIT_SOURCE" "$UNIT_DEST"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
    log_error "$SERVICE_NAME did not start. Check the unit's WorkingDirectory and ExecStart."
    exit 1
fi
if ! curl --fail --silent --show-error --max-time 5 -G \
    http://127.0.0.1:1337/ --data-urlencode 'text=hello' >/dev/null; then
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
    log_error 'Service 3 route/template check failed on port 1337.'
    exit 1
fi

log_success 'Service 3 deployed successfully.'
printf '\nURL:       http://127.0.0.1:1337/\n'
printf 'App path:  %s\n' "$DEST_DIR"
printf 'Python:    %s/bin/python\n' "$VENV_DIR"
printf 'Unit:      %s\n' "$UNIT_DEST"
printf 'Flag path: %s (flag value not displayed)\n\n' "$FLAG_FILE"
systemctl --no-pager --full status "$SERVICE_NAME"
