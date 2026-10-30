#!/usr/bin/env python3
"""Register this VM and persist its six-service port assignment."""

import json
import os
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from service_mapping import normalize_mapping

RUN_DIR = "/run/hackshield"
MAPPING_FILE = os.path.join(RUN_DIR, "service-port-mapping.json")
ATTEMPTS = 5


def persist_mapping(mapping):
    payload = {"service_ports": {str(number): port for number, port in mapping.items()}}
    fd, temporary = tempfile.mkstemp(prefix="service-port-mapping.", dir=RUN_DIR)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, MAPPING_FILE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    team = os.environ.get("TEAM_NAME", "").strip()
    server = os.environ.get("GAME_SERVER_ADDR", "").rstrip("/")
    if not team or not server.startswith(("http://", "https://")):
        raise RuntimeError("TEAM_NAME or GAME_SERVER_ADDR is missing from boot.env")

    payload = json.dumps({"team": team, "boot_time": int(time.time() * 1000)}).encode()
    request = Request(
        server + "/api/register_boot",
        data=payload,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    os.makedirs(RUN_DIR, mode=0o755, exist_ok=True)
    try:
        os.unlink(MAPPING_FILE)
    except FileNotFoundError:
        pass
    last_error = None
    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urlopen(request, timeout=15) as response:
                result = json.loads(response.read().decode("utf-8"))
            mapping = normalize_mapping(result)
            persist_mapping(mapping)
            print("Registered boot and saved assignments for services: " +
                  ", ".join(f"service{n}:{port}" for n, port in mapping.items()))
            return
        except HTTPError as exc:
            last_error = RuntimeError(f"game server returned HTTP {exc.code}")
            if exc.code < 500:
                break
        except (URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
            last_error = exc
            if isinstance(exc, ValueError):
                break
        if attempt < ATTEMPTS:
            time.sleep(5)
    raise RuntimeError(f"Could not register VM or obtain a valid service mapping: {last_error}")


if __name__ == "__main__":
    main()
