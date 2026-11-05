"""Opt-in telemetry: off by default, scrubbed, valid OTLP, never breaks the program."""

import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fcompanion as fc  # noqa: E402
import fc_telemetry as ft  # noqa: E402
from test_update import make_zip  # noqa: E402

# A SavedVariables file full of personal data that must never reach telemetry.
PERSONAL_SV = r'''
ForeverChroniclerDB = {
["entries"] = {
{ ["t"] = 1762200000, ["kind"] = "note", ["text"] = "my secret goal with Buddy", ["zone"] = "Elwynn Forest", ["level"] = 5, },
},
["goals"] = { { ["kind"] = "free", ["text"] = "my secret goal", ["created"] = 1, }, },
["errorLog"] = {
{
["t"] = 1762200500, ["first"] = 1762200400, ["count"] = 3, ["v"] = "0.3.1", ["label"] = "msg:GOALS_CHANGED",
["msg"] = "Interface/AddOns/ForeverChronicler/Goals.lua:42: attempt to index field 'Buddy' (a nil value) at C:\\Users\\ChaseSecret\\x.txt 1762200400",
["stack"] = "[string \"@Interface/AddOns/ForeverChronicler/Goals.lua\"]:42: in function <...>\n[string \"@Interface/AddOns/ForeverChronicler/Core.lua\"]:70: in function",
},
},
["diagnostics"] = {
["version"] = "0.3.1", ["since"] = 1762200000,
["handlers"] = {
["event:PLAYER_LEVEL_UP"] = { ["n"] = 4, ["sum"] = 6.5, ["max"] = 3, ["err"] = 0, ["b"] = { 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, }, },
["cmd:goal"] = { ["n"] = 1, ["sum"] = 0.2, ["max"] = 0.2, ["err"] = 1, ["b"] = { 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, }, },
["Buddy's secret"] = { ["n"] = 1, ["sum"] = 1, ["max"] = 1, ["err"] = 0, ["b"] = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, }, },
},
},
}
'''
FORBIDDEN = ["Chase", "ACCOUNTNAME", "Forever", "secret goal", "Buddy", "Users", "webhooks", "Elwynn",
             "topic-secret", "wow-folder"]


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.cfgdir = self.root / "cfg"
        for name, value in (("config_dir", lambda: self.cfgdir), ("game_running", lambda: False)):
            p = mock.patch.object(fc, name, value)
            p.start()
            self.addCleanup(p.stop)
        # never touch the network from tests (telemetry export or GitHub update checks)
        p = mock.patch.object(ft, "_http_post", side_effect=AssertionError("network used"))
        p.start()
        self.addCleanup(p.stop)
        p = mock.patch.object(fc, "_http_get", side_effect=fc.urllib.error.URLError("offline in tests"))
        p.start()
        self.addCleanup(p.stop)
        for var in ("OTEL_EXPORTER_OTLP_ENDPOINT", "OTEL_EXPORTER_OTLP_HEADERS"):
            p = mock.patch.dict(os.environ, {}, clear=False)
            p.start()
            self.addCleanup(p.stop)
            os.environ.pop(var, None)
        self.addCleanup(setattr, fc, "TEL", ft.DISABLED)
        # The feature flag is off in releases; these tests switch it on so the
        # dormant telemetry code stays tested (see FlagOff for the shipped behaviour).
        p = mock.patch.object(fc, "FEATURE_TELEMETRY", True)
        p.start()
        self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def wow_with_sv(self, account="ACCOUNTNAME", realm="Forever", char="Chase"):
        wow = self.root / "wow-folder"
        (wow / "Interface" / "AddOns").mkdir(parents=True, exist_ok=True)
        (wow / "Wow.exe").write_bytes(b"")
        sv = wow / "WTF" / "Account" / account / realm / char / "SavedVariables" / "ForeverChronicler.lua"
        sv.parent.mkdir(parents=True, exist_ok=True)
        sv.write_text(PERSONAL_SV, encoding="utf-8")
        return wow

    def config(self, enabled=False, **extra):
        cfg = fc.default_config()
        cfg["accepted_terms"] = fc.TERMS_VERSION
        cfg["discord_webhook"] = "https://discord.com/api/webhooks/123/abc"
        cfg["ntfy_topic"] = "topic-secret"
        cfg.update(extra)
        if enabled:
            fc.set_telemetry(cfg, True)
        fc.save_config(cfg)
        return cfg

    def spool(self):
        path = self.cfgdir / "telemetry-spool.jsonl"
        if not path.exists():
            return []
        return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines()]

    def run_main(self, *argv, answers=()):
        answers = iter(answers)
        out = io.StringIO()
        with mock.patch("builtins.input", lambda p="": next(answers, "")), mock.patch("sys.stdout", out):
            code = fc.main(list(argv))
        return code, out.getvalue()


