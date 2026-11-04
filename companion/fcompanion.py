#!/usr/bin/env python3
"""Forever Chronicaller companion app.

Runs outside the game (Python 3.8+, standard library only).

    python fcompanion.py setup      # first-time configuration (WoW folder, Discord, ntfy)
    python fcompanion.py watch      # post new chronicle entries to Discord / your phone
    python fcompanion.py test       # send a test notification

WoW addons can't talk to the internet, and their saved data only reaches disk
when you log out or /reload. So `watch` polls the addon's SavedVariables files
and posts entries it hasn't posted before. In game, `/chron sync` reloads your
UI so new entries go out immediately.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

ADDON = "ForeverChronicaller"
VERSION = "0.3.0"
USER_AGENT = f"ForeverChronicallerCompanion/{VERSION}"

# Entry kinds the addon writes, and whether they're posted by default.
DEFAULT_KINDS = {
    "start": True, "level": True, "goal": True, "achievement": True, "death": True,
    "zone": True, "quest": False, "note": True,
}


# --------------------------------------------------------------------------- config

def config_dir() -> Path:
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return base / "forever-chronicaller"


def default_config() -> Dict[str, Any]:
    return {
        "wow_path": "",            # folder that contains Interface/ and WTF/
        "discord_webhook": "",     # secret - keep it private
        "ntfy_topic": "",          # e.g. "chase-wow-adventures-8f3k" (pick something hard to guess)
        "ntfy_server": "https://ntfy.sh",
        "post_kinds": dict(DEFAULT_KINDS),
        "characters": [],          # empty = all characters
        "poll_seconds": 5,
        "github_repo": "",         # "owner/repo" for updates
    }


def load_config(path: Optional[Path] = None) -> Dict[str, Any]:
    path = path or config_dir() / "config.json"
    cfg = default_config()
    if path.exists():
        with open(path, encoding="utf-8") as f:
            stored = json.load(f)
        cfg.update({k: v for k, v in stored.items() if k in cfg})
        kinds = dict(DEFAULT_KINDS)
        kinds.update(stored.get("post_kinds", {}))
        cfg["post_kinds"] = kinds
    return cfg


def save_config(cfg: Dict[str, Any], path: Optional[Path] = None) -> Path:
    path = path or config_dir() / "config.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    if os.name != "nt":
        os.chmod(tmp, 0o600)  # the webhook URL is a secret
    os.replace(tmp, path)
    return path


# ------------------------------------------------------- SavedVariables (Lua) parser

class LuaParseError(ValueError):
    pass


_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<number>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,;])
""", re.VERBOSE | re.DOTALL)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
            "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unescape(body: str) -> str:
    out = bytearray()
    i = 0
    raw = body.encode("utf-8", "surrogateescape")
    while i < len(raw):
        c = raw[i]
        if c != 0x5C:  # backslash
            out.append(c)
            i += 1
            continue
        i += 1
        if i >= len(raw):
            raise LuaParseError("bad escape at end of string")
        e = chr(raw[i])
        if e.isdigit():
            j = i
            while j < len(raw) and j < i + 3 and chr(raw[j]).isdigit():
                j += 1
            out.append(int(raw[i:j]) & 0xFF)
            i = j
        elif e in _ESCAPES:
            out += _ESCAPES[e].encode()
            i += 1
        else:
            out.append(raw[i])
            i += 1
    return out.decode("utf-8", "replace")


def _tokenize(text: str):
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise LuaParseError(f"unexpected character {text[pos]!r} at {pos}")
        pos = m.end()
        if m.group("ws") is not None or m.group("comment") is not None:
            continue
        for kind in ("string", "number", "name", "punct"):
            if m.group(kind) is not None:
                yield kind, m.group(kind)
                break


def _to_python(table: Dict[Any, Any]) -> Any:
    """Tables with keys 1..n become lists, everything else stays a dict."""
    n = len(table)
    if n and all(isinstance(k, int) for k in table) and set(table) == set(range(1, n + 1)):
        return [table[i] for i in range(1, n + 1)]
    return table


