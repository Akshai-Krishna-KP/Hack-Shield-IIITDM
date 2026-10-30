#!/usr/bin/env bash
# Hack & Shield — Service 9 (Blockstar Build Vault, NoSQL operator-injection lab)
# Expected repository layout:
#   script/service/09_service.sh
#   service9/app.py, requirements.txt, templates/index.html, static/styles.css
#   nodejs/service9_seed.js       (mongosh seed script for blockstar_internal)
#   systemd/hackshield-service9.service
set -Eeuo pipefail
umask 027

log_info()    { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[SUCCESS] %s\n' "$*"; }
log_warn()    { printf '[WARN] %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SOURCE_DIR="$REPO_DIR/service9"
UNIT_SOURCE="$REPO_DIR/systemd/hackshield-service9.service"
SEED_SOURCE="$REPO_DIR/nodejs/service9_seed.js"
FLAG_SYNC_SOURCE="$SCRIPT_DIR/09_sync_flag.sh"
FLAG_SYNC_SERVICE_SOURCE="$REPO_DIR/systemd/hackshield-service9-flag-sync.service"
FLAG_SYNC_PATH_SOURCE="$REPO_DIR/systemd/hackshield-service9-flag-sync.path"

DEST_DIR="/opt/hackshield/services/service9"
VENV_DIR="$DEST_DIR/.venv"
PROTECTED_DIR="/opt/hackshield/protected"
SEED_FILE="$PROTECTED_DIR/service9_seed.js"

FLAG_DIR="/opt/flags"
FLAG_FILE="$FLAG_DIR/flag9"
LEGACY_FLAG_FILE="/opt/flag/flag9"

ENV_DIR="/etc/hackshield"
ENV_FILE="$ENV_DIR/service9.env"

SERVICE_NAME="hackshield-service9.service"
UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"
EDITORS_GROUP="hs-service-editors"
SERVICE_USER="user9"
PORT="5002"

MONGO_SERIES="${MONGODB_SERIES:-8.0}"
MONGO_CONF="/etc/mongod.conf"
MONGO_DB_NAME="blockstar_internal"
MONGO_APP_USER="hs_service9"

if [[ "$EUID" -ne 0 ]]; then
    log_info "Re-running with sudo. For overrides, export SERVICE9_FLAG / SERVICE9_RESEED first."
    exec sudo --preserve-env=SERVICE9_FLAG,SERVICE9_RESEED,MONGODB_SERIES bash "$SCRIPT_PATH" "$@"
fi

# --------------------------------------------------
# STEP 1: Validate repository and VM prerequisites
# --------------------------------------------------

[[ -d "$SOURCE_DIR" ]] || { log_error "Missing service source: $SOURCE_DIR"; exit 1; }
[[ -f "$SOURCE_DIR/app.py" ]] || { log_error "Missing $SOURCE_DIR/app.py"; exit 1; }
[[ -f "$SOURCE_DIR/requirements.txt" ]] || { log_error "Missing $SOURCE_DIR/requirements.txt"; exit 1; }
[[ -f "$SOURCE_DIR/templates/index.html" ]] || { log_error "Missing $SOURCE_DIR/templates/index.html"; exit 1; }
[[ -f "$SOURCE_DIR/static/styles.css" ]] || { log_error "Missing $SOURCE_DIR/static/styles.css"; exit 1; }
[[ -f "$SEED_SOURCE" ]] || { log_error "Missing MongoDB seed file: $SEED_SOURCE"; exit 1; }
[[ -f "$UNIT_SOURCE" ]] || { log_error "Missing systemd unit: $UNIT_SOURCE"; exit 1; }
[[ -f "$FLAG_SYNC_SOURCE" ]] || { log_error "Missing flag sync script: $FLAG_SYNC_SOURCE"; exit 1; }
[[ -f "$FLAG_SYNC_SERVICE_SOURCE" ]] || { log_error "Missing flag sync unit: $FLAG_SYNC_SERVICE_SOURCE"; exit 1; }
[[ -f "$FLAG_SYNC_PATH_SOURCE" ]] || { log_error "Missing flag watcher unit: $FLAG_SYNC_PATH_SOURCE"; exit 1; }

getent passwd "$SERVICE_USER" >/dev/null || {
    log_error "$SERVICE_USER does not exist. Run the VM setup script first."
    exit 1
}
getent group "$EDITORS_GROUP" >/dev/null || {
    log_error "$EDITORS_GROUP does not exist. Run the VM setup script first."
    exit 1
}

# The unit must load the protected env file (real MONGO_URI) and the venv.
grep -Fq "$VENV_DIR/bin/python" "$UNIT_SOURCE" || {
    log_error "Systemd unit ExecStart must use $VENV_DIR/bin/python."
    exit 1
}
grep -Fq "$DEST_DIR/app.py" "$UNIT_SOURCE" || {
    log_error "Systemd unit must launch $DEST_DIR/app.py."
    exit 1
}
grep -Fq "EnvironmentFile=$ENV_FILE" "$UNIT_SOURCE" || {
    log_error "Systemd unit must set EnvironmentFile=$ENV_FILE (this is how the authenticated MONGO_URI reaches the app)."
    exit 1
}
grep -Fq "EnvironmentFile=/run/hackshield/service9.env" "$UNIT_SOURCE" || {
    log_error "Systemd unit must load the game-server-assigned port from /run/hackshield/service9.env."
    exit 1
}

# --------------------------------------------------
# STEP 2: Install dependencies (Python + MongoDB + mongosh)
# --------------------------------------------------

log_info "Installing Python runtime dependencies..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip acl curl gnupg ca-certificates

if ! command -v mongod >/dev/null 2>&1 || ! command -v mongosh >/dev/null 2>&1; then
    # Ubuntu 24.04 does not ship MongoDB; use the official MongoDB apt repo.
    # Note: MongoDB 5.0+ requires a CPU with AVX (use "-cpu host" under KVM).
    log_info "Adding the MongoDB $MONGO_SERIES apt repository..."
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_SERIES}.asc" \
        | gpg --dearmor --yes -o "/usr/share/keyrings/mongodb-server-${MONGO_SERIES}.gpg"
    chmod 0644 "/usr/share/keyrings/mongodb-server-${MONGO_SERIES}.gpg"
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGO_SERIES}.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/${MONGO_SERIES} multiverse" \
        > "/etc/apt/sources.list.d/mongodb-org-${MONGO_SERIES}.list"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org-server mongodb-mongosh