class OffByDefault(Base):
    def test_defaults_are_off(self):
        t = fc.default_config()["telemetry"]
        self.assertFalse(t["enabled"])
        self.assertEqual(t["install_id"], "")
        self.assertIs(fc.build_telemetry(fc.default_config()), ft.DISABLED)

    def test_disabled_collects_and_writes_nothing(self):
        wow = self.wow_with_sv()
        self.config(wow_path=str(wow))
        code, _ = self.run_main("watch", "--once")
        self.assertEqual(code, 0)
        self.assertEqual(self.spool(), [])
        self.assertFalse((self.cfgdir / "telemetry-spool.jsonl").exists())

    def test_install_question_defaults_to_no_and_is_not_repeated(self):
        zipf = self.root / "ForeverChronicler-0.3.1.zip"
        zipf.write_bytes(make_zip("0.3.1"))
        wow = self.root / "w"
        wow.mkdir()
        (wow / "Wow.exe").write_bytes(b"")
        code, out = self.run_main("install", "--wow", str(wow), "--zip", str(zipf), answers=["yes", ""])
        self.assertEqual(code, 0, out)
        self.assertIn("NEVER sends", out)
        cfg = fc.load_config(self.cfgdir / "config.json")
        self.assertFalse(cfg["telemetry"]["enabled"])
        self.assertTrue(cfg["telemetry"]["asked"])
        code, out = self.run_main("install", "--wow", str(wow), "--zip", str(zipf))
        self.assertNotIn("Share anonymous diagnostics", out)

    def test_yes_flag_never_opts_in(self):
        zipf = self.root / "ForeverChronicler-0.3.1.zip"
        zipf.write_bytes(make_zip("0.3.1"))
        wow = self.root / "w"
        wow.mkdir()
        (wow / "Wow.exe").write_bytes(b"")
        self.run_main("install", "--wow", str(wow), "--zip", str(zipf), "--yes", "--accept-terms")
        self.assertFalse(fc.load_config(self.cfgdir / "config.json")["telemetry"]["enabled"])
        self.run_main("install", "--wow", str(wow), "--zip", str(zipf), "--yes", "--accept-terms", "--telemetry")
        self.assertTrue(fc.load_config(self.cfgdir / "config.json")["telemetry"]["enabled"])


class OptInOut(Base):
    def test_on_and_off(self):
        self.config()
        code, out = self.run_main("telemetry", "on", answers=["y"])
        cfg = fc.load_config(self.cfgdir / "config.json")
        self.assertTrue(cfg["telemetry"]["enabled"])
        self.assertRegex(cfg["telemetry"]["install_id"], r"^[0-9a-f]{32}$")
        self.assertIn("local file", out)  # no endpoint configured -> says so honestly
        self.run_main("telemetry", "status")  # creates spool via flush
        self.assertTrue(self.spool())
        code, out = self.run_main("telemetry", "off")
        cfg = fc.load_config(self.cfgdir / "config.json")
        self.assertFalse(cfg["telemetry"]["enabled"])
        self.assertEqual(cfg["telemetry"]["install_id"], "")
        self.assertFalse((self.cfgdir / "telemetry-spool.jsonl").exists(), "local data deleted")

    def test_on_declined(self):
        self.config()
        self.run_main("telemetry", "on", answers=["n"])
        self.assertFalse(fc.load_config(self.cfgdir / "config.json")["telemetry"]["enabled"])


