"""Opt-in, anonymous telemetry for Forever Chronicler (OpenTelemetry, OTLP/HTTP JSON).

OFF by default. Nothing in this module does anything unless the user has
opted in (config "telemetry.enabled" plus a random install id). See PRIVACY.md.

What it produces:
  * traces  - a span per operation (install, update, watch poll, Discord post, ...)
              with child spans, durations, status and scrubbed exceptions
  * metrics - fc.operations (count by op/outcome), fc.operation.duration (latency
              histogram), fc.errors (companion + addon errors by version and
              location), fc.addon.handler.duration / .errors (in-game diagnostics)

Where it goes: the OTLP endpoint from (highest first) the standard
OTEL_EXPORTER_OTLP_ENDPOINT / OTEL_EXPORTER_OTLP_HEADERS environment variables,
the companion config, or telemetry_build.json baked into release builds.
Without an endpoint, payloads are appended to a local spool file the user can
read and delete. Sending never blocks or breaks the program.

Privacy: attribute values are either fixed code names or pass through scrub(),
which removes quoted text, paths, URLs, long numbers and WoW colour codes.
"""

from __future__ import annotations

import json
import os
import platform
import re
import secrets
import sys
import time
import urllib.parse
import urllib.request
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Callable, Dict, Iterator, List, Optional, Tuple

SERVICE = "forever-chronicler-companion"
DURATION_BOUNDS_MS = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000]
SPOOL_MAX_BYTES = 1_000_000
SEND_TIMEOUT = 5

# --------------------------------------------------------------------------- scrubbing

_COLOR = re.compile(r"\|c[0-9a-fA-F]{8}|\|r")
_URL = re.compile(r"\b[a-z][a-z0-9+.-]*://\S+", re.I)
_ADDON_PATH = re.compile(r"[^\s'\"]*?[\\/]AddOns[\\/](?:ForeverChronic(?:al)?ler[\\/](?:src[\\/][\w-]+[\\/])?)?", re.I)
_WIN_PATH = re.compile(r"\b[A-Za-z]:[\\/][^\s'\"]*")
_POSIX_PATH = re.compile(r"(?<![\w.])/(?:[\w.~-]+/)+[\w.~-]*")
_QUOTED = re.compile(r"'[^']*'|\"[^\"]*\"|\[\[.*?\]\]", re.S)
_LONG_NUMBER = re.compile(r"(?<![:\w.])\d{4,}")
_EMAIL = re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b")


