#!/usr/bin/env bash
# Provision the Hack & Shield guest and deploy the services in this checkout.
set -Eeuo pipefail
umask 027

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SERVICE_DIR="$SCRIPT_DIR/service"
GAME_SERVER_DIR="$SCRIPT_DIR/game_server"
CONTROLLER_DIR="/usr/local/libexec/hackshield"
EDITORS_GROUP="hs-service-editors"

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

if [[ "$EUID" -ne 0 ]]; then
    exec sudo --preserve-env=SERVICE1_FLAG,SERVICE1_RAIHAN_PASSWORD,SERVICE2_FLAG,SERVICE2_ADMIN_PASSWORD,SERVICE2_RESEED,SERVICE3_FLAG,SERVICE4_SSRF_FLAG,SERVICE5_FLAG,SERVICE6_FLAG,SERVICE6_ADMIN_API_KEY,SERVICE7_FLAG,SERVICE8_FLAG,SERVICE8_JWT_SECRET,SERVICE9_FLAG,SERVICE9_RESEED,MONGODB_SERIES \
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

for number in 1 2 3 4 5 6 7 8 9; do
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
install -d -o root -g root -m 0711 /opt/flags

SUDOERS_FILE="/etc/sudoers.d/hackshield-player-restart"
if [[ -f "$SUDOERS_FILE" ]]; then
    SUDOERS_BACKUP="/opt/hackshield/backups/hackshield-player-restart.$(date +%Y%m%d-%H%M%S)"
    cp -a "$SUDOERS_FILE" "$SUDOERS_BACKUP"
    log_warn "Backed up existing player restart rules to $SUDOERS_BACKUP"
fi
cat > "$SUDOERS_FILE" <<'SUDOERS'
# Service restart permissions are generated for the six allocated services at boot.
SUDOERS
chown root:root "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"

mapfile -t SERVICE_SCRIPTS < <(find "$SERVICE_DIR" -maxdepth 1 -type f \
    -name '[0-9][0-9]_service.sh' -print | sort)
if [[ "${#SERVICE_SCRIPTS[@]}" -ne 9 ]]; then
    log_error "Expected nine numbered service deployment scripts in $SERVICE_DIR; found ${#SERVICE_SCRIPTS[@]}."
    exit 1
fi

log_info "Deploying services from $REPO_DIR..."
for service_script in "${SERVICE_SCRIPTS[@]}"; do
    log_info "Running $(basename -- "$service_script")"
    bash "$service_script"
    log_success "Finished $(basename -- "$service_script")"
done

log_info "Installing game-server registration and service allocation controller..."
install -d -o root -g root -m 0755 "$CONTROLLER_DIR"
for controller_file in load_boot_config.py register_boot.py manage_services.py service_mapping.py \
    rotate_flags.py gitea_push.sh; do
    [[ -f "$GAME_SERVER_DIR/$controller_file" ]] || {
        log_error "Required game-server controller file is missing: $GAME_SERVER_DIR/$controller_file"
        exit 1
    }
    install -o root -g root -m 0755 "$GAME_SERVER_DIR/$controller_file" "$CONTROLLER_DIR/$controller_file"
done
for unit in hackshield-config.service hackshield-register.service \
    hackshield-service-manager.service hackshield-stop-services.service \
    hackshield-flags.service; do
    [[ -f "$REPO_DIR/systemd/$unit" ]] || {
        log_error "Required controller unit is missing: $REPO_DIR/systemd/$unit"
        exit 1
    }
    install -o root -g root -m 0644 "$REPO_DIR/systemd/$unit" "/etc/systemd/system/$unit"
done
# Commit + push each service's code to the team's Gitea repo whenever it starts
for number in 1 2 3 4 5 6 7 8 9; do
    install -d -o root -g root -m 0755 "/etc/systemd/system/hackshield-service$number.service.d"
    printf '[Service]\n# "-" never fails the service, "+" runs as root (reads /run/hackshield/boot.env)\nExecStartPost=-+/bin/bash %s/gitea_push.sh %s\n' \
        "$CONTROLLER_DIR" "$number" > "/etc/systemd/system/hackshield-service$number.service.d/gitea.conf"
done
systemctl daemon-reload

# Prevent legacy enablement from starting unallocated services on boot.
for number in 1 2 3 4 5 6 7 8 9; do
    systemctl disable --now "hackshield-service$number.service" >/dev/null 2>&1 || true
done
systemctl disable --now mysql.service mongod.service >/dev/null 2>&1 || true
systemctl enable hackshield-config.service hackshield-register.service hackshield-service-manager.service hackshield-flags.service
systemctl start hackshield-flags.service

log_success "Hack & Shield service provisioning completed."
log_info "Log out and back in as player for the hs-service-editors group membership to take effect."
log_info "Configure QEMU hostfwd rules for every candidate app port: 9001, 4444, 1337, 7007, 8005, 8006, 5007, 5001, and 5002; forward 3306 for the Service 1 MySQL challenge. Do not forward 7108, 6006, or MongoDB port 27017."
log_info "At boot, the game server assigns six services and ports; only those six units are started."
