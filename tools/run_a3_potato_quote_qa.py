#!/usr/bin/env python3
"""Isolated A3 potato quote QA. Runs the NEW GDScript suite, not the shared runner."""
from __future__ import annotations
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
SUITE = "game/tests/e2e/run_a3_potato_quote_tests.gd"
MARKER = re.compile(r"A3 POTATO QUOTE TESTS: ([1-9][0-9]*) checks, 0 failures")
ERROR_MARKERS = ("SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked")

def run_godot(arguments: list[str], timeout: int) -> str:
    command = [GODOT, *arguments]
    print("A3 QA COMMAND:", " ".join(command), flush=True)
    try:
        proc = subprocess.run(
            command, cwd=ROOT, text=True, encoding="utf-8",
            errors="replace", stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"Godot invocation unavailable/timeout: {exc}") from exc
    print(proc.stdout, end="", flush=True)
    if proc.returncode != 0:
        raise RuntimeError(f"Godot exit {proc.returncode}: {arguments}")
    if any(marker in proc.stdout for marker in ERROR_MARKERS):
        raise RuntimeError(f"Godot reported script/engine errors: {arguments}")
    return proc.stdout

def main() -> int:
    try:
        version = run_godot(["--version"], 15).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Expected pinned Godot 4.7.2 stable; got {version!r}")
        run_godot(["--headless", "--path", ".", "--editor", "--import"], 120)
        output = run_godot(["--headless", "--path", ".", "--script", SUITE], 240)
        match = MARKER.search(output)
        if not match:
            raise RuntimeError("Required new A3 potato quote suite completion marker absent")
        print(f"A3 POTATO QUOTE ISOLATED QA: PASS ({match.group(1)} checks on {version})")
        return 0
    except RuntimeError as exc:
        print(f"A3 POTATO QUOTE ISOLATED QA: FAIL: {exc}", file=sys.stderr, flush=True)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
