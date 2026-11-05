"""Tests for WoW folder detection and the install command."""

import io
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fcompanion as fc  # noqa: E402
from test_update import make_zip  # noqa: E402


class DetectTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def fake_client(self, *parts, exe="Wow.exe"):
        d = self.root.joinpath(*parts)
        d.mkdir(parents=True)
        (d / exe).write_bytes(b"")
        return d

    def test_finds_clients_and_flavour_folders(self):
        a = self.fake_client("World of Warcraft", "_retail_")
        b = self.fake_client("WoW Forever")
        self.fake_client("Some Other Game", exe="Game.exe")
        (self.root / "World of Warcraft" / "_ptr_").mkdir()  # no exe: ignored
        found = fc.find_wow_dirs([self.root])
        self.assertEqual(sorted(found), sorted([a, b]))

    def test_looks_like_wow(self):
        d = self.fake_client("WoW Forever")
        self.assertTrue(fc.looks_like_wow(d))
        self.assertFalse(fc.looks_like_wow(self.root))
        (self.root / "WTF").mkdir()
        self.assertTrue(fc.looks_like_wow(self.root))

    def test_missing_roots_are_fine(self):
        self.assertEqual(fc.find_wow_dirs([self.root / "nope"]), [])


class InstallCommandTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.wow = self.root / "WoW Forever"
        self.wow.mkdir()
        (self.wow / "Wow.exe").write_bytes(b"")
        self.zip = self.root / "ForeverChronicler-0.2.0.zip"
        self.zip.write_bytes(make_zip("0.2.0"))
        for target, value in ((fc, "config_dir"),):
            p = mock.patch.object(target, value, return_value=self.root / "cfg")
            p.start()
            self.addCleanup(p.stop)
        p = mock.patch.object(fc, "game_running", return_value=False)
        p.start()
        self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def run_install(self, *argv):
        args = fc.build_parser().parse_args(["install", *argv])
        out = io.StringIO()
        with mock.patch("sys.stdout", out):
            code = fc.cmd_install(fc.default_config(), args)
        return code, out.getvalue()

    def test_install_with_flags_saves_config(self):
        code, out = self.run_install("--wow", str(self.wow), "--zip", str(self.zip), "--yes", "--accept-terms")
        self.assertEqual(code, 0, out)
        self.assertEqual(fc.installed_version(str(self.wow)), "0.2.0")
        self.assertEqual(fc.load_config(self.root / "cfg" / "config.json")["wow_path"], str(self.wow))
        self.assertIn("type /chron", out)

    def test_install_uses_bundled_zip_and_detected_folder(self):
        with mock.patch.object(fc, "bundled_zip", return_value=self.zip), \
             mock.patch.object(fc, "find_wow_dirs", return_value=[self.wow]):
            code, out = self.run_install("--yes", "--accept-terms")
        self.assertEqual(code, 0, out)
        self.assertEqual(fc.installed_version(str(self.wow)), "0.2.0")

    def test_refuses_non_wow_folder_without_confirmation(self):
        code, out = self.run_install("--wow", str(self.root / "cfg-not-wow"), "--zip", str(self.zip), "--yes", "--accept-terms")
        self.assertEqual(code, 1)
        self.assertIn("doesn't look like a WoW folder", out)

    def test_refuses_while_running(self):
        with mock.patch.object(fc, "game_running", return_value=True):
            code, out = self.run_install("--wow", str(self.wow), "--zip", str(self.zip), "--yes", "--accept-terms")
        self.assertEqual(code, 1)
        self.assertIsNone(fc.installed_version(str(self.wow)))


class TermsTests(InstallCommandTests):
    """The disclaimer must be agreed to explicitly before anything is installed."""

    def run_install_answering(self, answers, *argv):
        answers = iter(answers)
        args = fc.build_parser().parse_args(["install", *argv])
        out = io.StringIO()
        cfg = fc.load_config(self.root / "cfg" / "config.json")
        with mock.patch("builtins.input", lambda p="": next(answers)), mock.patch("sys.stdout", out):
            code = fc.cmd_install(cfg, args)
        return code, out.getvalue()

    def test_disclaimer_shown_and_decline_installs_nothing(self):
        code, out = self.run_install_answering(["no"], "--wow", str(self.wow), "--zip", str(self.zip))
        self.assertEqual(code, 1)
        for words in ("PERMISSIONS", "DATA", "RISKS", "No telemetry", "backed up", "PRIVACY.md"):
            self.assertIn(words, out)
        self.assertIn("Nothing was installed", out)
        self.assertIsNone(fc.installed_version(str(self.wow)))

    def test_yes_alone_does_not_accept(self):
        code, out = self.run_install("--wow", str(self.wow), "--zip", str(self.zip), "--yes")
        self.assertEqual(code, 1)
        self.assertIn("--accept-terms", out)
        self.assertIsNone(fc.installed_version(str(self.wow)))

    def test_agreement_is_remembered(self):
        code, _ = self.run_install_answering(["yes", ""], "--wow", str(self.wow), "--zip", str(self.zip))
        self.assertEqual(code, 0)
        saved = fc.load_config(self.root / "cfg" / "config.json")
        self.assertEqual(saved["accepted_terms"], fc.TERMS_VERSION)
        self.assertGreater(saved["accepted_terms_at"], 0)
        # second run: no disclaimer, no question
        code, out = self.run_install_answering([], "--wow", str(self.wow), "--zip", str(self.zip))
        self.assertEqual(code, 0)
        self.assertNotIn("RISKS", out)

    def test_privacy_command(self):
        out = io.StringIO()
        with mock.patch("sys.stdout", out):
            fc.main(["privacy"])
        self.assertIn("RISKS", out.getvalue())
        self.assertIn("PRIVACY.md", out.getvalue())


class BundleTest(unittest.TestCase):
    def test_installer_bundle_contents(self):
        repo = Path(__file__).resolve().parents[2]
        bundles = sorted((repo / "dist").glob("ForeverChronicler-Installer-*.zip"))
        if not bundles:
            self.skipTest("run scripts/package.sh first")
        names = set(zipfile.ZipFile(bundles[-1]).namelist())
        for f in ("fcompanion.py", "Install.bat", "install.sh", "README.md"):
            self.assertIn(f"ForeverChronicler-Installer/{f}", names)
        self.assertTrue(any(n.startswith("ForeverChronicler-Installer/ForeverChronicler-") and n.endswith(".zip")
                            and "Installer-" not in n.split("/")[-1] for n in names))


if __name__ == "__main__":
    unittest.main()