def parse_saved_variables(text: str) -> Dict[str, Any]:
    """Parse a WoW SavedVariables file: `Name = <value>` assignments. Never executes anything."""
    tokens = list(_tokenize(text))
    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else (None, None)

    def take(expected: Optional[str] = None):
        nonlocal pos
        if pos >= len(tokens):
            raise LuaParseError("unexpected end of file")
        tok = tokens[pos]
        if expected is not None and tok[1] != expected:
            raise LuaParseError(f"expected {expected!r}, got {tok[1]!r}")
        pos += 1
        return tok

    def value(depth=0):
        if depth > 50:
            raise LuaParseError("nested too deeply")
        kind, tok = take()
        if kind == "string":
            return _unescape(tok[1:-1])
        if kind == "number":
            if tok.lower().lstrip("-").startswith("0x"):
                return int(tok, 16)
            num = float(tok)
            return int(num) if num.is_integer() and not re.search(r"[.eE]", tok) else num
        if kind == "name":
            if tok == "true":
                return True
            if tok == "false":
                return False
            if tok == "nil":
                return None
            raise LuaParseError(f"unexpected name {tok!r}")
        if tok == "{":
            table: Dict[Any, Any] = {}
            index = 1
            while peek()[1] != "}":
                k, t = peek()
                if t == "[":
                    take("[")
                    key = value(depth + 1)
                    take("]")
                    take("=")
                    table[key] = value(depth + 1)
                elif k == "name" and pos + 1 < len(tokens) and tokens[pos + 1][1] == "=" and t not in ("true", "false", "nil"):
                    take()
                    take("=")
                    table[t] = value(depth + 1)
                else:
                    table[index] = value(depth + 1)
                    index += 1
                if peek()[1] in (",", ";"):
                    take()
            take("}")
            return _to_python(table)
        raise LuaParseError(f"unexpected {tok!r}")

    result: Dict[str, Any] = {}
    while pos < len(tokens):
        kind, name = take()
        if kind != "name":
            raise LuaParseError(f"expected a variable name, got {name!r}")
        take("=")
        result[name] = value()
    return result


# ------------------------------------------------------------------ finding the files

def saved_variable_files(wow_path: str) -> List[Path]:
    """Per-character SavedVariables files for this addon (any account/realm/character)."""
    pattern = os.path.join(wow_path, "WTF", "Account", "*", "*", "*", "SavedVariables", f"{ADDON}.lua")
    return [Path(p) for p in sorted(glob.glob(pattern))]


def character_of(path: Path) -> str:
    # .../WTF/Account/<account>/<realm>/<character>/SavedVariables/ForeverChronicaller.lua
    return f"{path.parent.parent.name}-{path.parent.parent.parent.name}"


# ------------------------------------------------------------------- formatting

_COLOR = re.compile(r"\|c[0-9a-fA-F]{8}|\|r")
_LINKS = re.compile(r"\|H[^|]*\|h(.*?)\|h")
_TEXTURES = re.compile(r"\|T[^|]*\|t")

EMOJI = {"start": "📜", "level": "⬆️", "goal": "🏆", "achievement": "🏅", "death": "💀",
         "zone": "🗺️", "quest": "❗", "note": "✏️"}


def clean_text(text: str) -> str:
    """Strip WoW colour codes, links and textures."""
    text = _LINKS.sub(r"\1", text)
    text = _TEXTURES.sub("", text)
    text = _COLOR.sub("", text)
    return text.replace("||", "|").strip()


def format_entry(e: Dict[str, Any]) -> str:
    emoji = EMOJI.get(e.get("kind", ""), "•")
    level = f"[{int(e['level'])}] " if isinstance(e.get("level"), (int, float)) else ""
    zone = f" — {e['zone']}" if e.get("zone") and e.get("kind") not in ("zone",) else ""
    return f"{emoji} {level}{clean_text(str(e.get('text', '')))}{zone}"


def batch_lines(lines: List[str], limit: int) -> List[str]:
    """Join lines into messages no longer than `limit` characters."""
    batches, current = [], ""
    for line in lines:
        line = line[:limit]
        if current and len(current) + 1 + len(line) > limit:
            batches.append(current)
            current = line
        else:
            current = f"{current}\n{line}" if current else line
    if current:
        batches.append(current)
    return batches


# -------------------------------------------------------------------- notifiers

Sender = Callable[[urllib.request.Request], None]


def _http_send(req: urllib.request.Request) -> None:
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                resp.read()
            return
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 2:  # rate limited
                retry = float(e.headers.get("Retry-After", "2") or 2)
                time.sleep(min(retry, 30))
                continue
            raise


