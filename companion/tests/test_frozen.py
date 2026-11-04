"""Standalone-program behaviour (PyInstaller build), simulated."""

import io
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fcompanion as fc  # noqa: E402
from test_update import make_zip  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


class FrozenTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.embedded = self.root / "_MEI123"
        self.embedded.mkdir()
        (self.embedded / "ForeverChronicaller-0.3.1.zip").write_bytes(make_zip("0.3.1"))
        self.wow = self.root / "WoW Forever"
        self.wow.mkdir()
        (self.wow / "Wow.exe").write_bytes(b"")
        for name, value in (("FROZEN", True), ("game_running", lambda: False),
                            ("config_dir", lambda: self.root / "cfg"), ("find_wow_dirs", lambda roots=None: [])):
            p = mock.patch.object(fc, name, value)
            p.start()
            self.addCleanup(p.stop)
        for name, value in (("_MEIPASS", str(self.embedded)), ("executable", str(self.root / "ForeverChronicaller-Installer.exe"))):
            p = mock.patch.object(fc.sys, name, value, create=True)
            p.start()
            self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def test_embedded_zip_is_found(self):
        self.assertEqual(fc.bundled_zip().name, "ForeverChronicaller-0.3.1.zip")

    def test_double_click_installs_and_waits_for_enter(self):
        answers = iter([str(self.wow), ""])  # folder prompt, then "Press Enter to close"
        prompts = []

        def fake_input(prompt=""):
            prompts.append(prompt)
            return next(answers)
        out = io.StringIO()
        with mock.patch("builtins.input", fake_input), mock.patch("sys.stdout", out):
            code = fc.main([])
        self.assertEqual(code, 0, out.getvalue())
        self.assertEqual(fc.installed_version(str(self.wow)), "0.3.1")
        self.assertIn("Press Enter to close", prompts[-1])
        self.assertIn("ForeverChronicaller-Installer.exe setup", out.getvalue().replace("./", ""))

    def test_double_click_error_is_shown_not_raised(self):
        out = io.StringIO()
        def boom(cfg, args):
            raise RuntimeError("boom")
        with mock.patch.dict(fc.COMMANDS, {"install": boom}), \
             mock.patch("builtins.input", lambda p="": ""), mock.patch("sys.stdout", out):
            code = fc.main([])
        self.assertEqual(code, 1)
        self.assertIn("Something went wrong: RuntimeError: boom", out.getvalue())

    def test_command_line_use_does_not_pause(self):
        with mock.patch("builtins.input", side_effect=AssertionError("should not prompt")), \
             mock.patch("sys.stdout", io.StringIO()):
            with self.assertRaises(SystemExit):
                fc.main(["--version"])


class VersionTest(unittest.TestCase):
    def test_companion_version_matches_toc(self):
        toc = (REPO / "ForeverChronicaller.toc").read_text(encoding="utf-8")
        toc_version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
        self.assertEqual(fc.VERSION, toc_version, "bump VERSION in companion/fcompanion.py together with the .toc")

    def test_default_repo(self):
        self.assertEqual(fc.default_config()["github_repo"], "SaffronG/ForeverChronicaller")


if __name__ == "__main__":
    unittest.main()
