"""Fast, offline regression checks; no internet and no GitHub credentials."""
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile

import windows_updater as u


def fake_package(paths=None):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name, content in (paths or {"MyShelter.exe": b"MZ" + b"game" * 100}).items():
            z.writestr(name, content)
    return output.getvalue()


class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.sha = "a" * 40
        self.archive = fake_package()
        self.manifest = {
            "schema": 1, "application": "MyShelter", "channel": "preview",
            "source_sha": self.sha, "package": u.ZIP_NAME,
            "entrypoint": "MyShelter.exe",
            "archive_sha256": __import__("hashlib").sha256(self.archive).hexdigest(),
            "archive_size": len(self.archive), "published_at": "2026-11-21T14:00:00Z",
        }

    def tearDown(self):
        self.temp.cleanup()

    def fake_download(self, _url, dest, expected_size, expected_sha):
        self.assertEqual(expected_size, len(self.archive))
        self.assertEqual(expected_sha, self.manifest["archive_sha256"])
        dest.write_bytes(self.archive)

    def test_strict_asset_url_and_release_tag(self):
        tag = u.TAG_PREFIX + self.sha
        url = f"https://github.com/{u.REPO}/releases/download/{tag}/{u.ZIP_NAME}"
        self.assertTrue(u._trusted_asset_url(url, tag, u.ZIP_NAME))
        self.assertFalse(u._trusted_asset_url(url.replace("github.com", "evil.example"), tag, u.ZIP_NAME))
        self.assertFalse(u._trusted_asset_url(url + "?redirect=1", tag, u.ZIP_NAME))
        releases = [{
            "tag_name": tag, "prerelease": True, "draft": False,
            "published_at": "2026-11-21T14:00:00Z",
            "assets": [{"name": u.ZIP_NAME, "browser_download_url": url},
                       {"name": u.MANIFEST_NAME, "browser_download_url": url.replace(u.ZIP_NAME, u.MANIFEST_NAME)}],
        }]
        def answer(where, _limit):
            return releases if where == u.API else dict(self.manifest)
        with mock.patch.object(u, "_json_url", side_effect=answer):
            manifest, chosen_url = u.discover()
        self.assertEqual(manifest["source_sha"], self.sha)
        self.assertEqual(chosen_url, url)

    def test_verified_install_and_same_sha_idempotent(self):
        with mock.patch.object(u, "discover", return_value=(self.manifest, "https://example.invalid/fake")), \
             mock.patch.object(u, "_download", side_effect=self.fake_download):
            self.assertIn("Installed preview", u.update(self.root))
            self.assertIn("up to date", u.update(self.root))
        self.assertEqual(u.load_state(self.root)["active_sha"], self.sha)
        self.assertEqual(u.installed_exe(self.root, self.sha).read_bytes()[:2], b"MZ")

    def test_corrupt_archive_does_not_replace_existing(self):
        oldsha = "b" * 40
        target = self.root / "versions" / oldsha
        target.mkdir(parents=True)
        (target / "MyShelter.exe").write_bytes(b"MZold")
        u.atomic_json(self.root / "state.json", {"active_sha": oldsha, "previous_sha": None})
        def broken(_url, dest, _size, _hash):
            dest.write_bytes(b"corrupted")
            raise u.UpdateError("Package SHA-256 mismatch")
        with mock.patch.object(u, "discover", return_value=(self.manifest, "https://example.invalid/fake")), \
             mock.patch.object(u, "_download", side_effect=broken):
            with self.assertRaises(u.UpdateError):
                u.update(self.root)
        self.assertEqual(u.load_state(self.root)["active_sha"], oldsha)
        self.assertTrue((target / "MyShelter.exe").exists())

    def test_zip_path_traversal_and_duplicate_rejected(self):
        for members in [
            {"../evil.exe": b"MZbad", "MyShelter.exe": b"MZokay"},
            {"subdir/extra.bin": b"bad", "MyShelter.exe": b"MZokay"},
            {"MyShelter.exe": b"not-an-exe"},
        ]:
            package = self.root / "payload.zip"
            package.write_bytes(fake_package(members))
            dest = self.root / ("test-" + str(len(list(self.root.iterdir()))))
            with self.assertRaises(u.UpdateError):
                u._extract_verified(package, dest)
            self.assertFalse((self.root / "evil.exe").exists())
            package.unlink()

    def test_rollback_preserves_both_versions_and_pauses(self):
        oldsha = "b" * 40
        for sha in (self.sha, oldsha):
            folder = self.root / "versions" / sha
            folder.mkdir(parents=True)
            (folder / "MyShelter.exe").write_bytes(b"MZtest")
        u.atomic_json(self.root / "state.json", {
            "active_sha": self.sha, "previous_sha": oldsha, "updates_paused": False,
        })
        self.assertIn("Rolled back", u.rollback(self.root))
        self.assertEqual(u.load_state(self.root)["active_sha"], oldsha)
        self.assertTrue(u.load_state(self.root)["updates_paused"])
        with mock.patch.object(u, "discover", side_effect=AssertionError("Must stay offline")):
            self.assertIn("paused", u.update(self.root))

    def test_manifest_mismatch_fails_closed(self):
        tag = u.TAG_PREFIX + self.sha
        base = f"https://github.com/{u.REPO}/releases/download/{tag}/"
        releases = [{
            "tag_name": tag, "prerelease": True, "draft": False,
            "published_at": "2026-11-21T14:00:00Z",
            "assets": [{"name": u.ZIP_NAME, "browser_download_url": base + u.ZIP_NAME},
                       {"name": u.MANIFEST_NAME, "browser_download_url": base + u.MANIFEST_NAME}],
        }]
        def tampered(where, _limit):
            if where == u.API:
                return releases
            return dict(self.manifest, source_sha="c" * 40)
        with mock.patch.object(u, "_json_url", side_effect=tampered):
            with self.assertRaises(u.UpdateError):
                u.discover()


if __name__ == "__main__":
    unittest.main()
