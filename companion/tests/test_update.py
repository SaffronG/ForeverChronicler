"""Tests for install/update (no network: GitHub is faked)."""

import io
import json
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fcompanion as fc  # noqa: E402


def make_zip(version="0.3.0", extra=None, toc=True):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        if toc:
            zf.writestr("ForeverChronicler/ForeverChronicler.toc", f"## Interface: 16001\n## Version: {version}\n\nCore.lua\n")
        zf.writestr("ForeverChronicler/Core.lua", f"-- core {version}\n")
        for name, data in (extra or {}).items():
            zf.writestr(name, data)
    return buf.getvalue()


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.wow = self.root / "WoW"
        (self.wow / "Interface" / "AddOns").mkdir(parents=True)
        self.cfg = fc.default_config()
        self.cfg.update(wow_path=str(self.wow), github_repo="chase/ForeverChronicler")
        self.logs = []
        # keep backups out of the real config folder
        patcher = mock.patch.object(fc, "config_dir", return_value=self.root / "cfg")
        patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def write_zip(self, data, name="addon.zip"):
        p = self.root / name
        p.write_bytes(data)
        return p

    def fake_github(self, version="0.3.0", zip_bytes=None, assets=None):
        zip_bytes = zip_bytes or make_zip(version)
        release = {"tag_name": f"v{version}", "assets": assets if assets is not None else [
            {"name": f"ForeverChronicler-Companion-{version}.zip", "browser_download_url": "https://github.com/x/companion.zip"},
            {"name": f"ForeverChronicler-{version}.zip", "browser_download_url": "https://github.com/x/addon.zip"},
        ]}

        def fetch(url):
            if url.endswith("/releases/latest"):
                return json.dumps(release).encode()
            if url == "https://github.com/x/addon.zip":
                return zip_bytes
            raise AssertionError("unexpected url " + url)
        return fetch

    def test_fresh_install_from_zip(self):
        v = fc.install_zip(self.write_zip(make_zip("0.2.0")), str(self.wow), self.logs.append)
        self.assertEqual(v, "0.2.0")
        self.assertEqual(fc.installed_version(str(self.wow)), "0.2.0")

    def test_update_replaces_and_backs_up(self):
        fc.install_zip(self.write_zip(make_zip("0.2.0")), str(self.wow), self.logs.append)
        installed = fc.update(self.cfg, fetch=self.fake_github("0.3.0"), log=self.logs.append, running=lambda: False)
        self.assertTrue(installed)
        self.assertEqual(fc.installed_version(str(self.wow)), "0.3.0")
        backups = list((self.root / "cfg" / "backups").iterdir())
        self.assertEqual(len(backups), 1)
        self.assertIn("0.2.0", backups[0].name)
        self.assertTrue((backups[0] / "ForeverChronicler.toc").exists())

    def test_up_to_date_and_check_only(self):
        fc.install_zip(self.write_zip(make_zip("0.3.0")), str(self.wow), self.logs.append)
        self.assertFalse(fc.update(self.cfg, fetch=self.fake_github("0.3.0"), log=self.logs.append, running=lambda: False))
        self.assertIn("up to date", self.logs[-1])
        self.assertFalse(fc.update(self.cfg, fetch=self.fake_github("0.10.0"), check_only=True, log=self.logs.append))
        self.assertEqual(fc.installed_version(str(self.wow)), "0.3.0")

    def test_refuses_while_game_running(self):
        self.assertFalse(fc.update(self.cfg, fetch=self.fake_github("0.3.0"), log=self.logs.append, running=lambda: True))
        self.assertIsNone(fc.installed_version(str(self.wow)))
        self.assertTrue(fc.update(self.cfg, fetch=self.fake_github("0.3.0"), force=True, log=self.logs.append, running=lambda: True))

    def test_rejects_dangerous_or_wrong_zips(self):
        cases = {
            "zip slip": make_zip(extra={"ForeverChronicler/../../evil.lua": "x"}),
            "absolute": make_zip(extra={"/etc/evil": "x"}),
            "other folder": make_zip(extra={"OtherAddon/x.lua": "x"}),
            "no toc": make_zip(toc=False),
        }
        for label, data in cases.items():
            with self.subTest(label):
                with self.assertRaises(fc.UpdateError):
                    fc.install_zip(self.write_zip(data), str(self.wow), self.logs.append)
        with self.assertRaises(fc.UpdateError):
            fc.install_zip(self.write_zip(b"not a zip"), str(self.wow), self.logs.append)
        self.assertFalse((self.root / "evil.lua").exists())

    def test_release_problems(self):
        with self.assertRaises(fc.UpdateError):
            fc.latest_release("", self.fake_github())
        with self.assertRaises(fc.UpdateError):
            fc.latest_release("a/b", self.fake_github(assets=[]))
        bad = [{"name": "ForeverChronicler-0.3.0.zip", "browser_download_url": "https://evil.example/addon.zip"}]
        with self.assertRaises(fc.UpdateError):
            fc.latest_release("a/b", self.fake_github(assets=bad))

    def test_version_compare(self):
        self.assertLess(fc.version_tuple("0.9.0"), fc.version_tuple("0.10.0"))

    def test_game_detection_patterns(self):
        with mock.patch.object(fc.subprocess, "run") as run, mock.patch.object(fc.os, "name", "posix"):
            run.return_value = mock.Mock(stdout="bash\nWow.exe\npython3\n")
            self.assertTrue(fc.game_running())
            run.return_value = mock.Mock(stdout="bash\nvim\n")  # e.g. editing ~/WoW/Wow.exe.txt
            self.assertFalse(fc.game_running())
        with mock.patch.object(fc.subprocess, "run") as run, mock.patch.object(fc.os, "name", "nt"):
            run.return_value = mock.Mock(stdout='"WowClassic.exe","1234","Console","1","2,000 K"\n"explorer.exe","1","Console","1","1 K"\n')
            self.assertTrue(fc.game_running())
            run.return_value = mock.Mock(stdout='"notepad.exe","1234","Console","1","2,000 K"\n')
            self.assertFalse(fc.game_running())


class PackagedZipTest(unittest.TestCase):
    """The zip built by scripts/package.sh must pass the installer's checks."""

    def test_real_package(self):
        repo = Path(__file__).resolve().parents[2]
        dist = sorted((repo / "dist").glob("ForeverChronicler-[0-9]*.zip"))
        if not dist:
            self.skipTest("run scripts/package.sh first")
        version = fc.check_zip(dist[-1])
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")


if __name__ == "__main__":
    unittest.main()
