#!/usr/bin/env python3
"""A2-01 deterministic optional mobility + real Player physics acceptance."""
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
SUITES = [
    ("game/tests/world/run_a2_locomotion_tests.gd", "A2 LOCOMOTION CONTRACT TESTS"),
    ("game/tests/world/run_a2_water_contact_tests.gd", "A2 REAL WATER CONTACT TESTS"),
    ("game/tests/e2e/run_a2_water_gameapp_compat_tests.gd", "A2 WATER GAMEAPP COMPAT TESTS"),
]

def call(args, timeout=120):
    cmd = [GODOT, *args]
    print("A2-01 CMD:", " ".join(cmd), flush=True)
    try:
        result = subprocess.run(cmd, cwd=ROOT, encoding="utf-8",
                                errors="replace", text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(str(exc)) from exc
    print(result.stdout, end="", flush=True)
    if result.returncode or any(tag in result.stdout for tag in (
        "SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked"
    )):
        raise RuntimeError(f"Native Godot error at {args}: exit={result.returncode}")
    return result.stdout

def main():
    try:
        version = call(["--version"], 15).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Expected Godot 4.7.2 stable, got {version!r}")
        call(["--headless", "--path", ".", "--editor", "--import"])
        total = 0
        for script, marker in SUITES:
            output = call(["--headless", "--path", ".", "--script", script])
            count = re.search(re.escape(marker) + r": ([1-9][0-9]*) checks, 0 failures", output)
            if not count:
                raise RuntimeError(f"No completed direct Godot evidence for {script}")
            total += int(count.group(1))
        print(f"A2 LOCOMOTION QA: PASS ({total} direct Godot checks on {version})")
        return 0
    except RuntimeError as exc:
        print(f"A2 LOCOMOTION QA: FAIL {exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