else
    log_warn "mongod and mongosh already installed; skipping MongoDB repository setup."
fi

if [[ ! -f "$MONGO_CONF" ]]; then
    log_error "MongoDB configuration not found: $MONGO_CONF"
    exit 1
fi
if grep -Eq '^[[:space:]]*(bindIpAll:[[:space:]]*true|bindIp:.*(0\.0\.0\.0|::))' "$MONGO_CONF"; then
    log_error "MongoDB in $MONGO_CONF is configured to listen on a non-loopback interface. Restrict bindIp to loopback before deploying Service 9."
    exit 1
fi

# --------------------------------------------------
# STEP 3: Back up the existing deployment (code only)
# --------------------------------------------------

if [[ -d "$DEST_DIR" ]]; then
    BACKUP_ROOT="/opt/hackshield/backups/service9"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    install -d -o root -g root -m 0700 "$BACKUP_ROOT" "$BACKUP_DIR"
    cp -a "$DEST_DIR/." "$BACKUP_DIR/"
    log_success "Existing deployment backed up to $BACKUP_DIR"
fi

# --------------------------------------------------
# STEP 4: Deploy application code
# --------------------------------------------------

log_info "Deploying Service 9 (Build Vault) application..."
install -d -o root -g "$EDITORS_GROUP" -m 2775 "$DEST_DIR"

# Never copy a developer's local venv into the deployment.
tar --exclude='./.venv' -C "$SOURCE_DIR" -cf - . | tar -C "$DEST_DIR" -xf -

