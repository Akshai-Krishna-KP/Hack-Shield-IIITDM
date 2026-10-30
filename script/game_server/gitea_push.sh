#!/bin/bash
# Usage: gitea_push.sh N
# Commits /opt/hackshield/services/serviceN and pushes it to branch "serviceN"
# of the team's Gitea repo (team_<name>/service-patches on the game server, :3000).
# Runs on every service start, so a patched + restarted service gets committed
# and pushed (patch tracking). Only commits when the tree changed.
# Never fails the service: called as ExecStartPost=-+...

set -u
N="$1"
SERVICE="service$N"
SRC="/opt/hackshield/services/$SERVICE"
GITEA_PORT=3000

[[ -d "$SRC" ]] || { echo "gitea_push: $SRC missing"; exit 0; }

# TEAM_NAME / GAME_SERVER_ADDR come from the unit's EnvironmentFile=/run/hackshield/boot.env
# (parsed by systemd). Never source boot.env in bash: $(...) in a team name would run.
if [[ -z "${TEAM_NAME:-}" || -z "${GAME_SERVER_ADDR:-}" ]]; then
    echo "gitea_push: TEAM_NAME/GAME_SERVER_ADDR not set (no boot config?); skipping $SERVICE"
    exit 0
fi

# Same naming as the game server's gitea.get_team_credentials()
TEAM_SLUG="$(echo "$TEAM_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')"
GITEA_USER="team_${TEAM_SLUG}"
GITEA_PASS="ctf_secret_${TEAM_SLUG}_2026"
GITEA_HOST="$(echo "$GAME_SERVER_ADDR" | sed -E 's#^https?://##; s#[:/].*$##')"
REMOTE="http://${GITEA_USER}:${GITEA_PASS}@${GITEA_HOST}:${GITEA_PORT}/${GITEA_USER}/service-patches.git"

G=(git -C "$SRC" -c safe.directory="$SRC" -c user.name="hackshield-vm" -c user.email="vm@hackshield.local")

if [[ ! -d "$SRC/.git" ]]; then
    "${G[@]}" init -q -b "$SERVICE"
    printf '.venv/\n__pycache__/\n*.pyc\n' > "$SRC/.git/info/exclude"
fi

"${G[@]}" add -A
"${G[@]}" diff --cached --quiet || "${G[@]}" commit -q -m "$SERVICE snapshot at $(date -Is)"

push() { timeout 10 "${G[@]}" push -q "$@" "$REMOTE" "HEAD:refs/heads/$SERVICE" 2>&1; }

if out="$(push)"; then
    echo "gitea_push: $SERVICE pushed to $GITEA_HOST"
elif [[ "$out" == *"[rejected]"* ]] && out="$(push --force)"; then
    # Remote branch has history from a previous VM (e.g. VM reset); this VM's tree wins
    echo "gitea_push: $SERVICE force-pushed to $GITEA_HOST (remote had unrelated history)"
else
    echo "gitea_push: $SERVICE push FAILED: ${out//$GITEA_PASS/***}"
fi
exit 0
