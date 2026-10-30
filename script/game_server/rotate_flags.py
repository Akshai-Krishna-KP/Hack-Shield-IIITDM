#!/usr/bin/env python3
"""Write the game server's current flag for each allocated service every tick.

Flags match the game server's flagauthenticator.generate_sha256_flag():
HMAC-SHA256(key "Hack&Shield", "<team>-service<N>-<tick>") with
tick = boot_time + k * 60000 (ms). A flag stays valid on the server for
5 minutes after its tick.
"""

import hashlib
import hmac
import json
import time
from pathlib import Path

from service_mapping import normalize_mapping

RUN_DIR = Path("/run/hackshield")
MAPPING_FILE = RUN_DIR / "service-port-mapping.json"
BOOT_TIME_FILE = RUN_DIR / "boot-time.json"
FLAG_DIR = Path("/opt/flags")
SALT = b"Hack&Shield"
TICK_MS = 60000


def make_flag(team, service, tick_time):
    message = f"{team}-{service}-{tick_time}".encode()
    digest = hmac.new(SALT, message, hashlib.sha256).hexdigest()
    return f"FLAG{{{team}_{service}_{digest}}}"


def main():
    boot = json.loads(BOOT_TIME_FILE.read_text(encoding="utf-8"))
    team, boot_time = boot["team"], int(boot["boot_time"])
    services = list(normalize_mapping(json.loads(MAPPING_FILE.read_text(encoding="utf-8"))))

    # Resume at the current tick if restarted mid-game
    tick = max(0, (int(time.time() * 1000) - boot_time) // TICK_MS)
    while True:
        tick_time = boot_time + tick * TICK_MS
        for number in services:
            # Truncate in place so the file keeps its userN owner and 0400 mode;
            # close_write also triggers hackshield-service9-flag-sync.path
            with open(FLAG_DIR / f"flag{number}", "w", encoding="utf-8") as stream:
                stream.write(make_flag(team, f"service{number}", tick_time))
        print(f"Wrote tick {tick} flags for services {services}", flush=True)
        tick += 1
        time.sleep(max(0.0, (boot_time + tick * TICK_MS) / 1000 - time.time()))


if __name__ == "__main__":
    main()
