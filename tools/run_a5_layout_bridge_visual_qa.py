#!/usr/bin/env python3
"""A5: enforce four real Godot v5 hospital/city screenshots (Linux Xvfb)."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path("/tmp/shelter-a5-real-layout")
FILES = (
    "hospital_floor3_topdown_1280x720.png",
    "hospital_floor3_fps_1280x720.png",
    "hospital_floor1_topdown_1280x720.png",
    "outside_topdown_1280x720.png",
)

def main() -> int:
    xvfb = shutil.which("xvfb-run")
    if not xvfb:
        print("A5 REAL LAYOUT VISUAL QA: NOT_RUN — missing xvfb-run", file=sys.stderr)
        return 1
    godot = os.environ.get("GODOT", "godot")
    cmd = [xvfb, "-a", "-s", "-screen 0 1920x1080x24", godot,
           "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
           "--path", ".", "--max-fps", "60", "--script",
           "game/tests/world/run_dual_view_layout_visual_tests.gd"]
    try:
        r = subprocess.run(cmd, cwd=ROOT, text=True, encoding="utf-8",
                           errors="replace", stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=120,
                           env=dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1"))
    except (subprocess.TimeoutExpired, OSError) as exc:
        print("A5 REAL LAYOUT VISUAL QA: FAIL invocation", exc, file=sys.stderr)
        return 1
    print(r.stdout, end="", flush=True)
    if r.returncode or not re.search(r"A5 REAL LAYOUT VISUAL TESTS: [1-9][0-9]* checks, 0 failures", r.stdout):
        print("A5 REAL LAYOUT VISUAL QA: FAIL missing real renderer completion", file=sys.stderr)
        return 1
    if any(word in r.stdout for word in ("SCRIPT ERROR:", "ERROR:", "instances leaked")):
        print("A5 REAL LAYOUT VISUAL QA: FAIL engine errors", file=sys.stderr)
        return 1
    for name in FILES:
        image = OUTPUT / name
        if not image.is_file() or image.stat().st_size < 3000:
            print(f"A5 REAL LAYOUT VISUAL QA: FAIL missing frame {name}", file=sys.stderr)
            return 1
        with image.open("rb") as handle:
            header = handle.read(24)
        if header[:8] != bytes.fromhex("89504e470d0a1a0a") or struct.unpack(">II", header[16:24]) != (1280, 720):
            print(f"A5 REAL LAYOUT VISUAL QA: FAIL image dimensions {name}", file=sys.stderr)
            return 1
    print("A5 REAL LAYOUT VISUAL QA: PASS (4 actual 1280x720 camera/world renders)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