class Scrubbing(unittest.TestCase):
    def test_scrub(self):
        cases = {
            "Interface/AddOns/ForeverChronicler/Goals.lua:42: attempt to index field 'Buddy'": "Goals.lua:42: attempt to index field <str>",
            "Interface/AddOns/ForeverChronicler/src/goals/Goals.lua:42: attempt to call nil": "Goals.lua:42: attempt to call nil",
            "C:\\WoW\\Interface\\AddOns\\ForeverChronicler\\src\\core\\Core.lua:7: boom": "Core.lua:7: boom",
            'C:\\Users\\Chase\\file.txt failed': "<path> failed",
            "/home/chase/.config/x.json missing": "<path> missing",
            "see https://discord.com/api/webhooks/1/x now": "see <url> now",
            "|cffff0000red|r 1762200400 and 42": "red <n> and 42",
            "mail me@example.com": "mail <email>",
            'call [[long text]] "Bob"': "call <str> <str>",
        }
        for raw, expected in cases.items():
            self.assertEqual(ft.scrub(raw), expected, raw)

    def test_stack_keeps_only_locations(self):
        stack = '[string "@Interface/AddOns/ForeverChronicler/Goals.lua"]:42: in function <x>\n/home/me/fcompanion.py:10'
        self.assertEqual(ft.scrub_stack(stack), "Goals.lua:42 < fcompanion.py:10")
        self.assertNotIn("home", ft.scrub_stack(stack))

    def test_endpoint_label_hides_path_and_token(self):
        self.assertEqual(ft.endpoint_label("https://otlp.example.com/otlp?token=abc"), "https://otlp.example.com")