def post_discord(webhook: str, character: str, lines: List[str], send: Sender = _http_send) -> int:
    count = 0
    for chunk in batch_lines(lines, 1900):
        body = json.dumps({
            "username": "Forever Chronicaller",
            "content": f"**{character}**\n{chunk}",
            "allowed_mentions": {"parse": []},  # never ping anyone from game text
        }).encode()
        req = urllib.request.Request(webhook, data=body, method="POST",
                                     headers={"Content-Type": "application/json", "User-Agent": USER_AGENT})
        send(req)
        count += 1
    return count


def post_ntfy(server: str, topic: str, character: str, lines: List[str], send: Sender = _http_send) -> int:
    count = 0
    url = f"{server.rstrip('/')}/{urllib.request.quote(topic)}"
    for chunk in batch_lines(lines, 3500):
        req = urllib.request.Request(url, data=chunk.encode("utf-8"), method="POST", headers={
            "Title": f"Forever Chronicaller - {character}".encode("ascii", "replace").decode(),
            "Tags": "scroll",
            "User-Agent": USER_AGENT,
        })
        send(req)
        count += 1
    return count


# ----------------------------------------------------------------------- watcher

def entry_key(e: Dict[str, Any]) -> str:
    return f"{e.get('t')}|{e.get('kind')}|{e.get('text')}"


