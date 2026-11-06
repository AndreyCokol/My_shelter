#!/usr/bin/env python3
"""Install only the selected Kibyra PNGs for this game; never publish raw packs."""
import argparse
import hashlib
import http.cookiejar
import json
from pathlib import Path
import re
import struct
import urllib.parse
import urllib.request
import zipfile
import io

ROOT = Path(__file__).resolve().parents[1]
PAGE = 'https://kibyra.itch.io/free-medieval-fantasy-ui-pack'
ARCHIVE_SHA = 'cb9de5447044ad68f71133c64ac7a8aea9f1297c9e71d7142564e0b5523db16b'
PREFIX = 'Free_Medieval_Fantasy_UI_Pack/'
SELECTED = {
    'button_frame': 'UI Icons 2/icon12.png',
    'focus_frame': 'UI Icons 2/icon13.png',
    'panel_frame': 'UI Icons 2/icon39.png',
    'heart': 'UI Icons 3/icon1.png',
    'coin': 'UI Icons 3/icon7.png',
    'inventory': 'UI Icons 3/icon8.png',
    'sword': 'UI Icons 3/icon9.png',
    'quests': 'UI Icons 3/icon58.png',
    'menu': 'UI Icons 3/icon35.png',
    'farm': 'UI Icons 3/icon56.png',
    'rest': 'UI Icons 3/icon59.png',
    'residents': 'UI Icons 3/icon36.png',
    'save': 'UI Icons 3/icon51.png',
    'shelter': 'UI Icons 3/icon34.png',
    'hero_xp': 'UI Icons 3/icon25.png',
    'shelter_xp': 'UI Icons 3/icon62.png',
    'back': 'UI Icons/icon6.png',
    'accept': 'UI Icons/icon8.png',
}


def fetch() -> bytes:
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    opener.addheaders = [('User-Agent', 'Mozilla/5.0')]
    def read(url, data=None, referer=PAGE):
        request = urllib.request.Request(url, data=data, headers={
            'Referer': referer, 'X-Requested-With': 'XMLHttpRequest'})
        with opener.open(request, timeout=40) as response:
            result = response.read(16 * 1024 * 1024 + 1)
        if len(result) > 16 * 1024 * 1024:
            raise ValueError('Download exceeds the expected pack size')
        return result
    def csrf(page):
        match = re.search(r'name="csrf_token" value="([^"]+)"', page)
        if not match:
            raise ValueError('Download form changed: CSRF field missing')
        return urllib.parse.urlencode({'csrf_token': match.group(1)}).encode()
    page = read(PAGE).decode('utf-8')
    if not re.search(r'"actual_price"\s*:\s*0\b', page):
        raise ValueError('Pack is not currently offered free; no purchase attempted')
    link = json.loads(read(PAGE + '/download_url', csrf(page)))['url']
    page = read(link).decode('utf-8')
    if 'claim_to_download_box' in page:
        raise ValueError('This download requires an itch.io account; supply your downloaded archive')
    match = re.search(r'data-upload_id="(\d+)"', page)
    if not match:
        raise ValueError('No downloadable file found')
    link = json.loads(read(PAGE + '/file/' + match.group(1), csrf(page), link))['url']
    return read(link)


def install(data: bytes, destination: Path | None = None) -> dict:
    digest = hashlib.sha256(data).hexdigest()
    if digest != ARCHIVE_SHA:
        raise ValueError('Archive differs from the reviewed version; review files/license before updating SHA')
    destination = destination or ROOT / 'game/assets/vendor/kibyra_ui'
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if sum(item.file_size for item in archive.infolist()) > 32 * 1024 * 1024:
            raise ValueError('Uncompressed archive exceeds expected size')
        if archive.testzip() is not None:
            raise ValueError('ZIP CRC validation failed')
        readme = archive.read(PREFIX + 'Readme.txt').decode('utf-8-sig')
        for term in ['Free for personal and commercial use', 'files as-is is not allowed', 'Created by: Kibyra']:
            if term not in readme:
                raise ValueError('Reviewed usage terms not found')
        files = {}
        prepared = {}
        for role, source in SELECTED.items():
            png = archive.read(PREFIX + source)
            if png[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', png[16:24]) != (32, 32):
                raise ValueError('Unexpected PNG format or size: ' + source)
            prepared[role + '.png'] = png
            files[role] = {'file': role + '.png', 'source': source,
                           'sha256': hashlib.sha256(png).hexdigest(), 'size': [32, 32]}
        # Validate every input before writing the selected game resources.
        destination.mkdir(parents=True, exist_ok=True)
        for name, png in prepared.items():
            (destination / name).write_bytes(png)
        (destination / 'CREDITS.txt').write_text(readme, encoding='utf-8')
        manifest = {'pack': 'Kibyra Free Medieval Fantasy UI Pack', 'source': PAGE,
                    'archive_sha256': digest, 'files': files}
        (destination / 'installed.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--ui-archive', type=Path, help='Archive obtained from the author')
    group.add_argument('--download-ui', action='store_true', help='Use the author\'s anonymous free download flow')
    args = parser.parse_args()
    data = args.ui_archive.read_bytes() if args.ui_archive else fetch()
    result = install(data)
    print('UI ASSETS: installed %d reviewed PNGs from Kibyra (not tracked by git)' % len(result['files']))

if __name__ == '__main__':
    main()
