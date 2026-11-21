#!/usr/bin/env python3
"""A2-05: direct Godot regression. A green shared CI is insufficient."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
SUITES = [
    ("game/tests/world/run_spatial_whole_object_tests.gd", "A2 WHOLE OBJECT INTENT TESTS"),
    ("game/tests/world/run_spatial_whole_object_physics_tests.gd", "A2 WHOLE OBJECT PHYSICS TESTS"),
]


def invoke(arguments: list[str], timeout: int) -> str:
    command = [GODOT, *arguments]
    print("A2-05 COMMAND:", " ".join(command), flush=True)
    try:
        result = subprocess.run(
            command, cwd=ROOT, text=True, encoding="utf-8",
            errors="replace", stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"Godot invocation failed: {error}") from error
    print(result.stdout, end="", flush=True)
    if result.returncode or any(
        marker in result.stdout for marker in
        ("SCRIPT ERROR:", "ERROR:", "WARNING: ObjectDB instances leaked")
    ):
        raise RuntimeError(f"Godot failure in {arguments}, exit={result.returncode}")
    return result.stdout


def main() -> int:
    try:
        version = invoke(["--version"], 20).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Expected Godot 4.7.2 stable, got {version!r}")
        invoke(["--headless", "--path", ".", "--editor", "--import"], 120)
        total = 0
        for script, marker in SUITES:
            output = invoke(["--headless", "--path", ".", "--script", script], 120)
            match = re.search(re.escape(marker) + r": ([1-9][0-9]*) checks, 0 failures", output)
            if not match:
                raise RuntimeError(f"No completed Godot evidence for {script}")
            total += int(match.group(1))
        print(f"A2 WHOLE OBJECT QA: PASS ({total} direct checks on {version})")
        return 0
    except RuntimeError as error:
        print(f"A2 WHOLE OBJECT QA: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
