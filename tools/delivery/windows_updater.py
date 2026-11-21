#!/usr/bin/env python3
"""MyShelter Windows evergreen preview updater. Python 3.12+, standard library only."""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
import zipfile

REPO = "AndreyCokol/My_shelter"
API = "https://api.github.com/repos/" + REPO + "/releases?per_page=30"
TAG_PREFIX = "myshelter-preview-"
ZIP_NAME = "MyShelter-Windows-x64.zip"
MANIFEST_NAME = "manifest.json"
MAX_PACKAGE_BYTES = 512 * 1024 * 1024
MAX_MANIFEST_BYTES = 16384
HTTP_TIMEOUT = 15


class UpdateError(RuntimeError):
    pass


def _request(url: str):
    return urlopen(Request(url, headers={
        "User-Agent": "MyShelterUpdater/1.0",
        "Accept": "application/vnd.github+json" if url.startswith("https://api.github.com/") else "application/octet-stream",
    }), timeout=HTTP_TIMEOUT)


def _json_url(url: str, limit: int) -> object:
    with _request(url) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise UpdateError("Metadata exceeds size limit")
    return json.loads(data.decode("utf-8-sig"))


def _trusted_asset_url(url: str, tag: str, filename: str) -> bool:
    if not isinstance(url, str):
        return False
    parsed = urlsplit(url)
    return (parsed.scheme == "https" and parsed.hostname == "github.com"
            and parsed.username is None and parsed.password is None
            and parsed.port in (None, 443)
            and parsed.path == "/" + REPO + "/releases/download/" + tag + "/" + filename
            and not parsed.query and not parsed.fragment)


def _asset(assets: list, filename: str, tag: str) -> str:
    hits = [a.get("browser_download_url") for a in assets
            if isinstance(a, dict) and a.get("name") == filename]
    if len(hits) != 1 or not _trusted_asset_url(hits[0], tag, filename):
        raise UpdateError("Missing/unsafe release asset: " + filename)
    return hits[0]


def discover() -> tuple[dict, str]:
    """Only manually published prereleases with exact 40-character source SHA."""
    releases = _json_url(API, 2_000_000)
    if not isinstance(releases, list):
        raise UpdateError("Invalid GitHub release response")
    releases.sort(key=lambda r: str(r.get("published_at", "")) if isinstance(r, dict) else "", reverse=True)
    for release in releases:
        if not isinstance(release, dict) or release.get("draft") or release.get("prerelease") is not True:
            continue
        tag = release.get("tag_name")
        if not isinstance(tag, str) or not re.fullmatch(TAG_PREFIX + r"[0-9a-f]{40}", tag):
            continue
        assets = release.get("assets", [])
        if not isinstance(assets, list):
            continue
        manifest_url = _asset(assets, MANIFEST_NAME, tag)
        package_url = _asset(assets, ZIP_NAME, tag)
        manifest = _json_url(manifest_url, MAX_MANIFEST_BYTES)
        if not isinstance(manifest, dict):
            raise UpdateError("Invalid manifest")
        sha = tag[len(TAG_PREFIX):]
        valid = (manifest.get("schema") == 1
                 and manifest.get("application") == "MyShelter"
                 and manifest.get("channel") == "preview"
                 and manifest.get("source_sha") == sha
                 and manifest.get("package") == ZIP_NAME
                 and manifest.get("entrypoint") == "MyShelter.exe"
                 and isinstance(manifest.get("archive_sha256"), str)
                 and re.fullmatch(r"[0-9a-f]{64}", manifest["archive_sha256"])
                 and type(manifest.get("archive_size")) is int
                 and 100 <= manifest["archive_size"] <= MAX_PACKAGE_BYTES)
        if not valid:
            raise UpdateError("Manifest does not match release/tag")
        manifest["published_at"] = release.get("published_at") or ""
        return manifest, package_url
    raise UpdateError("No approved preview release found")


def load_state(root: Path) -> dict:
    path = root / "state.json"
    if not path.exists():
        return {}
    state = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(state, dict):
        raise UpdateError("Invalid local state file")
    return state


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    try:
        tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


@contextlib.contextmanager
def exclusive_lock(root: Path):
    root.mkdir(parents=True, exist_ok=True)
    lock = root / ".update.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        if time.time() - lock.stat().st_mtime <= 3600:
            raise UpdateError("Another update is already running")
        lock.unlink()
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.write(fd, str(os.getpid()).encode("ascii"))
        yield
    finally:
        os.close(fd)
        lock.unlink(missing_ok=True)


