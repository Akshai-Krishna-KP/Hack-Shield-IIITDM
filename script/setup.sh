#!/usr/bin/env bash
# Provision the Hack & Shield guest and deploy the services in this checkout.
set -Eeuo pipefail
umask 027

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SERVICE_DIR="$SCRIPT_DIR/service"
EDITORS_GROUP="hs-service-editors"

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=SERVICE1_FLAG,SERVICE1_RAIHAN_PASSWORD,SERVICE2_FLAG,SERVICE2_ADMIN_PASSWORD,SERVICE2_RESEED,SERVICE3_FLAG,SERVICE4_SSRF_FLAG \
        bash "$SCRIPT_PATH" "$@"
fi

[[ -f "$REPO_DIR/README.md" && -d "$SERVICE_DIR" ]] || {
    log_error "Could not identify the repository root from $SCRIPT_PATH"
    exit 1
}

log_info "Installing base VM dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    acl apparmor-utils auditd build-essential curl git htop jq lsof sudo \
    openssh-server python3 python3-pip python3-venv rsync sqlite3 tree \
    ufw unzip wget

log_info "Creating the participant account and service identities..."
if ! getent passwd player >/dev/null; then
    useradd --create-home --shell /bin/bash player
    if [[ -t 0 ]]; then
        passwd player
    else
        log_warn "Created player with a locked password; set one with 'sudo passwd player' before enabling SSH login."
    fi
fi

if getent group sudo >/dev/null && id -nG player | tr ' ' '\n' | grep -qx sudo; then
    gpasswd -d player sudo
    log_warn "Removed player from the sudo group."
fi

if ! getent group "$EDITORS_GROUP" >/dev/null; then
    groupadd "$EDITORS_GROUP"
fi
usermod -aG "$EDITORS_GROUP" player

for number in 1 2 3 4; do
    account="user$number"
    if ! getent passwd "$account" >/dev/null; then
        useradd --system --user-group --no-create-home --home-dir /nonexistent \
            --shell /usr/sbin/nologin "$account"
    fi
done

log_info "Creating protected and persistent base directories..."
install -d -o root -g root -m 0755 \
    /opt/hackshield /opt/hackshield/services /opt/hackshield/protected \
    /var/lib/hackshield
install -d -o root -g root -m 0700 /opt/hackshield/backups
install -d -o root -g root -m 0750 /var/log/hackshield
install -d -o root -g root -m 0711 /opt/flags /opt/flag

SUDOERS_FILE="/etc/sudoers.d/hackshield-player-restart"
if [[ -f "$SUDOERS_FILE" ]]; then
    SUDOERS_BACKUP="/opt/hackshield/backups/hackshield-player-restart.$(date +%Y%m%d-%H%M%S)"
    cp -a "$SUDOERS_FILE" "$SUDOERS_BACKUP"
    log_warn "Backed up existing player restart rules to $SUDOERS_BACKUP"
fi
cat > "$SUDOERS_FILE" <<'SUDOERS'
player ALL=(root) NOPASSWD: /usr/bin/systemctl restart hackshield-service1.service, /usr/bin/systemctl restart hackshield-service2.service, /usr/bin/systemctl restart hackshield-service3.service, /usr/bin/systemctl restart hackshield-service4.service
SUDOERS
chown root:root "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"

mapfile -t SERVICE_SCRIPTS < <(find "$SERVICE_DIR" -maxdepth 1 -type f \
    -name '[0-9][0-9]_service.sh' -print | sort)
if [[ "${#SERVICE_SCRIPTS[@]}" -ne 4 ]]; then
    log_error "Expected four numbered service deployment scripts in $SERVICE_DIR; found ${#SERVICE_SCRIPTS[@]}."
    exit 1
fi

log_info "Deploying services from $REPO_DIR..."
for service_script in "${SERVICE_SCRIPTS[@]}"; do
    log_info "Running $(basename -- "$service_script")"
    bash "$service_script"
    log_success "Finished $(basename -- "$service_script")"
done

log_success "Hack & Shield service provisioning completed."
log_info "Log out and back in as player for the hs-service-editors group membership to take effect."
log_info "Configure QEMU hostfwd rules on the host for ports 9001, 3306, 4444, 1337, and 7007. Do not forward 7108."
log_info "Services 1-4 are deployed; challenge selection, scoring, monitoring, network isolation, and VM resets are not provisioned by this script."
