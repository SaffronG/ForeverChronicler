"""Tests for the companion app: python3 -m unittest discover -s companion/tests"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fcompanion as fc  # noqa: E402

# Written the way WoW writes SavedVariables (comments, escapes, nested tables).
SAMPLE = r'''
ForeverChronicallerDB = {
["version"] = 1,
["entries"] = {
{
["t"] = 1762200000,
["kind"] = "start",
["text"] = "The chronicle of Chase begins in Elwynn Forest.",
["zone"] = "Elwynn Forest",
["level"] = 1,
}, -- [1]
{
["t"] = 1762203600,
["kind"] = "level",
["text"] = "|cff00ff00Reached level 2!|r",
["zone"] = "Elwynn Forest",
["level"] = 2,
}, -- [2]
{
["t"] = 1762203700,
["kind"] = "note",
["text"] = "|cffdddddd\"Met a gnome \\ said \"hi\"\nnew line\226\156\147|r",
["level"] = 2,
}, -- [3]
},
["goals"] = {
{
["kind"] = "location",
["target"] = {
["mapID"] = 1429,
["x"] = 0.452,
["y"] = -0.5e-1,
["armed"] = false,
},
["done"] = true,
}, -- [1]
},
["zones"] = {
["Elwynn Forest"] = 1762200000,
},
["settings"] = {
["chronicle"] = {
["quest"] = false,
},
},
}
OtherGlobal = nil
'''


class FakeSender:
    def __init__(self):
        self.requests = []

    def __call__(self, req):
        self.requests.append(req)


class ParserTests(unittest.TestCase):
    def test_parses_wow_saved_variables(self):
        data = fc.parse_saved_variables(SAMPLE)
        db = data["ForeverChronicallerDB"]
        self.assertIsNone(data["OtherGlobal"])
        self.assertEqual(len(db["entries"]), 3)
        self.assertEqual(db["entries"][0]["t"], 1762200000)
        self.assertEqual(db["entries"][2]["text"], '|cffdddddd"Met a gnome \\ said "hi"\nnew line✓|r')
        target = db["goals"][0]["target"]
        self.assertEqual(target["mapID"], 1429)
        self.assertAlmostEqual(target["x"], 0.452)
        self.assertAlmostEqual(target["y"], -0.05)
        self.assertIs(target["armed"], False)
        self.assertEqual(db["zones"]["Elwynn Forest"], 1762200000)

    def test_rejects_code_and_garbage(self):
        for bad in ["X = os.execute('rm -rf /')", "X = {", "X = function() end", "= 5"]:
            with self.assertRaises(fc.LuaParseError):
                fc.parse_saved_variables(bad)

    def test_empty_and_long_comment(self):
        self.assertEqual(fc.parse_saved_variables("--[==[ hi ]==]\nA = {}\n"), {"A": {}})


class FormatTests(unittest.TestCase):
    def test_clean_text_strips_wow_codes(self):
        self.assertEqual(fc.clean_text("|cffff0000Red|r and |Hitem:1|h[Sword]|h |TInterface\\x:0|t"), "Red and [Sword]")

    def test_format_entry(self):
        line = fc.format_entry({"kind": "level", "text": "|cff00ff00Reached level 2!|r", "level": 2, "zone": "Elwynn"})
        self.assertEqual(line, "⬆️ [2] Reached level 2! — Elwynn")

    def test_batches_respect_limit(self):
        batches = fc.batch_lines(["x" * 600] * 5, 1900)
        self.assertTrue(all(len(b) <= 1900 for b in batches))
        self.assertEqual(sum(b.count("x") for b in batches), 3000)


class WatcherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.sv = root / "WTF" / "Account" / "ACC" / "Forever" / "Chase" / "SavedVariables" / "ForeverChronicaller.lua"
        self.sv.parent.mkdir(parents=True)
        self.sv.write_text(SAMPLE, encoding="utf-8")
        self.cfg = fc.default_config()
        self.cfg.update(wow_path=str(root), discord_webhook="https://discord.com/api/webhooks/1/abc", ntfy_topic="topic")
        self.sender = FakeSender()
        self.logs = []
        self.watcher = fc.Watcher(self.cfg, state_path=root / "state.json", send=self.sender, log=self.logs.append)

    def tearDown(self):
        self.tmp.cleanup()

    def write_with_extra(self, extra):
        marker = '}, -- [3]\n'
        self.sv.write_text(SAMPLE.replace(marker, marker + extra, 1), encoding="utf-8")

    def test_finds_files_and_character(self):
        files = fc.saved_variable_files(self.cfg["wow_path"])
        self.assertEqual(files, [self.sv])
        self.assertEqual(fc.character_of(self.sv), "Chase-Forever")

    def test_history_is_not_posted_on_first_run(self):
        self.assertEqual(self.watcher.poll_once(), 0)
        self.assertEqual(self.sender.requests, [])

    def test_new_entries_are_posted_once(self):
        self.watcher.poll_once()
        self.write_with_extra('{\n["t"] = 1762207200,\n["kind"] = "level",\n["text"] = "Reached level 3!",\n["level"] = 3,\n},\n'
                              '{\n["t"] = 1762207200,\n["kind"] = "quest",\n["text"] = "Completed quest: Hogger",\n},\n')
        self.watcher.mtimes.clear()
        self.assertEqual(self.watcher.poll_once(), 1, "quest entries are off by default")
        self.assertEqual(len(self.sender.requests), 2, "one Discord + one ntfy request")
        discord = json.loads(self.sender.requests[0].data)
        self.assertIn("Reached level 3!", discord["content"])
        self.assertIn("**Chase-Forever**", discord["content"])
        self.assertEqual(discord["allowed_mentions"], {"parse": []})
        self.assertIn(b"Reached level 3!", self.sender.requests[1].data)
        # the same file again: nothing new
        self.watcher.mtimes.clear()
        self.assertEqual(self.watcher.poll_once(), 0)
        # state survives a restart
        w2 = fc.Watcher(self.cfg, state_path=self.watcher.state_path, send=self.sender, log=self.logs.append)
        self.assertEqual(w2.poll_once(), 0)

    def test_unchanged_file_is_not_reparsed(self):
        self.watcher.poll_once()
        self.sv.write_text("broken = {", encoding="utf-8")
        # same mtime as recorded -> skipped (simulate by restoring mtime)
        import os
        st = self.watcher.mtimes[str(self.sv)]
        os.utime(self.sv, (st, st))
        self.assertEqual(self.watcher.poll_once(), 0)
        self.assertEqual(self.logs, [])

    def test_half_written_file_is_retried(self):
        self.watcher.poll_once()
        self.sv.write_text("ForeverChronicallerDB = {", encoding="utf-8")
        self.watcher.mtimes.clear()
        self.assertEqual(self.watcher.poll_once(), 0)
        self.assertTrue(any("Couldn't read" in l for l in self.logs))
        self.assertNotIn(str(self.sv), self.watcher.mtimes, "will retry")

    def test_failed_post_does_not_leak_webhook(self):
        def failing(req):
            raise OSError("network down " + req.full_url)
        self.watcher.send = failing
        self.watcher.notify("Chase", ["hello"])
        self.assertTrue(self.logs)
        self.assertFalse(any("webhooks" in l for l in self.logs))

    def test_character_filter(self):
        self.cfg["characters"] = ["Someoneelse"]
        self.assertFalse(self.watcher.wanted("Chase-Forever", {"kind": "level"}))
        self.cfg["characters"] = ["chase"]
        self.assertTrue(self.watcher.wanted("Chase-Forever", {"kind": "level"}))


class ConfigTests(unittest.TestCase):
    def test_round_trip_and_permissions(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "c" / "config.json"
            cfg = fc.default_config()
            cfg["discord_webhook"] = "https://discord.com/api/webhooks/1/x"
            cfg["post_kinds"]["quest"] = True
            fc.save_config(cfg, path)
            loaded = fc.load_config(path)
            self.assertEqual(loaded["discord_webhook"], cfg["discord_webhook"])
            self.assertTrue(loaded["post_kinds"]["quest"])
            import os
            if os.name != "nt":
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
