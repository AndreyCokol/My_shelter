#!/usr/bin/env python3
"""A2-07 executable standalone tests; green unrelated Core CI is not evidence."""
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = os.environ.get("GODOT", "godot")
SUITES = [
    ("game/tests/world/run_safe_return_tests.gd", "A2 SAFE RETURN TESTS"),
    ("game/tests/world/run_safe_reachable_tests.gd", "A2 SAFE REACHABLE TESTS"),
    ("game/tests/world/run_live_safe_return_physics_tests.gd", "A2 LIVE SAFE RETURN PHYSICS TESTS"),
]
ERRORS = ("SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked")

def run(args, timeout=100):
    command = [ENGINE, *args]
    print("A2 QA COMMAND:", " ".join(command), flush=True)
    try:
        proc = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                              errors="replace", stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as exc:
        raise RuntimeError(f"Could not run Godot: {exc}") from exc
    print(proc.stdout, end="", flush=True)
    if proc.returncode or any(token in proc.stdout for token in ERRORS):
        raise RuntimeError(f"Failed Godot args={args}, exit={proc.returncode}")
    return proc.stdout

def main():
    try:
        version = run(["--version"], 20).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Godot must be pinned to 4.7.2 stable, got {version!r}")
        run(["--headless", "--path", ".", "--editor", "--import"], 120)
        total = 0
        for path, marker in SUITES:
            output = run(["--headless", "--path", ".", "--script", path], 120)
            match = re.search(re.escape(marker) + r": ([1-9][0-9]*) checks, 0 failures", output)
            if not match:
                raise RuntimeError(f"Suite did not actually finish: {path}")
            total += int(match.group(1))
        print(f"A2 SAFE RETURN QA: PASS ({total} direct Godot assertions on {version})")
        return 0
    except RuntimeError as exc:
        print(f"A2 SAFE RETURN QA: FAIL {exc}", file=sys.stderr, flush=True)
        return 1

if __name__ == "__main__":
    sys.exit(main())
