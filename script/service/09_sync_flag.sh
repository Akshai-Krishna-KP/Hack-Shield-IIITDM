#!/usr/bin/env bash
# Copy the current protected flag into Service 9's classified MongoDB record.
set -Eeuo pipefail
umask 077

FLAG_FILE="/opt/flags/flag9"

if ! /usr/bin/systemctl is-active --quiet hackshield-service9.service; then
    printf '[INFO] Service 9 is inactive; skipping the MongoDB flag sync.\n'
    exit 0
fi

if [[ ! -r "$FLAG_FILE" ]]; then
    printf '[ERROR] Service 9 flag is missing or unreadable: %s\n' "$FLAG_FILE" >&2
    exit 1
fi
if [[ -z "${MONGO_URI:-}" ]]; then
    printf '[ERROR] MONGO_URI is not set.\n' >&2
    exit 1
fi

SERVICE9_FLAG="$(<"$FLAG_FILE")"
if [[ -z "$SERVICE9_FLAG" ]]; then
    printf '[ERROR] Service 9 flag file is empty.\n' >&2
    exit 1
fi

export SERVICE9_FLAG
mongosh --quiet "$MONGO_URI" --eval '
const result = db.builds.updateOne(
    { game_id: "gta7", classified: true },
    { $set: { flag: process.env.SERVICE9_FLAG } }
);
if (result.matchedCount !== 1) {
    print("Expected exactly one classified Service 9 record; matched " + result.matchedCount + ".");
    quit(1);
}
print("Service 9 flag synchronized to MongoDB.");
'
