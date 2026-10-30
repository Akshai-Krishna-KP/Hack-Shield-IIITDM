#!/usr/bin/env bash
# Hack & Shield — Service 8 (JWT algorithm-confusion / unverified-claims lab)
# Expected repository layout:
#   script/service/08_service.sh
#   service8/app.py, requirements.txt, templates/, static/, challenge_fs/.env
#   systemd/hackshield-service8.service
set -Eeuo pipefail
umask 027

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DIR="$REPO_DIR/service8"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service8.service"

DEST_DIR="/opt/hackshield/services/service8"
VENV_DIR="$DEST_DIR/.venv"

FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag8"
LEGACY_FLAG_FILE="/opt/flag/flag8"

ENV_DIR="/etc/hackshield"
ENV_FILE="$ENV_DIR/service8.env"

SERVICE_NAME="hackshield-service8.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"
EDITORS_GROUP="hs-service-editors"
SERVICE_USER="user8"
PORT="5001"

if [[ "$EUID" -ne 0 ]]; then
    log_info "Re-running with sudo. For overrides, use sudo -E with SERVICE8_FLAG / SERVICE8_JWT_SECRET."
    exec sudo --preserve-env=SERVICE8_FLAG,SERVICE8_JWT_SECRET bash "$SCRIPT_PATH" "$@"
fi

# --------------------------------------------------
# STEP 1: Validate repository and VM prerequisites
# --------------------------------------------------

[[ -d "$SOURCE_DIR" ]] || { log_error "Missing service source: $SOURCE_DIR"; exit 1; }
[[ -f "$SOURCE_DIR/app.py" ]] || { log_error "Missing $SOURCE_DIR/app.py"; exit 1; }
[[ -f "$SOURCE_DIR/requirements.txt" ]] || { log_error "Missing $SOURCE_DIR/requirements.txt"; exit 1; }
[[ -f "$SOURCE_DIR/templates/index.html" ]] || { log_error "Missing $SOURCE_DIR/templates/index.html"; exit 1; }
[[ -f "$SOURCE_DIR/templates/admin.html" ]] || { log_error "Missing $SOURCE_DIR/templates/admin.html"; exit 1; }
[[ -f "$SOURCE_DIR/static/styles.css" ]] || { log_error "Missing $SOURCE_DIR/static/styles.css"; exit 1; }
[[ -f "$SOURCE_DIR/challenge_fs/.env" ]] || { log_error "Missing $SOURCE_DIR/challenge_fs/.env"; exit 1; }
[[ -f "$UNIT_SOURCE" ]] || { log_error "Missing systemd unit: $UNIT_SOURCE"; exit 1; }

getent passwd "$SERVICE_USER" >/dev/null || {
    log_error "$SERVICE_USER does not exist. Run the VM setup script first."
    exit 1
}
getent group "$EDITORS_GROUP" >/dev/null || {
    log_error "$EDITORS_GROUP does not exist. Run the VM setup script first."
    exit 1
}

# The committed challenge_fs/.env is participant-editable source, not the
# real secret store. Fail loudly if the unit doesn't load the protected
# override, so this service never silently runs on the hardcoded demo key.
grep -Fq "$VENV_DIR/bin/python" "$UNIT_SOURCE" || {
    log_error "Systemd unit ExecStart must use $VENV_DIR/bin/python."
    exit 1
}
grep -Fq "$DEST_DIR/app.py" "$UNIT_SOURCE" || {
    log_error "Systemd unit must launch $DEST_DIR/app.py."
    exit 1
}
grep -Fq "EnvironmentFile=$ENV_FILE" "$UNIT_SOURCE" || {
    log_error "Systemd unit must set EnvironmentFile=$ENV_FILE (this is how the real JWT_SECRET reaches the app instead of the hardcoded fallback in challenge_fs/.env)."
    exit 1
}
grep -Fq "EnvironmentFile=/run/hackshield/service8.env" "$UNIT_SOURCE" || {
    log_error "Systemd unit must load the game-server-assigned port from /run/hackshield/service8.env."
    exit 1
}

# --------------------------------------------------
# STEP 2: Install dependencies
# --------------------------------------------------

log_info "Installing Python runtime dependencies..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip acl curl

# --------------------------------------------------
# STEP 3: Back up the existing deployment (code only; no persistent DB)
# --------------------------------------------------

if [[ -d "$DEST_DIR" ]]; then
    BACKUP_ROOT="/opt/hackshield/backups/service8"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    install -d -o root -g root -m 0700 "$BACKUP_ROOT" "$BACKUP_DIR"
    cp -a "$DEST_DIR/." "$BACKUP_DIR/"
    log_success "Existing deployment backed up to $BACKUP_DIR"
