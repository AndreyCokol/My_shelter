#!/usr/bin/env python3
"""A5: execute native Godot v4/v5-to-3D layout bridge regression tests."""
from __future__ import annotations

import re
import sys

from run_a5_dual_view_qa import checked_run

SUITE = "game/tests/world/run_dual_view_layout_bridge_tests.gd"
MARKER = re.compile(r"A5 LAYOUT BRIDGE TESTS: ([1-9][0-9]*) checks, 0 failures")


def main() -> int:
    try:
        version = checked_run(["--version"], 15).strip()
        if not version.startswith("4.7.2.stable."):
            raise RuntimeError(f"Wrong Godot version: {version!r}")
        checked_run(["--headless", "--path", ".", "--editor", "--import"], 90)
        output = checked_run(["--headless", "--path", ".", "--script", SUITE], 120)
        match = MARKER.search(output)
        if not match:
            raise RuntimeError("Layout bridge test did not complete with 0 failures")
        print(f"A5 LAYOUT BRIDGE QA: PASS ({match.group(1)} checks in Godot {version})")
        return 0
    except RuntimeError as error:
        print(f"A5 LAYOUT BRIDGE QA: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
