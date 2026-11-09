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
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_checkpoint_crash_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_save_failure_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_save_compat_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_campaign_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_router_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_event_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_calendar_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_performance_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_receipt_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_ruleset_compat_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/core/run_save_profile_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_soak_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_gameplay_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_food_catalog_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_resident_work_food_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_campaign_longterm_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_edge_tests.gd'],
    ['--headless', '--max-fps', '60', '--path', '.', '--script', 'game/tests/e2e/run_runtime_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_combat_equipment_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_ui_content_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_asset_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_world_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_shelter_access_tests.gd'],
    ['--headless', '--path', '.', '--script', 'game/tests/e2e/run_layout_fingerprint_tests.gd'],
    ['--headless', '--path', '.', '--quit-after', '3'],
]
for args in commands:
    try:
        run = subprocess.run([godot, *args], cwd=root, text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT,
                             timeout=150 if 'run_soak_tests.gd' in args else 45)
    except subprocess.TimeoutExpired as exc:
        # Preserve the partial Godot test trace to locate the exact hanging step.
        captured = exc.stdout or b''
        if isinstance(captured, bytes):
            captured = captured.decode('utf-8', 'replace')
        print(captured[-14000:], end='', flush=True)
        print(f'FAIL {args}: {exc}', flush=True)
        sys.exit(1)
    except OSError as exc:
        print(f'FAIL {args}: {exc}', flush=True)
        sys.exit(1)
    print(run.stdout, end='')
    if args == ['--version'] and not run.stdout.strip().startswith('4.7.2.stable.'):
        print('FAIL: expected Godot 4.7.2 stable')
        sys.exit(1)
    if '--script' in args and not re.search(r'(CORE|CHECKPOINT CRASH|SAVE FAILURE|SAVE COMPAT|CAMPAIGN|ROUTER|EVENT|CALENDAR|PERFORMANCE|RECEIPT|RULESET|SAVE PROFILE|SOAK|GAMEPLAY|FOOD CATALOG|RESIDENT WORK FOOD|CAMPAIGN LONGTERM|EDGE|RUNTIME|COMBAT|UI CONTENT|ASSET|WORLD|SHELTER ACCESS|LAYOUT) TESTS: [1-9][0-9]* checks, 0 failures', run.stdout):
        print('FAIL: missing successful test completion marker')
        sys.exit(1)
    if run.returncode or any(marker in run.stdout for marker in ('SCRIPT ERROR:', 'ERROR:', 'WARNING: ObjectDB instances leaked')):
        sys.exit(1)
print('GODOT CHECKS: PASS')
