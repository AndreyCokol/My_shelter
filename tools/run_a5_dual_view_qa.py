#!/usr/bin/env python3
"""A5-owned isolated QA: execute (not merely import) the A2-08 dual-view test.

Runs on Linux and Windows; does not alter A1's general Godot test runner.
A green existing Core workflow alone is insufficient evidence for A2-08.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
SUITE = "game/tests/world/run_dual_view_tests.gd"
MARKER = re.compile(r"A2 DUAL VIEW TESTS: ([1-9][0-9]*) checks, 0 failures")
ERRORS = ("SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked")


def checked_run(args: list[str], timeout: int) -> str:
    command = [GODOT, *args]
    print("QA COMMAND:", " ".join(command), flush=True)
    try:
        result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                                errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"Godot invocation failed: {error}") from error
    print(result.stdout, end="", flush=True)
    if result.returncode != 0:
        raise RuntimeError(f"Godot exited with {result.returncode}: {args}")
    if any(error in result.stdout for error in ERRORS):
        raise RuntimeError(f"Godot reported engine or script errors: {args}")
    return result.stdout


def main() -> int:
    try:
        version = checked_run(["--version"], 15).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Wrong Godot version: {version!r}")
        checked_run(["--headless", "--path", ".", "--editor", "--import"], 90)
        output = checked_run(["--headless", "--path", ".", "--script", SUITE], 90)
        match = MARKER.search(output)
        if not match:
            raise RuntimeError("Missing an actual completed dual-view suite marker")
        print(f"A5 DUAL VIEW QA: PASS ({match.group(1)} checks on Godot {version})")
        return 0
    except RuntimeError as error:
        print(f"A5 DUAL VIEW QA: FAIL: {error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