class Payloads(Base):
    def collect(self, wow, endpoint=None, sent=None):
        cfg = self.config(enabled=True, wow_path=str(wow))
        if endpoint:
            os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = endpoint
            os.environ["OTEL_EXPORTER_OTLP_HEADERS"] = "Authorization=Basic%20abc,X-Scope=fc"
        with mock.patch.object(ft, "_http_post", lambda url, body, headers: sent.append((url, body, headers))) \
                if sent is not None else mock.patch.object(ft, "_http_post", side_effect=AssertionError("network")):
            # rebuild the Telemetry object so it picks up the patched sender
            with mock.patch.object(fc, "build_telemetry", lambda c: ft.Telemetry(
                    enabled=True, install_id=c["telemetry"]["install_id"],
                    endpoint=ft.destination(c["telemetry"], {})[0], headers=ft.destination(c["telemetry"], {})[1],
                    resource=ft.runtime_resource(fc.VERSION, "0.3.1", False), spool_path=fc.spool_path(),
                    send=ft._http_post)):
                code, out = self.run_main("watch", "--once")
        self.assertEqual(code, 0, out)
        return cfg

    def payload_text(self):
        return json.dumps(self.spool())

    def test_no_personal_data_ever(self):
        wow = self.wow_with_sv()
        self.collect(wow)
        text = self.payload_text()
        self.assertTrue(text)
        for word in FORBIDDEN:
            self.assertNotIn(word, text, f"{word!r} leaked into telemetry")

    def test_addon_errors_linked_to_version_with_location_and_trace(self):
        self.collect(self.wow_with_sv())
        items = self.spool()
        metrics = [m for i in items if i["signal"] == "metrics"
                   for rm in i["payload"]["resourceMetrics"] for sm in rm["scopeMetrics"] for m in sm["metrics"]]
        errors = next(m for m in metrics if m["name"] == "fc.addon.errors")
        point = errors["sum"]["dataPoints"][0]
        attrs = {a["key"]: list(a["value"].values())[0] for a in point["attributes"]}
        self.assertEqual(attrs["addon.version"], "0.3.1")
        self.assertEqual(attrs["error.where"], "Goals.lua:42")
        self.assertEqual(attrs["handler"], "msg:GOALS_CHANGED")
        self.assertNotIn("error.message", attrs, "messages stay off metric labels (series count)")
        self.assertEqual(point["asInt"], "3")
        self.assertEqual(errors["sum"]["aggregationTemporality"], 2)  # cumulative
        spans = [s for i in items if i["signal"] == "traces"
                 for rs in i["payload"]["resourceSpans"] for ss in rs["scopeSpans"] for s in ss["spans"]]
        err_span = next(s for s in spans if s["name"] == "addon.error")
        self.assertEqual(err_span["status"]["code"], 2)
        stack = next(a for a in err_span["attributes"] if a["key"] == "error.stack")["value"]["stringValue"]
        self.assertEqual(stack, "Goals.lua:42 < Core.lua:70")
        message = next(a for a in err_span["attributes"] if a["key"] == "error.message")["value"]["stringValue"]
        self.assertIn("attempt to index field", message, "the scrubbed message is on the span")

    def test_addon_latency_histograms(self):
        self.collect(self.wow_with_sv())
        metrics = [m for i in self.spool() if i["signal"] == "metrics"
                   for rm in i["payload"]["resourceMetrics"] for sm in rm["scopeMetrics"] for m in sm["metrics"]]
        hist = next(m for m in metrics if m["name"] == "fc.addon.handler.duration")
        labels = {next(a for a in p["attributes"] if a["key"] == "handler")["value"]["stringValue"]: p
                  for p in hist["histogram"]["dataPoints"]}
        self.assertEqual(set(labels), {"event:PLAYER_LEVEL_UP", "cmd:goal"}, "unknown labels dropped")
        p = labels["event:PLAYER_LEVEL_UP"]
        self.assertEqual(sum(int(b) for b in p["bucketCounts"]), int(p["count"]))
        self.assertEqual(len(p["bucketCounts"]), len(p["explicitBounds"]) + 1)

    def test_companion_traces_and_latency(self):
        self.collect(self.wow_with_sv())
        items = self.spool()
        spans = [s for i in items if i["signal"] == "traces"
                 for rs in i["payload"]["resourceSpans"] for ss in rs["scopeSpans"] for s in ss["spans"]]
        by_name = {s["name"]: s for s in spans}
        root = by_name["command.watch"]
        self.assertNotIn("parentSpanId", root)
        self.assertRegex(root["traceId"], r"^[0-9a-f]{32}$")
        self.assertRegex(root["spanId"], r"^[0-9a-f]{16}$")
        child = by_name["watch.process"]
        self.assertEqual(child["traceId"], root["traceId"])
        self.assertTrue(child.get("parentSpanId"))
        self.assertGreaterEqual(int(root["endTimeUnixNano"]), int(root["startTimeUnixNano"]))
        metrics = [m for i in items if i["signal"] == "metrics"
                   for rm in i["payload"]["resourceMetrics"] for sm in rm["scopeMetrics"] for m in sm["metrics"]]
        names = {m["name"] for m in metrics}
        self.assertLessEqual({"fc.operations", "fc.operation.duration"}, names)
        res = {a["key"]: list(a["value"].values())[0] for a in items[0]["payload"][
            "resourceSpans" if items[0]["signal"] == "traces" else "resourceMetrics"][0]["resource"]["attributes"]}
        self.assertEqual(res["service.name"], "forever-chronicler-companion")
        self.assertEqual(res["service.version"], fc.VERSION)
        self.assertRegex(res["fc.install.id"], r"^[0-9a-f]{32}$")
        self.assertEqual(res["service.instance.id"], res["fc.install.id"])

    def test_sends_to_configured_endpoint_with_headers(self):
        sent = []
        self.collect(self.wow_with_sv(), endpoint="https://otlp.example.com/otlp", sent=sent)
        urls = {u for u, _, _ in sent}  # sent after the poll and again at exit
        self.assertEqual(urls, {"https://otlp.example.com/otlp/v1/metrics", "https://otlp.example.com/otlp/v1/traces"})
        headers = sent[0][2]
        self.assertEqual(headers["Authorization"], "Basic abc")
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(self.spool(), [], "nothing spooled when an endpoint is set")
        for _, body, _ in sent:
            for word in FORBIDDEN:
                self.assertNotIn(word.encode(), body)