def scrub(text: Any, limit: int = 200) -> str:
    """Remove anything that could identify the user from an error message or stack."""
    s = _COLOR.sub("", str(text))
    s = _URL.sub("<url>", s)
    s = _ADDON_PATH.sub("", s)          # ".../AddOns/ForeverChronicler/src/goals/Goals.lua:42" -> "Goals.lua:42"
    s = _WIN_PATH.sub("<path>", s)
    s = _POSIX_PATH.sub("<path>", s)
    s = _QUOTED.sub("<str>", s)
    s = _EMAIL.sub("<email>", s)
    s = _LONG_NUMBER.sub("<n>", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s[:limit]


# Only a code file's base name and a line number are ever taken from a stack or
# message, so it's safe to search the raw text (WoW quotes file paths in stacks,
# which scrub() would otherwise remove together with the location).
_LOCATION = re.compile(r"([\w-]+\.(?:lua|py|xml))[\"']?\]?:(\d+)")


def scrub_stack(stack: Any, frames: int = 8) -> str:
    """Keep only 'File.lua:line' / 'file.py:line' locations from a stack trace."""
    found = _LOCATION.findall(str(stack or ""))
    return " < ".join(f"{f}:{n}" for f, n in found[:frames])


def error_location(message: str) -> str:
    m = _LOCATION.search(str(message or ""))
    return f"{m.group(1)}:{m.group(2)}" if m else "unknown"


# ------------------------------------------------------------------------- OTLP helpers

def _kv(key: str, value: Any) -> Dict[str, Any]:
    if isinstance(value, bool):
        v = {"boolValue": value}
    elif isinstance(value, int):
        v = {"intValue": str(value)}
    elif isinstance(value, float):
        v = {"doubleValue": value}
    else:
        v = {"stringValue": str(value)}
    return {"key": key, "value": v}


def _attrs(d: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [_kv(k, v) for k, v in sorted(d.items()) if v is not None]


def hash_key(key: Any) -> str:
    import hashlib
    return hashlib.sha256(repr(key).encode()).hexdigest()[:16]


def parse_headers(raw: Any) -> Dict[str, str]:
    """OTEL_EXPORTER_OTLP_HEADERS format: 'k1=v1,k2=v2' (values URL-encoded), or a dict."""
    if isinstance(raw, dict):
        return {str(k): str(v) for k, v in raw.items()}
    out = {}
    for part in str(raw or "").split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip()] = urllib.parse.unquote(v.strip())
    return out


class _Histogram:
    def __init__(self, bounds: List[float]):
        self.bounds = bounds
        self.buckets = [0] * (len(bounds) + 1)
        self.count = 0
        self.sum = 0.0
        self.min: Optional[float] = None
        self.max: Optional[float] = None

    def record(self, value: float) -> None:
        i = 0
        while i < len(self.bounds) and value > self.bounds[i]:
            i += 1
        self.buckets[i] += 1
        self.count += 1
        self.sum += value
        self.min = value if self.min is None else min(self.min, value)
        self.max = value if self.max is None else max(self.max, value)


class _Span:
    def __init__(self, tel: "Telemetry", name: str, trace_id: str, parent_id: Optional[str], attrs: Dict[str, Any]):
        self.tel, self.name, self.trace_id, self.parent_id = tel, name, trace_id, parent_id
        self.span_id = secrets.token_hex(8)
        self.attrs = dict(attrs)
        self.events: List[Dict[str, Any]] = []
        self.status = (0, "")  # UNSET
        self.start_ns = time.time_ns()
        self._t0 = time.perf_counter()
        self.end_ns = 0
        self.duration_ms = 0.0

    def set(self, **attrs: Any) -> None:
        self.attrs.update(attrs)

    def error(self, exc: BaseException) -> None:
        self.status = (2, type(exc).__name__)
        self.events.append({"timeUnixNano": str(time.time_ns()), "name": "exception", "attributes": _attrs({
            "exception.type": type(exc).__name__,
            "exception.message": scrub(exc),
        })})

    def to_otlp(self) -> Dict[str, Any]:
        span = {
            "traceId": self.trace_id, "spanId": self.span_id, "name": self.name,
            "kind": 3 if self.name.startswith("http.") else 1,  # CLIENT / INTERNAL
            "startTimeUnixNano": str(self.start_ns), "endTimeUnixNano": str(self.end_ns),
            "attributes": _attrs(self.attrs), "events": self.events,
            "status": {"code": self.status[0], **({"message": self.status[1]} if self.status[1] else {})},
        }
        if self.parent_id:
            span["parentSpanId"] = self.parent_id
        return span


class _NoSpan:
    def set(self, **attrs: Any) -> None:
        pass

    def error(self, exc: BaseException) -> None:
        pass


# ------------------------------------------------------------------------------ Telemetry

Sender = Callable[[str, bytes, Dict[str, str]], None]


def _http_post(url: str, body: bytes, headers: Dict[str, str]) -> None:
    req = urllib.request.Request(url, data=body, method="POST", headers=headers)
    with urllib.request.urlopen(req, timeout=SEND_TIMEOUT) as resp:
        resp.read()


class Telemetry:
    """Collects spans and metrics for one program run. A disabled instance does nothing."""

    def __init__(self, enabled: bool = False, install_id: str = "", endpoint: str = "",
                 headers: Optional[Dict[str, str]] = None, resource: Optional[Dict[str, Any]] = None,
                 spool_path: Optional[Path] = None, send: Optional[Sender] = None):
        self.enabled = bool(enabled and install_id)
        self.install_id = install_id
        self.endpoint = endpoint.rstrip("/")
        self.headers = headers or {}
        self.resource = resource or {}
        self.spool_path = spool_path
        self.send = send or _http_post  # resolved now, so tests can patch it
        self.start_ns = time.time_ns()
        self.spans: List[_Span] = []
        self._stack: List[_Span] = []
        self.counters: Dict[Tuple[str, Tuple], int] = {}
        self.histograms: Dict[Tuple[str, Tuple], _Histogram] = {}
        self.external_metrics: List[Dict[str, Any]] = []  # pre-built (addon) metrics
        self.last_error = ""

    # -- recording ------------------------------------------------------------
    @contextmanager
    def span(self, name: str, **attrs: Any) -> Iterator[Any]:
        """Time an operation. Nested spans become children. Exceptions are recorded and re-raised."""
        if not self.enabled:
            yield _NoSpan()
            return
        parent = self._stack[-1] if self._stack else None
        sp = _Span(self, name, parent.trace_id if parent else secrets.token_hex(16),
                   parent.span_id if parent else None, attrs)
        self._stack.append(sp)
        outcome = "ok"
        try:
            yield sp
            if sp.status[0] == 2:
                outcome = "error"
            elif sp.status[0] == 0:
                sp.status = (1, "")
        except BaseException as exc:
            outcome = "error"
            sp.error(exc)
            self.count("fc.errors", source="companion", **{"error.type": type(exc).__name__,
                       "error.where": self._where(exc), "operation": name})
            raise
        finally:
            sp.end_ns = time.time_ns()
            sp.duration_ms = (time.perf_counter() - sp._t0) * 1000
            self._stack.pop()
            self.spans.append(sp)
            self.count("fc.operations", operation=name, outcome=outcome)
            self.observe("fc.operation.duration", sp.duration_ms, operation=name, outcome=outcome)

    @staticmethod
    def _where(exc: BaseException) -> str:
        tb = exc.__traceback__
        last = None
        while tb is not None:
            last = tb
            tb = tb.tb_next
        if last is None:
            return "unknown"
        return f"{Path(last.tb_frame.f_code.co_filename).name}:{last.tb_lineno}"

    def count(self, name: str, value: int = 1, **attrs: Any) -> None:
        if self.enabled:
            key = (name, tuple(sorted(attrs.items())))
            self.counters[key] = self.counters.get(key, 0) + value

    def observe(self, name: str, value_ms: float, **attrs: Any) -> None:
        if self.enabled:
            key = (name, tuple(sorted(attrs.items())))
            self.histograms.setdefault(key, _Histogram(DURATION_BOUNDS_MS)).record(value_ms)

    # -- addon data (from SavedVariables) ---------------------------------------
    def add_addon_data(self, db: Dict[str, Any], installed_version: Optional[str],
                       seen_errors: Optional[set] = None) -> None:
        """Turn the addon's error log and (opt-in) diagnostics into metrics + error spans.
        Metrics are cumulative, so sending the same data twice is harmless. Error spans
        are only created for errors not in `seen_errors` (which is updated)."""
        if not self.enabled or not isinstance(db, dict):
            return
        now = str(time.time_ns())
        log = db.get("errorLog") or []
        if isinstance(log, dict):
            log = list(log.values())
        points = {}
        for e in log:
            if not isinstance(e, dict) or "msg" not in e:
                continue
            attrs = {
                "source": "addon",
                "addon.version": str(e.get("v") or installed_version or "unknown"),
                "error.where": error_location(str(e.get("msg"))),
                "error.message": scrub(e.get("msg")),
                "handler": scrub(e.get("label") or "unknown", 60),
            }
            key = tuple(sorted(attrs.items()))
            start = int(e.get("first") or e.get("t") or 0) * 1_000_000_000
            prev = points.get(key)
            count = int(e.get("count") or 1) + (prev[1] if prev else 0)
            points[key] = (min(start, prev[0]) if prev else start, count, scrub_stack(e.get("stack")))
        if points:
            self.external_metrics.append({"name": "fc.addon.errors", "unit": "1", "sum": {
                "aggregationTemporality": 2, "isMonotonic": True, "dataPoints": [
                    {"attributes": _attrs(dict(k)), "startTimeUnixNano": str(start), "timeUnixNano": now, "asInt": str(n)}
                    for k, (start, n, _) in points.items()]}})
            # one span per distinct error so errors show up in trace views too
            trace = secrets.token_hex(16)
            for k, (start, n, stack) in points.items():
                fingerprint = f"{hash_key(k)}:{n}"
                if seen_errors is not None:
                    if fingerprint in seen_errors:
                        continue
                    seen_errors.add(fingerprint)
                a = dict(k)
                sp = _Span(self, "addon.error", trace, None, {**a, "error.count": n, "error.stack": stack})
                sp.status = (2, a["error.where"])
                sp.end_ns = sp.start_ns
                self.spans.append(sp)

        diag = db.get("diagnostics")
        if isinstance(diag, dict) and isinstance(diag.get("handlers"), dict):
            version = str(diag.get("version") or installed_version or "unknown")
            start = str(int(diag.get("since") or 0) * 1_000_000_000)
            bounds = [0.1, 0.5, 1, 2, 5, 10, 25, 50, 100, 250, 1000]  # FC.DIAG_BOUNDS in Core.lua
            hist_points, err_points = [], []
            for label, h in diag["handlers"].items():
                if not isinstance(h, dict) or not re.fullmatch(r"(event|msg|cmd):[\w-]*", str(label)):
                    continue  # labels are code names; anything else is ignored
                buckets = h.get("b") or []
                if isinstance(buckets, dict):
                    buckets = [buckets.get(i, 0) for i in range(1, len(bounds) + 2)]
                if len(buckets) != len(bounds) + 1:
                    continue
                attrs = _attrs({"handler": label, "addon.version": version})
                hist_points.append({"attributes": attrs, "startTimeUnixNano": start, "timeUnixNano": now,
                                    "count": str(int(h.get("n") or 0)), "sum": float(h.get("sum") or 0),
                                    "max": float(h.get("max") or 0),
                                    "bucketCounts": [str(int(b)) for b in buckets], "explicitBounds": bounds})
                err_points.append({"attributes": attrs, "startTimeUnixNano": start, "timeUnixNano": now,
                                   "asInt": str(int(h.get("err") or 0))})
            if hist_points:
                self.external_metrics.append({"name": "fc.addon.handler.duration", "unit": "ms", "histogram": {
                    "aggregationTemporality": 2, "dataPoints": hist_points}})
                self.external_metrics.append({"name": "fc.addon.handler.errors", "unit": "1", "sum": {
                    "aggregationTemporality": 2, "isMonotonic": True, "dataPoints": err_points}})

    # -- export -----------------------------------------------------------------
    def _resource(self) -> Dict[str, Any]:
        return {"attributes": _attrs({"service.name": SERVICE, "fc.install.id": self.install_id, **self.resource})}

    def _scope(self) -> Dict[str, Any]:
        return {"name": "fcompanion", "version": str(self.resource.get("service.version", ""))}

    def payloads(self) -> Dict[str, Dict[str, Any]]:
        now = str(time.time_ns())
        start = str(self.start_ns)
        out: Dict[str, Dict[str, Any]] = {}
        if self.spans:
            out["traces"] = {"resourceSpans": [{"resource": self._resource(), "scopeSpans": [
                {"scope": self._scope(), "spans": [s.to_otlp() for s in self.spans]}]}]}
        metrics: List[Dict[str, Any]] = []
        by_name: Dict[str, List[Dict[str, Any]]] = {}
        for (name, attrs), value in self.counters.items():
            by_name.setdefault(name, []).append({"attributes": _attrs(dict(attrs)), "startTimeUnixNano": start,
                                                 "timeUnixNano": now, "asInt": str(value)})
        for name, points in by_name.items():
            metrics.append({"name": name, "unit": "1", "sum": {"aggregationTemporality": 2, "isMonotonic": True,
                                                              "dataPoints": points}})
        hists: Dict[str, List[Dict[str, Any]]] = {}
        for (name, attrs), h in self.histograms.items():
            hists.setdefault(name, []).append({
                "attributes": _attrs(dict(attrs)), "startTimeUnixNano": start, "timeUnixNano": now,
                "count": str(h.count), "sum": h.sum, "min": h.min, "max": h.max,
                "bucketCounts": [str(b) for b in h.buckets], "explicitBounds": h.bounds})
        for name, points in hists.items():
            metrics.append({"name": name, "unit": "ms", "histogram": {"aggregationTemporality": 2, "dataPoints": points}})
        metrics += self.external_metrics
        if metrics:
            out["metrics"] = {"resourceMetrics": [{"resource": self._resource(), "scopeMetrics": [
                {"scope": self._scope(), "metrics": metrics}]}]}
        return out

    def flush(self) -> int:
        """Send (or spool) everything collected so far. Never raises. Returns payloads handled."""
        if not self.enabled:
            return 0
        handled = 0
        for signal, payload in self.payloads().items():
            body = json.dumps(payload, separators=(",", ":")).encode()
            try:
                if self.endpoint:
                    self.send(f"{self.endpoint}/v1/{signal}", body,
                              {"Content-Type": "application/json", **self.headers})
                else:
                    self._spool(signal, payload)
                handled += 1
            except Exception as exc:  # telemetry must never break the program
                self.last_error = f"{type(exc).__name__}"
        self.spans.clear()
        self.counters.clear()
        self.histograms.clear()
        self.external_metrics.clear()
        self.start_ns = time.time_ns()
        return handled

    def _spool(self, signal: str, payload: Dict[str, Any]) -> None:
        if not self.spool_path:
            return
        self.spool_path.parent.mkdir(parents=True, exist_ok=True)
        if self.spool_path.exists() and self.spool_path.stat().st_size > SPOOL_MAX_BYTES:
            os.replace(self.spool_path, self.spool_path.with_suffix(".old.jsonl"))
        with open(self.spool_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"signal": signal, "payload": payload}) + "\n")


