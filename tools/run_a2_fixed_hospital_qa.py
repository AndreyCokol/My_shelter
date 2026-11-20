#!/usr/bin/env python3
"""A2-03: execute the fixed starter hospital/roof suite in pinned Godot."""
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
SUITE = "game/tests/world/run_fixed_start_hospital_tests.gd"
MARKER = re.compile(r"A2 FIXED HOSPITAL PROTOTYPE TESTS: ([1-9][0-9]*) checks, 0 failures")

def run(args, timeout=110):
    command = [GODOT, *args]
    print("A2 HOSPITAL QA COMMAND:", " ".join(command), flush=True)
    try:
        result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                                errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(str(e)) from e
    print(result.stdout, end="", flush=True)
    if result.returncode or any(token in result.stdout for token in ("SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked")):
        raise RuntimeError(f"Failed Godot args={args}, exit={result.returncode}")
    return result.stdout

def main():
    try:
        version = run(["--version"], 15).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Pinned 4.7.2 stable expected, got {version!r}")
        run(["--headless", "--path", ".", "--editor", "--import"], 120)
        output = run(["--headless", "--path", ".", "--script", SUITE], 120)
        match = MARKER.search(output)
        if not match:
            raise RuntimeError("No direct Godot completion marker for hospital/roof test")
        print(f"A2 FIXED HOSPITAL QA: PASS ({match.group(1)} checks in Godot {version})")
        return 0
    except RuntimeError as error:
        print(f"A2 FIXED HOSPITAL QA: FAIL {error}", file=sys.stderr, flush=True)
        return 1

if __name__ == "__main__":
    sys.exit(main())
