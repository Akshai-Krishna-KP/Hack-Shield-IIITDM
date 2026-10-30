#!/usr/bin/env python3
"""Read TEAM_NAME and GAME_SERVER_ADDR supplied through QEMU fw_cfg."""

import json
import os
import tempfile

SOURCE = "/sys/firmware/qemu_fw_cfg/by_name/opt/org.hackshield/boot-config/raw"
RUN_DIR = "/run/hackshield"
DESTINATION = os.path.join(RUN_DIR, "boot.env")


def systemd_quote(value):
    if "\n" in value or "\r" in value or "\0" in value:
        raise RuntimeError("Boot configuration values cannot contain newline or NUL characters")
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    with open(SOURCE, encoding="utf-8") as stream:
        config = json.load(stream)
    for key in ("TEAM_NAME", "GAME_SERVER_ADDR"):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise RuntimeError(f"Missing or invalid {key} in QEMU boot configuration")

    address = config["GAME_SERVER_ADDR"].strip()
    if not address.startswith(("http://", "https://")):
        raise RuntimeError("GAME_SERVER_ADDR must start with http:// or https://")

    os.makedirs(RUN_DIR, mode=0o755, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="boot.env.", dir=RUN_DIR, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            for key in ("TEAM_NAME", "GAME_SERVER_ADDR"):
                stream.write(f"{key}={systemd_quote(config[key].strip())}\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, DESTINATION)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("Hack & Shield boot configuration loaded.")


if __name__ == "__main__":
    main()
