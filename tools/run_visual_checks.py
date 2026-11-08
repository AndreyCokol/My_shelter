#!/usr/bin/env python3
"""Render actual Godot scenes under Xvfb; a missing renderer is never a PASS."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import struct
import sys

root = Path(__file__).resolve().parents[1]
engine = os.environ.get('GODOT', 'godot')
xvfb = shutil.which('xvfb-run')
if not xvfb:
    sys.exit('VISUAL CHECKS: NOT_RUN; xvfb-run is unavailable')
environment = dict(os.environ, LIBGL_ALWAYS_SOFTWARE='1')
command = [xvfb, '-a', '-s', '-screen 0 2560x1440x24', engine, '--rendering-method', 'gl_compatibility',
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
for name in ['welcome', 'shelter', 'radial', 'inventory', 'farm', 'rest', 'residents', 'quests', 'shop', 'save', 'credits', 'workshop',
             'jobs', 'map', 'journal', 'new_confirm', 'hospital', 'city', 'hospital_door', 'stairs', 'house_door',
             'apartment', 'camp']:
    image = Path('/tmp/shelter-visual') / (name + '.png')
    if not image.is_file() or image.stat().st_size < 1000:
        sys.exit('VISUAL CHECKS: FAIL missing rendered scene ' + name)
# The base suite saves 23 actual 1280x720 PNGs; additional review
# checks all 13 modal panels, shelter and radial at real Full HD pixels.
for name in ['shelter', 'radial', 'inventory', 'farm', 'rest', 'residents',
             'quests', 'shop', 'save', 'credits', 'workshop', 'jobs',
             'map', 'journal', 'new_confirm']:
    image = Path('/tmp/shelter-visual') / (name + '_1080p.png')
    if not image.is_file() or image.stat().st_size < 1000:
        sys.exit('VISUAL CHECKS: FAIL missing Full HD image ' + name)
    with image.open('rb') as stream:
        header = stream.read(24)
    if header[:8] != bytes.fromhex('89504e470d0a1a0a'):
        sys.exit('VISUAL CHECKS: FAIL invalid PNG header ' + name)
    width, height = struct.unpack('>II', header[16:24])
    if (width, height) != (1920, 1080):
        sys.exit(f'VISUAL CHECKS: FAIL {name} has {width}x{height}, expected 1920x1080')
print('VISUAL CHECKS: 15 Full HD captures verified 1920x1080')
print('VISUAL CHECKS: PASS (actual software OpenGL frames, not mockups)')