class Watcher:
    """Finds chronicle entries that haven't been posted yet."""

    def __init__(self, cfg: Dict[str, Any], state_path: Optional[Path] = None, send: Sender = _http_send,
                 log: Callable[[str], None] = print):
        self.cfg = cfg
        self.state_path = state_path or config_dir() / "state.json"
        self.send = send
        self.log = log
        self.state = self._load_state()
        self.mtimes: Dict[str, float] = {}

    def _load_state(self) -> Dict[str, Any]:
        if self.state_path.exists():
            with open(self.state_path, encoding="utf-8") as f:
                return json.load(f)
        return {"characters": {}}

    def _save_state(self) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.state_path.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.state, f)
        os.replace(tmp, self.state_path)

    def new_entries(self, character: str, entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        st = self.state["characters"].setdefault(character, {"last_t": None, "keys_at_last_t": []})
        if st["last_t"] is None:
            # First time we see this character: don't flood the channel with history.
            self._mark(st, entries)
            return []
        last_t, seen = st["last_t"], set(st["keys_at_last_t"])
        fresh = [e for e in entries if isinstance(e, dict) and isinstance(e.get("t"), (int, float))
                 and (e["t"] > last_t or (e["t"] == last_t and entry_key(e) not in seen))]
        self._mark(st, entries)
        return fresh

    @staticmethod
    def _mark(st: Dict[str, Any], entries: List[Dict[str, Any]]) -> None:
        times = [e["t"] for e in entries if isinstance(e, dict) and isinstance(e.get("t"), (int, float))]
        if not times:
            return
        last_t = max(times)
        if st["last_t"] is not None and last_t < st["last_t"]:
            return  # older data (e.g. restored backup): keep our position
        st["last_t"] = last_t
        st["keys_at_last_t"] = [entry_key(e) for e in entries if isinstance(e, dict) and e.get("t") == last_t]

    def wanted(self, character: str, e: Dict[str, Any]) -> bool:
        chars = [c.lower() for c in self.cfg.get("characters") or []]
        if chars and character.lower() not in chars and character.split("-")[0].lower() not in chars:
            return False
        return bool(self.cfg["post_kinds"].get(e.get("kind"), False))

    def process_file(self, path: Path) -> int:
        """Post new entries from one SavedVariables file. Returns the number posted."""
        text = path.read_text(encoding="utf-8", errors="replace")
        data = parse_saved_variables(text).get("ForeverChronicallerDB")
        if not isinstance(data, dict):
            return 0
        entries = data.get("entries") or []
        if isinstance(entries, dict):  # sparse table
            entries = [entries[k] for k in sorted(entries) if isinstance(k, int)]
        character = character_of(path)
        fresh = [e for e in self.new_entries(character, entries) if self.wanted(character, e)]
        if fresh:
            lines = [format_entry(e) for e in sorted(fresh, key=lambda e: e["t"])]
            self.notify(character, lines)
            self.log(f"Posted {len(lines)} new entr{'y' if len(lines) == 1 else 'ies'} for {character}.")
        self._save_state()
        return len(fresh)

    def notify(self, character: str, lines: List[str]) -> None:
        if self.cfg.get("discord_webhook"):
            try:
                post_discord(self.cfg["discord_webhook"], character, lines, self.send)
            except Exception as e:  # keep running; report without leaking the webhook URL
                self.log(f"Discord post failed: {type(e).__name__}: {getattr(e, 'code', '')}")
        if self.cfg.get("ntfy_topic"):
            try:
                post_ntfy(self.cfg.get("ntfy_server") or "https://ntfy.sh", self.cfg["ntfy_topic"], character, lines, self.send)
            except Exception as e:
                self.log(f"ntfy post failed: {type(e).__name__}: {getattr(e, 'code', '')}")

    def poll_once(self) -> int:
        posted = 0
        for path in saved_variable_files(self.cfg["wow_path"]):
            try:
                mtime = path.stat().st_mtime
            except OSError:
                continue
            key = str(path)
            if self.mtimes.get(key) == mtime:
                continue
            self.mtimes[key] = mtime
            try:
                posted += self.process_file(path)
            except (LuaParseError, OSError, UnicodeError) as e:
                # The game may be in the middle of writing the file; try again next change.
                self.log(f"Couldn't read {path.name} for {character_of(path)} yet ({e}).")
                self.mtimes.pop(key, None)
        return posted


# ---------------------------------------------------------------------- commands

def ask(prompt: str, current: str = "") -> str:
    shown = f" [{current}]" if current else ""
    answer = input(f"{prompt}{shown}: ").strip()
    return answer or current


def cmd_setup(cfg: Dict[str, Any], args) -> int:
    print("Forever Chronicaller companion setup. Press Enter to keep the value in [brackets].\n")
    cfg["wow_path"] = ask("WoW: Forever folder (the one containing Interface and WTF)", cfg["wow_path"])
    if cfg["wow_path"] and not Path(cfg["wow_path"], "WTF").is_dir():
        print("  Note: no WTF folder there yet. It appears after you've logged in once.")
    hook = ask("Discord webhook URL (Server Settings > Integrations > Webhooks; leave empty to skip)",
               "(keep current)" if cfg["discord_webhook"] else "")
    if hook and hook != "(keep current)":
        if not re.match(r"^https://(?:\w+\.)?discord(?:app)?\.com/api/webhooks/", hook):
            print("  That doesn't look like a Discord webhook URL; saved anyway.")
        cfg["discord_webhook"] = hook
    cfg["ntfy_topic"] = ask("ntfy topic for phone notifications (install the ntfy app and subscribe; empty to skip)",
                            cfg["ntfy_topic"])
    path = save_config(cfg)
    print(f"\nSaved to {path}")
    print("Next: run `python fcompanion.py test`, then `python fcompanion.py watch` while you play.")
    return 0


def cmd_test(cfg: Dict[str, Any], args) -> int:
    if not cfg.get("discord_webhook") and not cfg.get("ntfy_topic"):
        print("Nothing to test: set a Discord webhook or ntfy topic with `setup` first.")
        return 1
    w = Watcher(cfg)
    w.notify("Test", ["📜 Forever Chronicaller companion is connected!"])
    print("Test notification sent (check Discord / your phone).")
    return 0


def cmd_watch(cfg: Dict[str, Any], args) -> int:
    if not cfg.get("wow_path"):
        print("Run `python fcompanion.py setup` first.")
        return 1
    if not cfg.get("discord_webhook") and not cfg.get("ntfy_topic"):
        print("No Discord webhook or ntfy topic configured; entries will only be listed here.")
    w = Watcher(cfg)
    files = saved_variable_files(cfg["wow_path"])
    print(f"Watching {len(files)} character file(s) under {cfg['wow_path']}. "
          "New entries are posted when you log out or type /chron sync in game. Ctrl+C to stop.")
    try:
        while True:
            w.poll_once()
            if args.once:
                return 0
            time.sleep(max(1, int(cfg.get("poll_seconds", 5))))
    except KeyboardInterrupt:
        print("Stopped.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="fcompanion", description="Forever Chronicaller companion app")
    p.add_argument("--version", action="version", version=VERSION)
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("setup", help="configure the WoW folder, Discord and ntfy")
    sub.add_parser("test", help="send a test notification")
    w = sub.add_parser("watch", help="post new chronicle entries while you play")
    w.add_argument("--once", action="store_true", help="check once and exit")
    return p


COMMANDS = {"setup": cmd_setup, "test": cmd_test, "watch": cmd_watch}


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    cfg = load_config()
    return COMMANDS[args.command](cfg, args)


if __name__ == "__main__":
    sys.exit(main())
