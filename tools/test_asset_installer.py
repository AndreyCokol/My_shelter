#!/usr/bin/env python3
"""Exercise installation boundaries without uploading the licensed pack."""
import importlib.util
from pathlib import Path
import tempfile
import sys

spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install_ui_assets.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def run(archive: Path):
    data = archive.read_bytes()
    with tempfile.TemporaryDirectory() as work:
        target = Path(work) / 'vendor'
        try:
            module.install(b'bad archive', target)
            raise AssertionError('corrupt archive accepted')
        except ValueError:
            assert not target.exists(), 'failed validation wrote files'
        result = module.install(data, target)
        assert len(result['files']) == 18
        assert len(list(target.glob('*.png'))) == 18
        assert not list(target.glob('*.zip'))
        assert 'Kibyra' in (target / 'CREDITS.txt').read_text()
        # Reinstallation is deterministic and preserves selected source bytes.
        before = {p.name: p.read_bytes() for p in target.iterdir()}
        module.install(data, target)
        assert before == {p.name: p.read_bytes() for p in target.iterdir()}
    print('ASSET INSTALLER: corruption/write barrier, 18 PNG selection, attribution, deterministic reinstall PASS')

if __name__ == '__main__':
    run(Path(sys.argv[1]))
