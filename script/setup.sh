#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Base directory configuration
BASE_DIR="/home/hacker/script"
SEQ_DIR="$BASE_DIR/service"
LOG_DIR="/tmp/script_logs"

# Colors for pretty logging
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Ensure script is run with sudo privileges if needed
if [ "$EUID" -ne 0 ]; then
  log_warn "Some installation steps may require sudo privileges."
fi

## ==========================================
## STEP 1: System Update & Essential Packages
## ==========================================
log_info "Starting system update and essential packages installation..."

sudo apt-get update && sudo apt-get upgrade -y

ESSENTIAL_PACKAGES=(
    curl
    wget
    git
    build-essential
    htop
    unzip
    jq
    acl
)

log_info "Installing essential packages: ${ESSENTIAL_PACKAGES[*]}"
sudo apt-get install -y "${ESSENTIAL_PACKAGES[@]}"

log_success "System update and essential installations completed."

## ==========================================
## STEP 2: Run Sequential Scripts (In Order)
## ==========================================
log_info "Checking for sequential scripts in: $SEQ_DIR"

if [ -d "$SEQ_DIR" ]; then
    # Sorts alphabetically so you can prefix with numbers (e.g., 01_db.sh, 02_config.sh)
    for script in "$SEQ_DIR"/*.sh; do
        if [ -f "$script" ]; then
            log_info "Running sequential script: $(basename "$script")"
            bash "$script"
            log_success "Finished: $(basename "$script")"
        fi
    done
else
    log_warn "Sequential directory not found at $SEQ_DIR, skipping."
fi

log_success "All setup steps and sub-scripts finished successfully!"