find "$DEST_DIR" -path "$VENV_DIR" -prune -o -exec chown root:"$EDITORS_GROUP" {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type d -exec chmod 2775 {} +
find "$DEST_DIR" -path "$VENV_DIR" -prune -o -type f -exec chmod 0664 {} +

log_success "Application code deployed to $DEST_DIR"

# --------------------------------------------------
# STEP 5: Private virtual environment (owned by the service account only)
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

log_info "Installing Flask/PyMongo dependencies..."
runuser -u "$SERVICE_USER" -- "$VENV_DIR/bin/python" -m pip install --upgrade pip
runuser -u "$SERVICE_USER" -- "$VENV_DIR/bin/python" -m pip install -r "$DEST_DIR/requirements.txt"

# --------------------------------------------------
# STEP 6: Start MongoDB and create the application credential
# --------------------------------------------------

systemctl start mongod

log_info "Waiting for MongoDB..."
MONGO_UP=0
for _ in $(seq 1 30); do
    if mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; then
        MONGO_UP=1
        break
    fi
    sleep 1
done
[[ "$MONGO_UP" -eq 1 ]] || { log_error "MongoDB did not become ready on 127.0.0.1:27017."; exit 1; }

install -d -o root -g root -m 0755 "$ENV_DIR"
if [[ ! -f "$ENV_FILE" ]]; then
    # Fresh install: authorization is not enabled yet, so the app user can be
    # created without credentials.
    S9_PASS="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
    export S9_PASS S9_USER="$MONGO_APP_USER" S9_DB="$MONGO_DB_NAME"
    log_info "Creating the MongoDB application user..."
    if ! mongosh --quiet "mongodb://127.0.0.1:27017/$MONGO_DB_NAME" --eval '
        const u = process.env.S9_USER;
        try { db.dropUser(u); } catch (e) { if (e.code === 13) { throw e; } }
        db.createUser({ user: u, pwd: process.env.S9_PASS,
                        roles: [{ role: "readWrite", db: process.env.S9_DB }] });
    '; then
        log_error "Could not create $MONGO_APP_USER. If MongoDB already requires auth, restore $ENV_FILE or temporarily disable security.authorization."
        exit 1
    fi
    (umask 077; printf 'MONGO_URI=mongodb://%s:%s@127.0.0.1:27017/%s?authSource=%s\nMONGO_DB_NAME=%s\n' \
        "$MONGO_APP_USER" "$S9_PASS" "$MONGO_DB_NAME" "$MONGO_DB_NAME" "$MONGO_DB_NAME" > "$ENV_FILE")
    log_success "Wrote protected credentials to $ENV_FILE"
else
    log_warn "Existing credentials preserved: $ENV_FILE"
fi
chown root:root "$ENV_FILE"
chmod 0600 "$ENV_FILE"

S9_URI="$(grep -E '^MONGO_URI=' "$ENV_FILE" | head -n1 | cut -d= -f2-)"
[[ -n "$S9_URI" ]] || { log_error "MONGO_URI missing from $ENV_FILE"; exit 1; }

# --------------------------------------------------
# STEP 7: Protected flag in the repository convention
# --------------------------------------------------

install -d -o root -g root -m 0711 "$FLAG_DIR"
setfacl -m "u:${SERVICE_USER}:--x" "$FLAG_DIR"

if [[ ! -f "$FLAG_FILE" && -f "$LEGACY_FLAG_FILE" ]]; then
    mv -- "$LEGACY_FLAG_FILE" "$FLAG_FILE"
    log_info "Migrated the existing Service 9 flag to $FLAG_FILE."
fi

if [[ ! -f "$FLAG_FILE" ]]; then
    FLAG_VALUE="${SERVICE9_FLAG:-HS{service9_$(python3 -c 'import secrets; print(secrets.token_hex(16))')}}"
    printf '%s\n' "$FLAG_VALUE" > "$FLAG_FILE"
    log_success "Created protected flag at $FLAG_FILE"
else
    log_warn "Existing flag preserved: $FLAG_FILE"
fi
chown "$SERVICE_USER:$SERVICE_USER" "$FLAG_FILE"
chmod 0400 "$FLAG_FILE"

# --------------------------------------------------
# STEP 8: Apply the protected seed file
# (preserved on reruns unless SERVICE9_RESEED=1)
# --------------------------------------------------

install -d -o root -g root -m 0755 "$PROTECTED_DIR"
# 0600: the seed holds the per-game dev tokens.
install -o root -g root -m 0600 "$SEED_SOURCE" "$SEED_FILE"

BUILD_COUNT="$(mongosh --quiet "$S9_URI" --eval 'db.builds.countDocuments({})' 2>/dev/null | tail -n1 | tr -d '[:space:]')" || BUILD_COUNT=""
[[ "$BUILD_COUNT" =~ ^[0-9]+$ ]] || BUILD_COUNT=0

if [[ "${SERVICE9_RESEED:-0}" == "1" || "$BUILD_COUNT" -eq 0 ]]; then
    if [[ "${SERVICE9_RESEED:-0}" == "1" ]]; then
        log_warn "SERVICE9_RESEED=1: dropping the existing builds collection."
        mongosh --quiet "$S9_URI" --eval 'db.builds.drop()' >/dev/null
    fi
    log_info "Applying $SEED_FILE to $MONGO_DB_NAME..."
    SERVICE9_FLAG="$(<"$FLAG_FILE")" MONGO_DB_NAME="$MONGO_DB_NAME" mongosh --quiet "$S9_URI" --file "$SEED_FILE"
    log_success "Database seed applied."
else
    log_warn "Existing builds collection preserved ($BUILD_COUNT documents)."
fi

# Keep the classified document's flag aligned with the protected flag file,
# including on reruns where the rest of the collection is preserved.
SERVICE9_FLAG="$(<"$FLAG_FILE")" mongosh --quiet "$S9_URI" --eval \
    'db.builds.updateOne({game_id: "gta7", classified: true}, {$set: {flag: process.env.SERVICE9_FLAG}})' >/dev/null

# --------------------------------------------------
# STEP 9: Require authentication on MongoDB, loopback only
# (players cannot read the build tokens straight from the database)
# --------------------------------------------------

if ! grep -Eq '^[[:space:]]+authorization:[[:space:]]*enabled' "$MONGO_CONF"; then
    cp -a "$MONGO_CONF" "$MONGO_CONF.backup.$(date +%Y%m%d-%H%M%S)"
    if grep -Eq '^security:' "$MONGO_CONF"; then
        sed -i '/^security:/a\  authorization: enabled' "$MONGO_CONF"
    else
        printf '\nsecurity:\n  authorization: enabled\n' >> "$MONGO_CONF"
    fi
    systemctl restart mongod
    log_success "MongoDB authorization enabled."
fi

# --------------------------------------------------
# STEP 10: Install systemd unit
# --------------------------------------------------

install -o root -g root -m 0644 "$UNIT_SOURCE" "$UNIT_DEST"
install -d -o root -g root -m 0755 /usr/local/libexec
install -o root -g root -m 0755 "$FLAG_SYNC_SOURCE" /usr/local/libexec/hackshield-service9-flag-sync
install -o root -g root -m 0644 "$FLAG_SYNC_SERVICE_SOURCE" /etc/systemd/system/hackshield-service9-flag-sync.service
install -o root -g root -m 0644 "$FLAG_SYNC_PATH_SOURCE" /etc/systemd/system/hackshield-service9-flag-sync.path
systemctl daemon-reload
systemctl enable --now hackshield-service9-flag-sync.path
# --------------------------------------------------
# STEP 11: Verify seeded challenge data
# --------------------------------------------------

# Confirm the classified record exists. The HTTP challenge is started by the
# environment's external service controller, so this script only checks data.
CLASSIFIED_ID="$(mongosh --quiet "$S9_URI" --eval 'const d = db.builds.findOne({classified: true}, {game_id: 1, _id: 0}); print(d ? d.game_id : "")' 2>/dev/null | tail -n1 | tr -d '[:space:]')" || CLASSIFIED_ID=""
if [[ -z "$CLASSIFIED_ID" ]]; then
    log_error "No classified build found in $MONGO_DB_NAME.builds; check $SEED_SOURCE."
    exit 1
fi
if [[ ! "$CLASSIFIED_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    log_error "Classified game_id contains unexpected characters; cannot run the self-test."
    exit 1
fi

log_success "Service 9 deployed; the external service controller manages its unit."
printf '\nPortal:        http://127.0.0.1:%s/\nCatalog API:   http://127.0.0.1:%s/api/builds\nHealth check:  http://127.0.0.1:%s/health\nMongoDB:       127.0.0.1:27017 (auth enabled, not exposed)\nSecret env:    %s\nSeed file:     %s\nFlag file:     %s (value not displayed)\nSystemd unit:  %s\nUnit source:   %s\n\n' \
    "$PORT" "$PORT" "$PORT" "$ENV_FILE" "$SEED_FILE" "$FLAG_FILE" "$SERVICE_NAME" "$UNIT_SOURCE"
echo "Keep this intentionally vulnerable service on the isolated competition network."
echo "Do NOT forward MongoDB port 27017 through QEMU."
