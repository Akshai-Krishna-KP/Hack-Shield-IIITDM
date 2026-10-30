#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")"

echo "======================================"
echo "       Hack & Shield VM Launcher"
echo "======================================"

# Prompt for configuration
[[ -n "${TEAM_NAME:-}" ]] || read -r -p "Enter Team Name: " TEAM_NAME
[[ -n "${GAME_SERVER_ADDR:-}" ]] || read -r -p "Enter Game Server IP/address (e.g. http://192.168.1.10:5000 or https://...): " GAME_SERVER_ADDR

# Validate input
if [[ -z "$TEAM_NAME" ]]; then
    echo "Error: Team name cannot be empty."
    exit 1
fi

if [[ -z "$GAME_SERVER_ADDR" ]]; then
    echo "Error: Game Server IP/address cannot be empty."
    exit 1
fi

# Add scheme if the user enters only an IP or hostname
if [[ ! "$GAME_SERVER_ADDR" =~ ^https?:// ]]; then
    GAME_SERVER_ADDR="http://${GAME_SERVER_ADDR}"
fi

# Create temporary JSON configuration for the guest VM
BOOT_CONFIG="$(mktemp)"
trap 'rm -f "$BOOT_CONFIG"' EXIT

python3 - "$BOOT_CONFIG" "$TEAM_NAME" "$GAME_SERVER_ADDR" <<'PY'
import json
import sys

path, team, server = sys.argv[1:]

with open(path, "w", encoding="utf-8") as f:
    json.dump({
        "TEAM_NAME": team,
        "GAME_SERVER_ADDR": server
    }, f)
PY

echo
echo "Starting Hack & Shield VM..."
echo "Team: $TEAM_NAME"
echo "Game Server: $GAME_SERVER_ADDR"
echo

# The game server assigns each of the six services a random port in 5000-5050
# (must match FORWARDED_SERVICE_PORTS in script/game_server/service_mapping.py),
# so forward the whole range to the same ports on the host.
# Keep SSH on host port 2222 -> guest 22, and MySQL 3306 for the Service 1 challenge.
NIC_OPTS="user,model=virtio-net-pci,hostfwd=tcp::${SSH_PORT:-2222}-:22,hostfwd=tcp::3306-:3306"
for port in {5000..5050}; do
    NIC_OPTS+=",hostfwd=tcp::${port}-:${port}"
done

qemu-system-x86_64 \
    -name hackshield \
    -machine q35 \
    -accel kvm \
    -cpu host \
    -smp 2 \
    -m 4096 \
    -drive file="${VM_IMAGE:-vm/hacksheild.qcow2}",format=qcow2,if=virtio \
    -boot order=c \
    -fw_cfg name=opt/org.hackshield/boot-config,file="$BOOT_CONFIG" \
    -nic "$NIC_OPTS" \
    "$@"