DISABLED = Telemetry()


# ----------------------------------------------------------------------- configuration

def destination(cfg_tel: Dict[str, Any], build: Dict[str, Any]) -> Tuple[str, Dict[str, str]]:
    """Endpoint + headers: environment > config > release build defaults."""
    env_ep = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "")
    if env_ep:
        return env_ep, parse_headers(os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", ""))
    if cfg_tel.get("endpoint"):
        return cfg_tel["endpoint"], parse_headers(cfg_tel.get("headers", ""))
    if build.get("endpoint"):
        return build["endpoint"], parse_headers(build.get("headers", ""))
    return "", {}


def endpoint_label(endpoint: str) -> str:
    """What the user is shown: scheme + host only."""
    if not endpoint:
        return "nowhere - only a local file on this computer (no endpoint configured)"
    p = urllib.parse.urlparse(endpoint)
    return f"{p.scheme}://{p.hostname}" if p.hostname else endpoint


def new_install_id() -> str:
    return uuid.uuid4().hex


def runtime_resource(service_version: str, addon_version: Optional[str], frozen: bool) -> Dict[str, Any]:
    return {
        "service.version": service_version,
        "fc.addon.version": addon_version or "not installed",
        "os.type": platform.system().lower() or "unknown",
        "process.runtime.version": platform.python_version(),
        "fc.build": "standalone" if frozen else "python",
    }
