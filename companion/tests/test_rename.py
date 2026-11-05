"""Tests for carrying installs and data over from the pre-0.5.0 name (ForeverChronicaller)."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fcompanion as fc  # noqa: E402
from test_update import make_zip  # noqa: E402

OLD_SV = 'ForeverChronicallerDB = {\n["entries"] = {\n{\n["t"] = 1,\n["kind"] = "note",\n["text"] = "old",\n},\n},\n}\n'


class RenameTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.wow = self.root / "WoW Forever"
        (self.wow / "Interface" / "AddOns").mkdir(parents=True)
        p = mock.patch.object(fc, "config_dir", return_value=self.root / "cfg")
        p.start()
        self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def sv_dir(self, char="Chase"):
        d = self.wow / "WTF" / "Account" / "ACC" / "Forever" / char / "SavedVariables"
        d.mkdir(parents=True, exist_ok=True)
        return d

    def test_install_moves_old_folder_and_copies_saved_files(self):
        old_addon = self.wow / "Interface" / "AddOns" / fc.LEGACY_ADDON
        old_addon.mkdir()
        (old_addon / f"{fc.LEGACY_ADDON}.toc").write_text("## Version: 0.4.2\n")
        (self.sv_dir("Chase") / f"{fc.LEGACY_ADDON}.lua").write_text(OLD_SV)
        (self.sv_dir("Alt") / f"{fc.LEGACY_ADDON}.lua").write_text(OLD_SV)
        (self.sv_dir("Alt") / f"{fc.ADDON}.lua").write_text("ForeverChroniclerDB = {}\n")  # already migrated

        zip_path = self.root / "ForeverChronicler-0.5.0.zip"
        zip_path.write_bytes(make_zip("0.5.0"))
        logs = []
        fc.install_zip(zip_path, str(self.wow), logs.append)

        self.assertFalse(old_addon.exists(), "old addon folder would load next to the new one")
        self.assertTrue(any(p.name.startswith(fc.LEGACY_ADDON) for p in (self.root / "cfg" / "backups").iterdir()))
        self.assertTrue((self.wow / "Interface" / "AddOns" / fc.ADDON / f"{fc.ADDON}.toc").exists())
        chase = self.sv_dir("Chase")
        self.assertEqual((chase / f"{fc.ADDON}.lua").read_text(), OLD_SV, "copied for the addon to adopt")
        self.assertTrue((chase / f"{fc.LEGACY_ADDON}.lua").exists(), "original kept")
        self.assertEqual((self.sv_dir("Alt") / f"{fc.ADDON}.lua").read_text(), "ForeverChroniclerDB = {}\n",
                         "existing new file never overwritten")
        self.assertTrue(any("1 character" in line for line in logs))

    def test_migration_is_a_no_op_without_old_data(self):
        self.assertEqual(fc.migrate_legacy(str(self.wow), lambda _: None), 0)

    def test_watcher_reads_old_files_and_old_table_name(self):
        (self.sv_dir("Chase") / f"{fc.LEGACY_ADDON}.lua").write_text(OLD_SV)
        files = fc.saved_variable_files(str(self.wow))
        self.assertEqual([f.name for f in files], [f"{fc.LEGACY_ADDON}.lua"])
        data = fc.addon_data(fc.parse_saved_variables(OLD_SV))
        self.assertEqual(data["entries"][0]["text"], "old")
        # once the new file exists, only that one is used
        (self.sv_dir("Chase") / f"{fc.ADDON}.lua").write_text("ForeverChroniclerDB = {}\n")
        self.assertEqual([f.name for f in fc.saved_variable_files(str(self.wow))], [f"{fc.ADDON}.lua"])


class ConfigRenameTests(unittest.TestCase):
    def test_old_config_folder_and_repo_are_carried_over(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            old = base / fc.LEGACY_CONFIG_DIR
            old.mkdir()
            (old / "config.json").write_text(json.dumps({"github_repo": fc.LEGACY_REPO, "ntfy_topic": "abc"}))
            env = {"APPDATA": str(base)} if os.name == "nt" else {"XDG_CONFIG_HOME": str(base)}
            with mock.patch.dict(os.environ, env):
                d = fc.config_dir()
                self.assertEqual(d.name, "forever-chronicler")
                cfg = fc.load_config(d / "config.json")
            self.assertEqual(cfg["ntfy_topic"], "abc", "settings copied")
            self.assertEqual(cfg["github_repo"], fc.DEFAULT_REPO, "renamed repository")
            self.assertTrue((old / "config.json").exists(), "old folder kept")


if __name__ == "__main__":
    unittest.main()
