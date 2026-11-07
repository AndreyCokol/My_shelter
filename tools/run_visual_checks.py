#!/usr/bin/env python3
"""Render actual Godot scenes under Xvfb; a missing renderer is never a PASS."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
engine = os.environ.get('GODOT', 'godot')
xvfb = shutil.which('xvfb-run')
if not xvfb:
    sys.exit('VISUAL CHECKS: NOT_RUN; xvfb-run is unavailable')
environment = dict(os.environ, LIBGL_ALWAYS_SOFTWARE='1')
command = [xvfb, '-a', engine, '--rendering-method', 'gl_compatibility',
           '--audio-driver', 'Dummy', '--path', '.', '--max-fps', '60',
           '--script', 'game/tests/e2e/run_visual_tests.gd']
try:
    result = subprocess.run(command, cwd=root, env=environment, text=True,
                            encoding='utf-8', errors='replace', stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=75)
except (OSError, subprocess.TimeoutExpired) as exc:
    sys.exit('VISUAL CHECKS: FAIL ' + str(exc))
print(result.stdout)
if result.returncode or not re.search(r'VISUAL TESTS: [1-9][0-9]* checks, 0 failures', result.stdout):
    sys.exit(1)
if any(item in result.stdout for item in ['SCRIPT ERROR:', 'ERROR:', 'instances leaked']):
    sys.exit(1)
for name in ['welcome', 'shelter', 'inventory', 'farm', 'rest', 'residents', 'quests', 'shop', 'save', 'credits', 'workshop',
             'jobs', 'map', 'city', 'camp']:
    image = Path('/tmp/shelter-visual') / (name + '.png')
    if not image.is_file() or image.stat().st_size < 1000:
        sys.exit('VISUAL CHECKS: FAIL missing rendered scene ' + name)
print('VISUAL CHECKS: PASS (actual software OpenGL frames, not mockups)')
