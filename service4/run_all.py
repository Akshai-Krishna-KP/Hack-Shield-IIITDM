#!/usr/bin/env python3
"""Run both Service 4 processes under one systemd unit."""
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
children = []
stopping = False


def stop_children(_signum=None, _frame=None):
    global stopping
    stopping = True
    for child in children:
        if child.poll() is None:
            child.terminate()


signal.signal(signal.SIGTERM, stop_children)
signal.signal(signal.SIGINT, stop_children)

try:
    children.append(subprocess.Popen([sys.executable, str(ROOT / "internal_api.py")]))
    time.sleep(0.2)
    children.append(subprocess.Popen([sys.executable, str(ROOT / "app.py")]))

    while not stopping:
        for child in children:
            result = child.poll()
            if result is not None:
                stop_children()
                sys.exit(result or 1)
        time.sleep(0.2)
finally:
    stop_children()
    for child in children:
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
