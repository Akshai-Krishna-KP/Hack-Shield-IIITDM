
#!/usr/bin/env bash
set -Eeuo pipefail

# Resolve paths from the repository, not the current working directory.
SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DIR="$REPO_DIR/service1"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service1.service"

DEST_DIR="/opt/hackshield/services/service1"
PROTECTED_DIR="/opt/hackshield/protected"
SQL_FILE="$PROTECTED_DIR/service1_seed.sql"
FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag1"

SERVICE_NAME="hackshield-service1.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"

log_info()    { echo "[INFO] $*"; }
log_success() { echo "[SUCCESS] $*"; }
log_warn()    { echo "[WARN] $*"; }
log_error()   { echo "[ERROR] $*" >&2; }

# Re-run as root if necessary.
if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$SCRIPT_PATH" "$@"
fi

# --------------------------------------------------
# STEP 1: Validate repository and VM prerequisites
# --------------------------------------------------

[[ -d "$SOURCE_DIR" ]] || {
    log_error "Service directory missing: $SOURCE_DIR"
    exit 1
}

[[ -f "$SOURCE_DIR/server.py" ]] || {
    log_error "server.py not found."
    exit 1
}

[[ -f "$UNIT_SOURCE" ]] || {
    log_error "Systemd unit missing: $UNIT_SOURCE"
    exit 1
}

getent passwd user1 >/dev/null || {
    log_error "user1 does not exist. Run the VM setup first."
    exit 1
}

getent group hs-service-editors >/dev/null || {
    log_error "hs-service-editors does not exist. Run the VM setup first."
    exit 1
}

# --------------------------------------------------
# STEP 2: Install dependencies
# --------------------------------------------------

log_info "Installing MySQL, Python and ACL dependencies..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    mysql-server \
    python3 \
    python3-pymysql \
    python3-venv \
    acl

systemctl enable --now mysql

# --------------------------------------------------
# STEP 3: Generate protected SQL seed file
# --------------------------------------------------

log_info "Creating the Service 1 database seed file..."

# Install the protected SQL seed file from the repository.
install -d -o root -g root -m 0755 "$PROTECTED_DIR"

install -o root -g root -m 0644 \
    "$REPO_DIR/sql/service1_seed.sql" \
    "$SQL_FILE"

# Apply schema and seed data.
mysql < "$SQL_FILE"

log_success "Database schema and seed data installed."


# --------------------------------------------------
# STEP 4: Configure the intentional MySQL exposure
# --------------------------------------------------

MYSQL_CONFIG="/etc/mysql/mysql.conf.d/mysqld.cnf"

if [[ ! -f "$MYSQL_CONFIG" ]]; then
    log_error "MySQL configuration not found: $MYSQL_CONFIG"
    exit 1
fi

# Back up the configuration before changing it.
cp -a "$MYSQL_CONFIG" \
    "$MYSQL_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"

if grep -Eq '^[[:space:]]*bind-address[[:space:]]*=' "$MYSQL_CONFIG"; then
    sed -i -E \
        's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' \
        "$MYSQL_CONFIG"
else
    sed -i '/^\[mysqld\]/a bind-address = 0.0.0.0' "$MYSQL_CONFIG"
fi

systemctl restart mysql

log_success "MySQL configured to listen on all interfaces."

# --------------------------------------------------
# STEP 5: Create the protected flag
# --------------------------------------------------

log_info "Creating the Service 1 flag..."

install -d -o root -g root -m 0711 "$FLAG_DIR"

# Allow user1 to traverse the flag directory without listing it.
setfacl -m u:user1:--x "$FLAG_DIR"

# Set SERVICE1_FLAG before running the script to use a different flag.
FLAG_VALUE="${SERVICE1_FLAG:-}"

if [[ -z "$FLAG_VALUE" ]]; then
    FLAG_VALUE='HS{bind_address_0_0_0_0_is_not_a_firewall}'
fi

printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
chown user1:user1 "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

log_success "Flag created at $FLAG_FILE"

# --------------------------------------------------
# STEP 6: Back up the existing website deployment
# --------------------------------------------------

if [[ -d "$DEST_DIR" ]]; then
    BACKUP_ROOT="/opt/hackshield/backups/service1"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"

    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    install -d -o root -g root -m 0700 "$BACKUP_DIR"

    cp -a "$DEST_DIR/." "$BACKUP_DIR/"
    log_success "Existing service backed up to $BACKUP_DIR"
fi

# --------------------------------------------------
# STEP 7: Deploy the website
# --------------------------------------------------

systemctl stop "$SERVICE_NAME" 2>/dev/null || true

install -d -o root -g hs-service-editors -m 2775 "$DEST_DIR"
cp -a "$SOURCE_DIR/." "$DEST_DIR/"

chown -R root:hs-service-editors "$DEST_DIR"
find "$DEST_DIR" -type d -exec chmod 2775 {} +
find "$DEST_DIR" -type f -exec chmod 0664 {} +

log_success "Website deployed to $DEST_DIR"

# --------------------------------------------------
# STEP 8: Install systemd service
# --------------------------------------------------

install -o root -g root -m 0644 "$UNIT_SOURCE" "$UNIT_DEST"

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# --------------------------------------------------
# STEP 9: Verify deployment
# --------------------------------------------------

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 60 --no-pager || true
    log_error "Service failed to start."
    exit 1
fi

log_success "Service 1 deployment completed successfully."

echo
echo "Portal:       http://127.0.0.1:9001/"
echo "MySQL:        port 3306"
echo "Database:     employees"
echo "Table:        staff"
echo "Systemd unit: $SERVICE_NAME"

systemctl --no-pager --full status "$SERVICE_NAME"
