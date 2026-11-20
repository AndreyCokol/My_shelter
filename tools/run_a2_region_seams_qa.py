#!/usr/bin/env python3
"""A2-04: actual Godot regression for canonical reciprocal region seams."""
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
SUITE = "game/tests/world/run_region_seam_tests.gd"
MARK = re.compile(r"A2 REGION SEAM TESTS: ([1-9][0-9]*) checks, 0 failures")

def run(args, timeout=100):
    cmd = [GODOT, *args]
    print("A2 REGIONS QA COMMAND:", " ".join(cmd), flush=True)
    try:
        p = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, encoding="utf-8", errors="replace", timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as e:
        raise RuntimeError(str(e)) from e
    print(p.stdout, end="", flush=True)
    if p.returncode or any(tag in p.stdout for tag in ("SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked")):
        raise RuntimeError(f"Godot failed with exit={p.returncode}")
    return p.stdout

def main():
    try:
        version = run(["--version"], 15).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Godot 4.7.2 stable required, got {version!r}")
        run(["--headless", "--path", ".", "--editor", "--import"], 120)
        output = run(["--headless", "--path", ".", "--script", SUITE], 120)
        m = MARK.search(output)
        if not m:
            raise RuntimeError("No evidence the region-seam suite actually finished")
        print(f"A2 REGION SEAMS QA: PASS ({m.group(1)} checks, Godot {version})")
        return 0
    except RuntimeError as e:
        print(f"A2 REGION SEAMS QA: FAIL: {e}", file=sys.stderr, flush=True)
        return 1

if __name__ == "__main__":
    sys.exit(main())
