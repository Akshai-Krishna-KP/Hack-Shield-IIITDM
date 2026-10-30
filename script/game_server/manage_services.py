#!/usr/bin/env python3
"""Start only the six game-server-selected services on their assigned ports."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from service_mapping import normalize_mapping

RUN_DIR = Path("/run/hackshield")
MAPPING_FILE = RUN_DIR / "service-port-mapping.json"
SUDOERS_FILE = Path("/etc/sudoers.d/hackshield-player-restart")
SERVICE_IDS = range(1, 10)


def systemctl(*arguments, check=True):
    return subprocess.run(["/usr/bin/systemctl", *arguments], check=check)


def write_sudoers(mapping):
    commands = [f"/usr/bin/systemctl restart hackshield-service{n}.service"
                for n in mapping]
    contents = (
        "player ALL=(root) NOPASSWD: " + ", ".join(commands) + "\n"
        if commands else
        "# Service restart permissions are disabled until a valid allocation is received.\n"
    )
    SUDOERS_FILE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="hackshield-player-restart.",
                                     dir=SUDOERS_FILE.parent, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o440)
        subprocess.run(["/usr/sbin/visudo", "-cf", temporary], check=True)
        os.replace(temporary, SUDOERS_FILE)
        os.chown(SUDOERS_FILE, 0, 0)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def clear_service_env():
    RUN_DIR.mkdir(mode=0o755, parents=True, exist_ok=True)
    for number in SERVICE_IDS:
        (RUN_DIR / f"service{number}.env").unlink(missing_ok=True)


def stop_all():
    failures = []
    for number in SERVICE_IDS:
        result = systemctl("stop", f"hackshield-service{number}.service", check=False)
        if result.returncode not in (0, 5):
            failures.append(number)
    for dependency in ("mysql.service", "mongod.service"):
        result = systemctl("stop", dependency, check=False)
        if result.returncode not in (0, 5):
            failures.append(dependency)
    clear_service_env()
    write_sudoers({})
    if failures:
        raise RuntimeError("Could not stop service(s): " + ", ".join(map(str, failures)))


def load_mapping():
    with MAPPING_FILE.open(encoding="utf-8") as stream:
        return normalize_mapping(json.load(stream))


def apply_mapping():
    mapping = load_mapping()
    RUN_DIR.mkdir(mode=0o755, parents=True, exist_ok=True)
    os.chmod(RUN_DIR, 0o755)
    stop_all()

    try:
        for number, port in mapping.items():
            env_file = RUN_DIR / f"service{number}.env"
            temporary = env_file.with_suffix(".env.tmp")
            temporary.write_text(f"PORT={port}\n", encoding="ascii")
            os.chmod(temporary, 0o644)
            os.replace(temporary, env_file)

        if 1 in mapping:
            systemctl("start", "mysql.service")
        for number in mapping:
            systemctl("start", f"hackshield-service{number}.service")
        for number in mapping:
            systemctl("is-active", "--quiet", f"hackshield-service{number}.service")
        write_sudoers(mapping)
        print("Started exactly six allocated services.")
    except Exception:
        stop_all()
        raise


def main():
    action = sys.argv[1] if len(sys.argv) == 2 else "apply"
    if action == "apply":
        apply_mapping()
    elif action == "stop-all":
        stop_all()
    else:
        raise SystemExit("usage: manage_services.py [apply|stop-all]")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
