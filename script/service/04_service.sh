#!/usr/bin/env bash
# Hack & Shield — deploy the public WikiLink SSRF app and its internal
# Fleet Inventory target from the consolidated Service 4 directory.
set -Eeuo pipefail
umask 027

log_info()    { printf '\033[0;34m[INFO]\033[0m %s\n' "$*"; }
log_success() { printf '\033[0;32m[SUCCESS]\033[0m %s\n' "$*"; }
log_warn()    { printf '\033[0;33m[WARN]\033[0m %s\n' "$*"; }
log_error()   { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SERVICE4_SOURCE="$REPO_DIR/service4"
SERVICE4_UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service4.service"

SERVICE4_DEST="/opt/hackshield/services/service4"
LEGACY_SERVICE5_DEST="/opt/hackshield/services/service5"
LEGACY_SERVICE5_NAME="hackshield-service5.service"
LEGACY_SERVICE5_UNIT_DEST="/etc/systemd/system/$LEGACY_SERVICE5_NAME"
RETIRED_SERVICE5_FLAG_FILE="/opt/flags/flag_ssrf_service5"
FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag4"
LEGACY_FLAG_FILE="/opt/flag/flag4"

SERVICE4_NAME="hackshield-service4.service"
SERVICE4_UNIT_DEST="/etc/systemd/system/$SERVICE4_NAME"

# Re-run as root if necessary.
if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$SCRIPT_PATH" "$@"
fi

# -----------------------------
# STEP 1: Validate source files
# -----------------------------
[[ -f "$SERVICE4_SOURCE/app.py" ]] || {
    log_error "Missing $SERVICE4_SOURCE/app.py"
    exit 1
}
[[ -f "$SERVICE4_SOURCE/requirements.txt" ]] || {
    log_error "Missing $SERVICE4_SOURCE/requirements.txt"
    exit 1
}
[[ -f "$SERVICE4_SOURCE/internal_api.py" ]] || {
    log_error "Missing $SERVICE4_SOURCE/internal_api.py"
    exit 1
}
[[ -f "$SERVICE4_UNIT_SOURCE" ]] || {
    log_error "Missing systemd unit: $SERVICE4_UNIT_SOURCE"
    exit 1
}
getent passwd user4 >/dev/null || {
    log_error "user4 does not exist. Run the VM setup first."
    exit 1
}
getent group hs-service-editors >/dev/null || {
    log_error "hs-service-editors does not exist. Run the VM setup first."
    exit 1
}

# -----------------------------
# STEP 2: Install prerequisites
# -----------------------------
log_info "Installing Python, venv and ACL prerequisites..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip acl curl

# -----------------------------
# STEP 3: Back up current deploys
# -----------------------------
BACKUP_ROOT="/opt/hackshield/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
backup_dir() {
    local src="$1" name="$2"
    if [[ -d "$src" ]]; then
        install -d -o root -g root -m 0700 "$BACKUP_ROOT/$name/$STAMP"
        cp -a "$src/." "$BACKUP_ROOT/$name/$STAMP/"
        log_success "Backed up $src to $BACKUP_ROOT/$name/$STAMP"
    fi
}
backup_dir "$SERVICE4_DEST" "service4"
backup_dir "$LEGACY_SERVICE5_DEST" "legacy-service5"
if [[ -f "$LEGACY_SERVICE5_UNIT_DEST" ]]; then
    LEGACY_UNIT_BACKUP="/opt/hackshield/backups/legacy-service5-unit/$STAMP"
    install -d -o root -g root -m 0700 "$LEGACY_UNIT_BACKUP"
    cp -a "$LEGACY_SERVICE5_UNIT_DEST" "$LEGACY_UNIT_BACKUP/"
fi

# -----------------------------
# STEP 4: Stop units before copy
# -----------------------------
systemctl stop "$SERVICE4_NAME" 2>/dev/null || true
systemctl disable --now "$LEGACY_SERVICE5_NAME" 2>/dev/null || true

# -----------------------------
# STEP 5: Deploy Service 4
# -----------------------------
log_info "Deploying public WikiLink portal to $SERVICE4_DEST..."
install -d -o root -g hs-service-editors -m 2775 "$SERVICE4_DEST"
cp -a "$SERVICE4_SOURCE/." "$SERVICE4_DEST/"
chown -R root:hs-service-editors "$SERVICE4_DEST"
find "$SERVICE4_DEST" -type d -exec chmod 2775 {} +
find "$SERVICE4_DEST" -type f -exec chmod 0664 {} +

if [[ ! -x "$SERVICE4_DEST/.venv/bin/python" ]]; then
    log_info "Creating Service 4 virtual environment..."
    python3 -m venv "$SERVICE4_DEST/.venv"
fi
"$SERVICE4_DEST/.venv/bin/python" -m pip install --upgrade pip
"$SERVICE4_DEST/.venv/bin/python" -m pip install -r "$SERVICE4_DEST/requirements.txt"

# -----------------------------
# STEP 6: Retire the old separate Service 5 deployment
# -----------------------------
if [[ -d "$LEGACY_SERVICE5_DEST" ]]; then
    log_info "Removing the retired standalone Service 5 deployment..."
    rm -rf -- "$LEGACY_SERVICE5_DEST"
fi
rm -f -- "$LEGACY_SERVICE5_UNIT_DEST"
rm -f -- "$RETIRED_SERVICE5_FLAG_FILE"

# -----------------------------
# STEP 7: Create protected flag
# -----------------------------
log_info "Preparing the synthetic SSRF challenge flag..."
install -d -o root -g root -m 0711 "$FLAG_DIR"
# The service account can traverse the flag directory but cannot list it.
setfacl -m u:user4:--x "$FLAG_DIR"

if [[ ! -f "$FLAG_FILE" && -f "$LEGACY_FLAG_FILE" ]]; then
    mv -- "$LEGACY_FLAG_FILE" "$FLAG_FILE"
    log_info "Migrated the existing Service 4 flag to $FLAG_FILE."
elif [[ -f "$FLAG_FILE" && -f "$LEGACY_FLAG_FILE" ]]; then
    rm -f -- "$LEGACY_FLAG_FILE"
    log_warn "Removed the obsolete Service 4 flag from $LEGACY_FLAG_FILE; preserving $FLAG_FILE."
fi
if [[ ! -f "$FLAG_FILE" ]]; then
    FLAG_VALUE="${SERVICE4_SSRF_FLAG:-HS{service4_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
fi
chown user4:user4 "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"
log_success "SSRF flag installed at $FLAG_FILE (owner user4, mode 0400)."

# -----------------------------
# STEP 8: Install systemd units
# -----------------------------
log_info "Installing systemd units..."
install -o root -g root -m 0644 "$SERVICE4_UNIT_SOURCE" "$SERVICE4_UNIT_DEST"

# Ensure the combined unit launches from the Service 4 virtual environment.
if ! grep -Fq "$SERVICE4_DEST/.venv/bin/python" "$SERVICE4_UNIT_DEST"; then
    log_warn "Service 4 unit does not reference $SERVICE4_DEST/.venv/bin/python; review its ExecStart."
fi
systemctl daemon-reload

log_success "Service 4 deployed; startup is managed externally."
echo
echo "Public portal:       http://127.0.0.1:7007/"
echo "Preview endpoint:    http://127.0.0.1:7007/api/preview"
echo "Internal API:        http://127.0.0.1:7108 (loopback only)"
echo "Flag file:           $FLAG_FILE"
echo "Service 4 unit:      $SERVICE4_NAME"
echo
echo "IMPORTANT: Do not add port 7108 to QEMU hostfwd rules."
echo "Both processes run under the single Service 4 systemd unit."