class FlagOff(Base):
    """What ships: FEATURE_TELEMETRY = False."""

    def setUp(self):
        super().setUp()
        p = mock.patch.object(fc, "FEATURE_TELEMETRY", False)
        p.start()
        self.addCleanup(p.stop)

    def test_flag_is_off_in_this_version(self):
        source = Path(fc.__file__).read_text(encoding="utf-8")
        self.assertRegex(source, r"(?m)^FEATURE_TELEMETRY = False$", "telemetry must ship switched off")

    def test_no_question_no_command_no_flag(self):
        zipf = self.root / "ForeverChronicler-0.4.0.zip"
        zipf.write_bytes(make_zip("0.4.0"))
        wow = self.root / "w"
        wow.mkdir()
        (wow / "Wow.exe").write_bytes(b"")
        code, out = self.run_main("install", "--wow", str(wow), "--zip", str(zipf), answers=["yes"])
        self.assertEqual(code, 0, out)
        self.assertNotIn("diagnostics", out.lower())
        self.assertIn("No telemetry", out)
        self.assertFalse(fc.load_config(self.cfgdir / "config.json")["telemetry"]["asked"])
        with mock.patch("sys.stderr", io.StringIO()), self.assertRaises(SystemExit):
            fc.main(["telemetry", "status"])
        with mock.patch("sys.stderr", io.StringIO()), self.assertRaises(SystemExit):
            fc.main(["install", "--telemetry"])

    def test_enabled_config_is_ignored(self):
        wow = self.wow_with_sv()
        cfg = self.config(wow_path=str(wow))
        cfg["telemetry"].update(enabled=True, install_id="a" * 32)
        fc.save_config(cfg)
        self.assertIs(fc.build_telemetry(cfg), ft.DISABLED)
        code, _ = self.run_main("watch", "--once")
        self.assertEqual(code, 0)
        self.assertFalse((self.cfgdir / "telemetry-spool.jsonl").exists())


class Robustness(unittest.TestCase):
    def test_send_failure_never_raises(self):
        def boom(*a):
            raise OSError("network down")
        t = ft.Telemetry(enabled=True, install_id="x" * 32, endpoint="https://e", send=boom)
        with t.span("op"):
            pass
        self.assertEqual(t.flush(), 0)
        self.assertEqual(t.last_error, "OSError")

    def test_exception_recorded_scrubbed_and_reraised(self):
        t = ft.Telemetry(enabled=True, install_id="x" * 32)
        with self.assertRaises(ValueError):
            with t.span("op"):
                raise ValueError("bad value 'Chase' at C:\\Users\\Chase")
        span = t.spans[0].to_otlp()
        self.assertEqual(span["status"]["code"], 2)
        msg = next(a for a in span["events"][0]["attributes"] if a["key"] == "exception.message")
        self.assertNotIn("Chase", json.dumps(msg))
        err = [k for k in t.counters if k[0] == "fc.errors"][0]
        self.assertIn(("error.type", "ValueError"), err[1])
        self.assertTrue(any(k == "error.where" and v.startswith("test_telemetry.py:") for k, v in err[1]))

    def test_disabled_instance_is_inert(self):
        t = ft.Telemetry(enabled=True, install_id="")  # no id -> disabled
        with t.span("op") as sp:
            sp.set(a=1)
        t.count("x")
        t.add_addon_data({"errorLog": [{"msg": "x"}]}, "1")
        self.assertEqual((t.spans, t.counters, t.flush()), ([], {}, 0))

    def test_same_location_different_messages_is_one_series(self):
        db = {"errorLog": [{"msg": "Goals.lua:1: first", "count": 2, "t": 1, "label": "msg:X"},
                           {"msg": "Goals.lua:1: second", "count": 3, "t": 2, "label": "msg:X"}]}
        t = ft.Telemetry(enabled=True, install_id="x" * 32)
        t.add_addon_data(db, "1")
        errors = next(m for m in t.external_metrics if m["name"] == "fc.addon.errors")
        points = errors["sum"]["dataPoints"]
        self.assertEqual(len(points), 1)
        self.assertEqual(points[0]["asInt"], "5")

    def test_error_spans_not_repeated(self):
        db = {"errorLog": [{"msg": "Goals.lua:1: x", "count": 1, "t": 1}]}
        seen = set()
        t = ft.Telemetry(enabled=True, install_id="x" * 32)
        t.add_addon_data(db, "1", seen)
        t.add_addon_data(db, "1", seen)
        self.assertEqual(len([s for s in t.spans if s.name == "addon.error"]), 1)

    def test_http_span_has_status_not_url(self):
        t = ft.Telemetry(enabled=True, install_id="x" * 32)
        with mock.patch.object(fc, "TEL", t):
            fc.post_discord("https://discord.com/api/webhooks/1/secret", "C", ["hi"], send=lambda req: 204)
        span = next(s for s in t.spans if s.name == "http.post").to_otlp()
        attrs = {a["key"]: list(a["value"].values())[0] for a in span["attributes"]}
        self.assertEqual(attrs["http.response.status_code"], "204")
        self.assertEqual(attrs["fc.target"], "discord")
        self.assertNotIn("webhooks", json.dumps(span))


if __name__ == "__main__":
    unittest.main()
