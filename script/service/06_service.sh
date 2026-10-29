#!/usr/bin/env bash
# Deploy Service 6 as a direct Flask service on port 8006.
set -Eeuo pipefail
umask 027

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="$REPO_DIR/service6"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service6.service"
DEST_DIR="/opt/hackshield/services/service6"
VENV_DIR="$DEST_DIR/.venv"
CHALLENGE_FS="$DEST_DIR/challenge_fs"
CONFIG_FILE="$CHALLENGE_FS/.env"
FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag6"
SERVICE_NAME="hackshield-service6.service"
PORT=8006
LEGACY_NGINX_SITE="/etc/nginx/sites-available/hackshield-service6"
LEGACY_NGINX_LINK="/etc/nginx/sites-enabled/hackshield-service6"

if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=SERVICE6_FLAG,SERVICE6_ADMIN_API_KEY bash "$SCRIPT_PATH" "$@"
fi

for required in "$SOURCE_DIR/app.py" "$SOURCE_DIR/requirements.txt" \
    "$SOURCE_DIR/challenge_fs/.env" "$UNIT_SOURCE"; do
    [[ -f "$required" ]] || { log_error "Required file is missing: $required"; exit 1; }
done
[[ -d "$SOURCE_DIR/templates" && -d "$SOURCE_DIR/static" && -d "$SOURCE_DIR/challenge_fs/public" ]] || {
    log_error "Service 6 templates, static assets, or public documents are missing."; exit 1;
}
getent passwd user6 >/dev/null || { log_error "user6 does not exist; run script/setup.sh first."; exit 1; }
getent group hs-service-editors >/dev/null || { log_error "hs-service-editors does not exist; run script/setup.sh first."; exit 1; }

log_info "Installing Service 6 dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y acl python3 python3-pip python3-venv

systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Remove only the Service 6 proxy from prior deployments so it releases port 8006.
if [[ -e "$LEGACY_NGINX_SITE" || -L "$LEGACY_NGINX_SITE" || \
      -e "$LEGACY_NGINX_LINK" || -L "$LEGACY_NGINX_LINK" ]]; then
    rm -f -- "$LEGACY_NGINX_LINK" "$LEGACY_NGINX_SITE"
    if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
        nginx -t
        systemctl reload nginx
    fi
fi

install -d -o root -g hs-service-editors -m 2775 "$DEST_DIR"
tar --exclude='./.venv' -C "$SOURCE_DIR" -cf - . | tar -C "$DEST_DIR" -xf -
usermod -a -G hs-service-editors user6
chown -R root:hs-service-editors "$DEST_DIR"
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type d -exec chmod 2775 {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type f -exec chmod 0664 {} +

# Keep the intentionally traversable .env outside the participant-editable tree.
install -d -o root -g user6 -m 0750 "$CHALLENGE_FS" "$CHALLENGE_FS/public"
chown -R root:user6 "$CHALLENGE_FS"
find "$CHALLENGE_FS" -type d -exec chmod 0750 {} +
find "$CHALLENGE_FS/public" -type f -exec chmod 0440 {} +
chmod 0640 "$CONFIG_FILE"

if ! grep -q '^ADMIN_API_KEY=' "$CONFIG_FILE" || grep -q 'HNS-DEMO-ADMIN-KEY' "$CONFIG_FILE"; then
    ADMIN_API_KEY="${SERVICE6_ADMIN_API_KEY:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')}"
    printf 'APP_NAME=Internal File API\nADMIN_API_KEY=%s\nDEBUG=False\n' "$ADMIN_API_KEY" > "$CONFIG_FILE"
fi
chown root:user6 "$CONFIG_FILE"
chmod 0640 "$CONFIG_FILE"

install -d -o root -g root -m 0711 "$FLAG_DIR"
setfacl -m "u:user6:--x" "$FLAG_DIR"
if [[ ! -f "$FLAG_FILE" ]]; then
    FLAG_VALUE="${SERVICE6_FLAG:-HS{service6_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
fi
chown user6:user6 "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    install -d -o user6 -g user6 -m 0750 "$VENV_DIR"
    runuser -u user6 -- python3 -m venv "$VENV_DIR"
fi
chown -R user6:user6 "$VENV_DIR"
runuser -u user6 -- "$VENV_DIR/bin/python" -m pip install --upgrade pip
runuser -u user6 -- "$VENV_DIR/bin/python" -m pip install -r "$DEST_DIR/requirements.txt"

install -o root -g root -m 0644 "$UNIT_SOURCE" /etc/systemd/system/"$SERVICE_NAME"
systemctl daemon-reload

log_success "Service 6 files deployed; external service management will start Flask on port ${PORT}."
log_info "Protected flag: $FLAG_FILE; admin key is stored in $CONFIG_FILE."
