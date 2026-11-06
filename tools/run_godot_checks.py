#!/usr/bin/env python3
"""Bound Godot runs and reject script errors even if the engine exits zero."""
import os
import re
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
godot = os.environ.get('GODOT', 'godot')
commands = [
    ['--version'],
    ['--headless', '--path', '.', '--editor', '--import'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_core_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_campaign_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_router_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_event_tests.gd'],
    ['--headless', '--path', '.', '--quit-after', '3'],
]
for args in commands:
    try:
        run = subprocess.run([godot, *args], cwd=root, text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=45)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f'FAIL {args}: {exc}')
        sys.exit(1)
    print(run.stdout, end='')
    if args == ['--version'] and not run.stdout.strip().startswith('4.7.2.stable.'):
        print('FAIL: expected Godot 4.7.2 stable')
        sys.exit(1)
    if '--script' in args and not re.search(r'(CORE|CAMPAIGN|ROUTER|EVENT) TESTS: [1-9][0-9]* checks, 0 failures', run.stdout):
        print('FAIL: missing successful test completion marker')
        sys.exit(1)
    if run.returncode or any(marker in run.stdout for marker in ('SCRIPT ERROR:', 'ERROR:', 'WARNING: ObjectDB instances leaked')):
        sys.exit(1)
print('GODOT CHECKS: PASS')