def _download(url: str, dest: Path, expected_size: int, expected_sha: str) -> None:
    digest = hashlib.sha256()
    actual = 0
    with _request(url) as source, dest.open("wb") as target:
        while True:
            block = source.read(1024 * 1024)
            if not block:
                break
            actual += len(block)
            if actual > MAX_PACKAGE_BYTES or actual > expected_size:
                raise UpdateError("Package exceeds declared size")
            target.write(block)
            digest.update(block)
    if actual != expected_size or digest.hexdigest() != expected_sha:
        raise UpdateError("Package size or SHA-256 mismatch")


def _extract_verified(package: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(package) as archive:
        entries = archive.infolist()
        names = [x.filename for x in entries]
        if len(entries) > 2 or len(set(names)) != len(names) or "MyShelter.exe" not in names:
            raise UpdateError("Unexpected ZIP files")
        if any(name not in {"MyShelter.exe", "README.txt"} for name in names):
            raise UpdateError("Unsafe ZIP path")
        if sum(e.file_size for e in entries) > MAX_PACKAGE_BYTES:
            raise UpdateError("Uncompressed package too large")
        for entry in entries:
            if entry.is_dir() or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise UpdateError("Symlink/directory not allowed")
            with archive.open(entry) as source, (target / entry.filename).open("wb") as dest:
                shutil.copyfileobj(source, dest, 1024 * 1024)
    with (target / "MyShelter.exe").open("rb") as binary:
        if binary.read(2) != b"MZ":
            raise UpdateError("Executable has no PE header")


def installed_exe(root: Path, sha: object) -> Path | None:
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        return None
    exe = root / "versions" / sha / "MyShelter.exe"
    return exe if exe.is_file() else None


def update(root: Path, force: bool = False) -> str:
    with exclusive_lock(root):
        state = load_state(root)
        if state.get("updates_paused") and not force:
            return "Updates paused after rollback (use update --force)"
        manifest, url = discover()
        sha = manifest["source_sha"]
        if state.get("active_sha") == sha and installed_exe(root, sha):
            return "Already up to date: " + sha[:12]
        if str(state.get("published_at", "")) > manifest["published_at"] and not force:
            return "Refused older release; current version retained"
        version = root / "versions" / sha
        if not installed_exe(root, sha):
            cache = root / "cache"
            cache.mkdir(parents=True, exist_ok=True)
            package = cache / (sha + ".part")
            staging = root / "versions" / (sha + ".staging")
            try:
                _download(url, package, manifest["archive_size"], manifest["archive_sha256"])
                if staging.exists():
                    shutil.rmtree(staging)
                _extract_verified(package, staging)
                if version.exists():
                    raise UpdateError("Existing version directory is incomplete")
                os.replace(staging, version)
            finally:
                package.unlink(missing_ok=True)
                if staging.exists():
                    shutil.rmtree(staging)
        previous = state.get("active_sha") if installed_exe(root, state.get("active_sha")) else state.get("previous_sha")
        atomic_json(root / "state.json", {
            "active_sha": sha, "previous_sha": previous if previous != sha else None,
            "channel": "preview", "published_at": manifest["published_at"],
            "updates_paused": False,
        })
        return "Installed preview: " + sha[:12]


def rollback(root: Path) -> str:
    with exclusive_lock(root):
        state = load_state(root)
        sha = state.get("previous_sha")
        if not installed_exe(root, sha):
            raise UpdateError("No previous installed version")
        atomic_json(root / "state.json", {
            **state, "active_sha": sha, "previous_sha": state.get("active_sha"),
            "updates_paused": True,
        })
        return "Rolled back and paused updates: " + sha[:12]


def launch(root: Path, game_args: list[str]) -> int:
    state = load_state(root)
    exe = installed_exe(root, state.get("active_sha"))
    if exe is None:
        try:
            print(update(root))
        except Exception as error:
            print("No installed version and update failed:", error, file=sys.stderr)
            return 2
        state = load_state(root)
        exe = installed_exe(root, state.get("active_sha"))
    else:
        if not state.get("updates_paused"):
            flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()),
                              "--root", str(root), "update"], cwd=str(root),
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, creationflags=flags)
    if exe is None:
        return 2
    subprocess.Popen([str(exe), *game_args], cwd=str(exe.parent))
    print("Launched:", exe)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="MyShelter local preview auto-updater")
    parser.add_argument("--root", type=Path, default=Path(os.getenv("LOCALAPPDATA", str(Path.home()))) / "MyShelter")
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("update", help="Check for published build")
    check.add_argument("--force", action="store_true", help="Resume updates after rollback")
    commands.add_parser("rollback", help="Return to prior installed build and pause auto-update")
    launch_parser = commands.add_parser("launch", help="Start local game immediately; update in background")
    launch_parser.add_argument("game_args", nargs="*")
    args = parser.parse_args(argv)
    try:
        if args.command == "launch":
            return launch(args.root, args.game_args)
        print(update(args.root, args.force) if args.command == "update" else rollback(args.root))
        return 0
    except Exception as error:
        print("MyShelter updater:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
