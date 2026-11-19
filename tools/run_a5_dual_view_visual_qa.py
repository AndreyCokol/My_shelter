#!/usr/bin/env python3
"""A5 visual QA: assert real software-rendered orthographic + FPS PNGs."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/tmp/shelter-dual-view")
SCRIPT = "game/tests/world/run_dual_view_visual_tests.gd"
PNG_SIZE = (1280, 720)
EXPECTED = ("topdown_1280x720.png", "first_person_1280x720.png")


def main() -> int:
    xvfb = shutil.which("xvfb-run")
    if not xvfb:
        print("A5 DUAL VIEW VISUAL QA: NOT_RUN missing xvfb-run", file=sys.stderr)
        return 1
    godot = os.environ.get("GODOT", "godot")
    command = [xvfb, "-a", "-s", "-screen 0 1920x1080x24", godot,
               "--rendering-method", "gl_compatibility",
               "--audio-driver", "Dummy", "--path", ".", "--max-fps", "60",
               "--script", SCRIPT]
    try:
        result = subprocess.run(command, cwd=ROOT, env=dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1"),
                                text=True, encoding="utf-8", errors="replace",
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"A5 DUAL VIEW VISUAL QA: FAIL invocation: {error}", file=sys.stderr)
        return 1
    print(result.stdout, end="", flush=True)
    if result.returncode or not re.search(r"A5 DUAL VIEW VISUAL TESTS: [1-9][0-9]* checks, 0 failures", result.stdout):
        print("A5 DUAL VIEW VISUAL QA: FAIL no successful actual rendering marker", file=sys.stderr)
        return 1
    if any(token in result.stdout for token in ("SCRIPT ERROR:", "ERROR:", "instances leaked")):
        print("A5 DUAL VIEW VISUAL QA: FAIL Godot reported errors", file=sys.stderr)
        return 1
    for filename in EXPECTED:
        image = OUT / filename
        if not image.is_file() or image.stat().st_size < 3000:
            print(f"A5 DUAL VIEW VISUAL QA: FAIL missing/empty actual screenshot: {image}", file=sys.stderr)
            return 1
        with image.open("rb") as handle:
            header = handle.read(24)
        if header[:8] != bytes.fromhex("89504e470d0a1a0a"):
            print(f"A5 DUAL VIEW VISUAL QA: FAIL invalid PNG: {image}", file=sys.stderr)
            return 1
        size = struct.unpack(">II", header[16:24])
        if size != PNG_SIZE:
            print(f"A5 DUAL VIEW VISUAL QA: FAIL {image} is {size}, not {PNG_SIZE}", file=sys.stderr)
            return 1
    print("A5 DUAL VIEW VISUAL QA: PASS (2 real Godot PNG renders at 1280x720)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
