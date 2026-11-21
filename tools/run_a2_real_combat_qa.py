#!/usr/bin/env python3
"""A2-02 direct Godot test of production Player/Enemy/PhysicsServer2D methods."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
SUITES = [
    ("game/tests/e2e/run_a2_real_combat_physics_tests.gd", "A2 REAL COMBAT PHYSICS TESTS"),
    ("game/tests/e2e/run_a2_gameapp_first_kill_e2e.gd", "A2 GAMEAPP FIRST KILL E2E TESTS"),
]

def run(args: list[str], timeout: int) -> str:
    cmd = [GODOT, *args]
    print("A2 COMBAT QA COMMAND:", " ".join(cmd), flush=True)
    try:
        result = subprocess.run(cmd, cwd=ROOT, text=True, encoding="utf-8",
                                errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"Godot unavailable or timed out: {error}") from error
    print(result.stdout, end="", flush=True)
    if result.returncode or any(text in result.stdout for text in ("SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked")):
        raise RuntimeError(f"Godot failed at args={args} exit={result.returncode}")
    return result.stdout

def main() -> int:
    try:
        version = run(["--version"], 15).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Expected pinned Godot 4.7.2 stable, got {version!r}")
        run(["--headless", "--path", ".", "--editor", "--import"], 120)
        total = 0
        for script, marker in SUITES:
            output = run(["--headless", "--path", ".", "--script", script], 120)
            match = re.search(re.escape(marker) + r": ([1-9][0-9]*) checks, 0 failures", output)
            if not match:
                raise RuntimeError(f"No zero-failure marker for actual Godot script: {script}")
            total += int(match.group(1))
        print(f"A2 REAL COMBAT QA: PASS ({total} Godot checks on {version})")
        return 0
    except RuntimeError as error:
        print(f"A2 REAL COMBAT QA: FAIL {error}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