fi

# --------------------------------------------------
# STEP 4: Deploy application code
# --------------------------------------------------

log_info "Deploying Service 8 (JWT portal) application..."
install -d -o root -g "$EDITORS_GROUP" -m 2775 "$DEST_DIR"

# Never copy a developer's local venv into the deployment.
tar --exclude='./.venv' -C "$SOURCE_DIR" -cf - . | tar -C "$DEST_DIR" -xf -

find "$DEST_DIR" -path "$VENV_DIR" -prune -o -exec chown root:"$EDITORS_GROUP" {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type d -exec chmod 2775 {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type f -exec chmod 0664 {} +
usermod -a -G "$EDITORS_GROUP" "$SERVICE_USER"

log_success "Application code deployed to $DEST_DIR"

# --------------------------------------------------
# STEP 5: Private virtual environment (owned by the service account only,
# so player cannot tamper with the installed dependencies post-deploy)
# --------------------------------------------------

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    if [[ -e "$VENV_DIR" ]]; then
        log_warn "$VENV_DIR exists but has no executable Python; recreating it."
        rm -rf -- "$VENV_DIR"
    fi
    install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 "$VENV_DIR"
    runuser -u "$SERVICE_USER" -- python3 -m venv "$VENV_DIR"
fi
chown -R "$SERVICE_USER:$SERVICE_USER" "$VENV_DIR"

log_info "Installing Flask/PyJWT dependencies..."
runuser -u "$SERVICE_USER" -- "$VENV_DIR/bin/python" -m pip install --upgrade pip
runuser -u "$SERVICE_USER" -- "$VENV_DIR/bin/python" -m pip install -r "$DEST_DIR/requirements.txt"

# --------------------------------------------------
# STEP 6: Protected secret override
#
# This is the real JWT_SECRET used at runtime. It overrides the hardcoded
# placeholder in the deployed (player-editable) challenge_fs/.env, exactly
# as Service 2's SHOEMART_SESSION_SECRET overrides its own defaults.
# --------------------------------------------------

install -d -o root -g root -m 0755 "$ENV_DIR"
if [[ ! -f "$ENV_FILE" ]]; then
    JWT_SECRET_VALUE="${SERVICE8_JWT_SECRET:-$(python3 -c 'import secrets; print(secrets.token_hex(32))')}"
    (umask 077; printf 'JWT_SECRET=%s\n' "$JWT_SECRET_VALUE" > "$ENV_FILE")
    log_success "Generated a per-VM JWT_SECRET at $ENV_FILE"
else
    log_warn "Existing secret preserved: $ENV_FILE"
fi
chown root:root "$ENV_FILE"
chmod 0600 "$ENV_FILE"

# --------------------------------------------------
# STEP 7: Protected flag
# --------------------------------------------------

install -d -o root -g root -m 0711 "$FLAG_DIR"
setfacl -m "u:${SERVICE_USER}:--x" "$FLAG_DIR"

if [[ ! -f "$FLAG_FILE" && -f "$LEGACY_FLAG_FILE" ]]; then
    mv -- "$LEGACY_FLAG_FILE" "$FLAG_FILE"
    log_info "Migrated the existing Service 8 flag to $FLAG_FILE."
fi

if [[ ! -f "$FLAG_FILE" ]]; then
    FLAG_VALUE="${SERVICE8_FLAG:-HS{service8_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
    log_success "Created protected flag at $FLAG_FILE"
else
    log_warn "Existing flag preserved: $FLAG_FILE"
fi
chown "$SERVICE_USER:$SERVICE_USER" "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

# --------------------------------------------------
# STEP 8: Install systemd unit
# --------------------------------------------------

install -o root -g root -m 0644 "$UNIT_SOURCE" "$UNIT_DEST"
systemctl daemon-reload
log_success "Service 8 deployed; the external service controller manages its unit."
printf '\nPortal:        http://127.0.0.1:%s/\nToken issue:   http://127.0.0.1:%s/api/token\nAdmin portal:  http://127.0.0.1:%s/api/admin/\nHealth check:  http://127.0.0.1:%s/health\nSecret env:    %s\nFlag file:     %s (value not displayed)\nSystemd unit:  %s\nUnit source:   %s\n\n' \
    "$PORT" "$PORT" "$PORT" "$PORT" "$ENV_FILE" "$FLAG_FILE" "$SERVICE_NAME" "$UNIT_SOURCE"
echo "The flag is generated per VM. Keep this intentionally vulnerable service on the isolated competition network."
