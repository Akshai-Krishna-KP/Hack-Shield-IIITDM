#!/usr/bin/env python3
"""Register this VM and persist its six-service port assignment."""

import json
import os
import ssl
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from service_mapping import normalize_mapping

RUN_DIR = "/run/hackshield"
MAPPING_FILE = os.path.join(RUN_DIR, "service-port-mapping.json")
BOOT_TIME_FILE = os.path.join(RUN_DIR, "boot-time.json")
RETRY_MAX_DELAY = 30
# The game server may use a self-signed certificate; registration is only
# trusted by source IP on the server side, so skip TLS verification.
TLS_CONTEXT = ssl._create_unverified_context()


def persist_json(path, payload):
    fd, temporary = tempfile.mkstemp(prefix=os.path.basename(path) + ".", dir=RUN_DIR)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def persist_mapping(mapping):
    persist_json(MAPPING_FILE, {"service_ports": {str(number): port for number, port in mapping.items()}})


def main():
    team = os.environ.get("TEAM_NAME", "").strip()
    server = os.environ.get("GAME_SERVER_ADDR", "").rstrip("/")
    if not team or not server.startswith(("http://", "https://")):
        raise RuntimeError("TEAM_NAME or GAME_SERVER_ADDR is missing from boot.env")

    os.makedirs(RUN_DIR, mode=0o755, exist_ok=True)
    for stale in (MAPPING_FILE, BOOT_TIME_FILE):
        try:
            os.unlink(stale)
        except FileNotFoundError:
            pass
    # Keep retrying: the team may not be added on the game server yet (403),
    # or the server may not be up yet. Each attempt sends the current time, so
    # the server's flag window starts when registration actually succeeds.
    attempt, delay = 0, 5
    while True:
        attempt += 1
        boot_time = int(time.time() * 1000)
        request = Request(
            server + "/api/register_boot",
            data=json.dumps({"team": team, "boot_time": boot_time}).encode(),
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=15, context=TLS_CONTEXT) as response:
                result = json.loads(response.read().decode("utf-8"))
            mapping = normalize_mapping(result)
            persist_mapping(mapping)
            # The flag rotator derives its ticks from the exact boot_time the server accepted
            persist_json(BOOT_TIME_FILE, {"team": team, "boot_time": boot_time})
            print("Registered boot and saved assignments for services: " +
                  ", ".join(f"service{n}:{port}" for n, port in mapping.items()), flush=True)
            return
        except HTTPError as exc:
            error = f"game server returned HTTP {exc.code}"
        except (URLError, OSError, json.JSONDecodeError, ValueError) as exc:
            error = str(exc)
        print(f"[WARN] Registration attempt {attempt} failed ({error}); retrying in {delay}s",
              flush=True)
        time.sleep(delay)
        delay = min(delay * 2, RETRY_MAX_DELAY)


if __name__ == "__main__":
    main()
