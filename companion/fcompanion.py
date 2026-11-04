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
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

ADDON = "ForeverChronicaller"
VERSION = "0.3.1"
USER_AGENT = f"ForeverChronicallerCompanion/{VERSION}"
DEFAULT_REPO = "SaffronG/ForeverChronicaller"

TERMS_VERSION = 1  # bump when PRIVACY.md changes in a way users must agree to again
PRIVACY_URL = "https://github.com/SaffronG/ForeverChronicaller/blob/main/PRIVACY.md"

DISCLAIMER = f"""\
==============================================================================
 Forever Chronicaller - before you install (terms version {TERMS_VERSION})
==============================================================================
 PERMISSIONS - this program will:
   * write the addon into <WoW folder>/Interface/AddOns/ForeverChronicaller
   * keep its settings, state and backups in its own folder
   * list running program NAMES to check WoW is closed before changing files
   * read the addon's saved files (only if you use Discord/phone posting)
   * connect to GitHub for updates; to Discord / ntfy / telemetry only if
     you set those up. The addon itself can't use the internet at all.

 DATA:
   * Your chronicle and goals stay on your computer.
   * Nothing is sent anywhere unless you turn it on. Sharing goals sends
     the goal (and your character name) to the players you choose.
   * Telemetry (anonymous diagnostics) is OFF by default and opt-in only.
     It never contains names, chronicle text or chat.

 RISKS:
   * A failed or interrupted update can leave the addon broken. The old
     version is backed up first and restored automatically if the swap
     fails; your chronicle (in WTF/) is never touched by updates.
   * New, hobby software, mostly tested outside the real game: expect bugs.
   * The program is unsigned: Windows may warn about an unknown publisher.
   * Provided as is, without warranty. Use at your own risk.

 Full details: {{privacy}}
==============================================================================
"""

# True when running as a standalone program built with PyInstaller (no Python needed).
FROZEN = bool(getattr(sys, "frozen", False))


def prog() -> str:
    """How the player runs this program, for messages."""
    if FROZEN:
        name = Path(sys.executable).name
        return name if os.name == "nt" else f"./{name}"
    return "python fcompanion.py"

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
        "github_repo": DEFAULT_REPO,  # "owner/repo" for updates
        "accepted_terms": 0,       # TERMS_VERSION the user agreed to (0 = not yet)
        "accepted_terms_at": 0,
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


# ------------------------------------------------------------- install / update

class UpdateError(Exception):
    pass


MAX_UNZIPPED = 20 * 1024 * 1024  # an addon zip is ~100 KB; refuse anything absurd


def version_tuple(v: str):
    return tuple(int(n) for n in re.findall(r"\d+", str(v))) or (0,)


def addon_dir(wow_path: str) -> Path:
    return Path(wow_path) / "Interface" / "AddOns" / ADDON


def installed_version(wow_path: str) -> Optional[str]:
    toc = addon_dir(wow_path) / f"{ADDON}.toc"
    if not toc.exists():
        return None
    m = re.search(r"^## Version:\s*(\S+)", toc.read_text(encoding="utf-8", errors="replace"), re.M)
    return m.group(1) if m else "0"


def check_zip(zip_path: Path) -> str:
    """Validate an addon zip and return the version inside. Raises UpdateError."""
    try:
        zf = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile:
        raise UpdateError("not a valid zip file")
    with zf:
        total = 0
        for info in zf.infolist():
            name = info.filename
            parts = Path(name).parts
            if name.startswith(("/", "\\")) or ".." in parts or ":" in name or not parts or parts[0] != ADDON:
                raise UpdateError(f"unexpected path in zip: {name!r}")
            total += info.file_size
            if total > MAX_UNZIPPED:
                raise UpdateError("zip is too large")
        try:
            toc = zf.read(f"{ADDON}/{ADDON}.toc").decode("utf-8", "replace")
        except KeyError:
            raise UpdateError(f"zip doesn't contain {ADDON}/{ADDON}.toc")
    m = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    if not m:
        raise UpdateError("no version in the zip's .toc")
    return m.group(1)


def game_running() -> bool:
    """Best effort: is a WoW client process running?"""
    # Only look at process *names* (not full command lines), so e.g. an editor
    # with a path to Wow.exe open doesn't count.
    try:
        if os.name == "nt":
            out = subprocess.run(["tasklist", "/fo", "csv", "/nh"], capture_output=True, text=True, timeout=10).stdout
            names = [line.split('","')[0].strip('"') for line in out.splitlines() if line]
        else:
            out = subprocess.run(["ps", "-eo", "comm="], capture_output=True, text=True, timeout=10).stdout
            names = [line.strip() for line in out.splitlines()]
    except (OSError, subprocess.SubprocessError):
        return False
    return any(re.fullmatch(r"wow[\w-]*\.exe", n, re.I) for n in names)


def install_zip(zip_path: Path, wow_path: str, log: Callable[[str], None] = print) -> str:
    """Install/replace the addon from a zip. The old version is kept in the backups folder.
    Returns the installed version."""
    version = check_zip(zip_path)
    addons = Path(wow_path) / "Interface" / "AddOns"
    if not Path(wow_path).is_dir():
        raise UpdateError(f"WoW folder not found: {wow_path}")
    addons.mkdir(parents=True, exist_ok=True)
    target = addons / ADDON
    backup = None
    with tempfile.TemporaryDirectory(dir=str(addons.parent)) as tmp:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(tmp)  # paths were validated by check_zip
        if target.exists():
            backups = config_dir() / "backups"
            backups.mkdir(parents=True, exist_ok=True)
            backup = backups / f"{ADDON}-{installed_version(wow_path) or 'old'}-{int(time.time())}"
            shutil.move(str(target), str(backup))
        try:
            shutil.move(str(Path(tmp) / ADDON), str(target))
        except Exception:
            if backup is not None and not target.exists():
                shutil.move(str(backup), str(target))  # put the old version back
            raise
    if backup:
        log(f"Previous version backed up to {backup}")
    return version


def looks_like_wow(path: Path) -> bool:
    """A WoW client folder has a Wow*.exe (or at least Interface/ or WTF/)."""
    if not path.is_dir():
        return False
    if any(p.is_file() for p in path.glob("Wow*.exe")) or any(p.is_file() for p in path.glob("wow*.exe")):
        return True
    return (path / "WTF").is_dir() or (path / "Interface" / "AddOns").is_dir()


def wow_search_roots() -> List[Path]:
    roots: List[Path] = []
    if os.name == "nt":
        for drive in "CDEFGH":
            base = Path(f"{drive}:/")
            if base.exists():
                roots += [base, base / "Program Files (x86)", base / "Program Files", base / "Games"]
    else:
        home = Path.home()
        roots += [home / "Games", home / "games", home / ".wine" / "drive_c" / "Program Files (x86)",
                  home / ".wine" / "drive_c" / "Program Files", home / ".local" / "share" / "lutris"]
        roots += [Path(p) for p in glob.glob(str(home / "Games" / "*" / "drive_c" / "Program Files*"))]
    return roots


def find_wow_dirs(roots: Optional[List[Path]] = None) -> List[Path]:
    """Look for WoW client folders (incl. _retail_-style subfolders) under common install locations."""
    found: List[Path] = []
    for root in roots if roots is not None else wow_search_roots():
        try:
            children = [c for c in root.iterdir() if c.is_dir()]
        except OSError:
            continue
        for child in children:
            name = child.name.lower()
            if "warcraft" not in name and "wow" not in name and "forever" not in name:
                continue
            candidates = [child] + [c for c in child.glob("_*_") if c.is_dir()]
            for c in candidates:
                if any(x.is_file() for x in c.glob("[Ww]ow*.exe")) and c not in found:
                    found.append(c)
    return found


def bundle_places() -> List[Path]:
    """Where files shipped with the program live: inside the standalone program,
    next to it, or next to this script."""
    places = []
    if FROZEN and getattr(sys, "_MEIPASS", None):
        places.append(Path(sys._MEIPASS))           # embedded in the .exe / binary
    if FROZEN:
        places.append(Path(sys.executable).resolve().parent)
    places.append(Path(__file__).resolve().parent)
    places.append(Path(__file__).resolve().parent.parent)  # repo checkout
    return places


def privacy_location() -> str:
    for place in bundle_places():
        if (place / "PRIVACY.md").is_file():
            return f"{place / 'PRIVACY.md'}\n               or {PRIVACY_URL}"
    return PRIVACY_URL


def ensure_terms(cfg: Dict[str, Any], accept_flag: bool = False, interactive: bool = True) -> bool:
    """Show the disclaimer and get explicit agreement once per terms version."""
    if int(cfg.get("accepted_terms") or 0) >= TERMS_VERSION:
        return True
    print(DISCLAIMER.format(privacy=privacy_location()))
    if accept_flag:
        print("Agreed via --accept-terms.")
    elif not interactive:
        print("Not agreed. Run again without --yes to answer, or add --accept-terms.")
        return False
    else:
        answer = input("Type 'yes' to agree and continue (anything else cancels): ").strip().lower()
        if answer not in ("yes", "y"):
            print("Cancelled. Nothing was installed or changed.")
            return False
    cfg["accepted_terms"] = TERMS_VERSION
    cfg["accepted_terms_at"] = int(time.time())
    return True


def bundled_zip() -> Optional[Path]:
    """The addon zip shipped with the installer."""
    zips = []
    for place in bundle_places():
        zips += place.glob(f"{ADDON}-[0-9]*.zip")
    zips.sort(key=lambda p: version_tuple(p.name))
    return zips[-1] if zips else None


Fetch = Callable[[str], bytes]


def _http_get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def latest_release(repo: str, fetch: Fetch = _http_get) -> Dict[str, str]:
    """{'version': '0.3.0', 'url': <addon zip download url>} for the newest GitHub release."""
    if not re.match(r"^[\w.-]+/[\w.-]+$", repo or ""):
        raise UpdateError("set github_repo (owner/repo) in the config first")
    try:
        data = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))
    except urllib.error.HTTPError as e:
        raise UpdateError(f"GitHub answered {e.code} (no releases yet?)")
    except (urllib.error.URLError, OSError) as e:
        raise UpdateError(f"couldn't reach GitHub ({e})")
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        if re.match(rf"^{ADDON}-[\d.]+\.zip$", name):
            url = asset.get("browser_download_url", "")
            if not url.startswith("https://github.com/"):
                raise UpdateError("unexpected download location")
            return {"version": str(data.get("tag_name", "")).lstrip("v"), "url": url}
    raise UpdateError("the latest release has no addon zip")


def update(cfg: Dict[str, Any], fetch: Fetch = _http_get, check_only: bool = False, force: bool = False,
           log: Callable[[str], None] = print, running: Callable[[], bool] = game_running) -> bool:
    """Install the latest release if it's newer. Returns True if something was installed."""
    current = installed_version(cfg["wow_path"])
    latest = latest_release(cfg.get("github_repo", ""), fetch)
    if current and version_tuple(latest["version"]) <= version_tuple(current):
        log(f"Forever Chronicaller {current} is up to date.")
        return False
    log(f"New version available: {latest['version']} (installed: {current or 'none'}).")
    if check_only:
        log(f"Run `{prog()} update` to install it.")
        return False
    if running() and not force:
        log("WoW seems to be running. Close it first (or use --force, then restart the game: "
            "/reload is not enough when files were added).")
        return False
    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp) / "addon.zip"
        zip_path.write_bytes(fetch(latest["url"]))
        version = install_zip(zip_path, cfg["wow_path"], log)
    log(f"Installed Forever Chronicaller {version}.")
    return True


# ---------------------------------------------------------------------- commands

def ask(prompt: str, current: str = "") -> str:
    shown = f" [{current}]" if current else ""
    answer = input(f"{prompt}{shown}: ").strip()
    return answer or current


def cmd_setup(cfg: Dict[str, Any], args) -> int:
    if not ensure_terms(cfg, getattr(args, "accept_terms", False)):
        return 1
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
    cfg["github_repo"] = ask("GitHub repository for updates, owner/repo (empty to skip)", cfg["github_repo"])
    path = save_config(cfg)
    print(f"\nSaved to {path}")
    print(f"Next: run `{prog()} test`, then `{prog()} watch` while you play.")
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
        print(f"Run `{prog()} setup` first.")
        return 1
    if not cfg.get("discord_webhook") and not cfg.get("ntfy_topic"):
        print("No Discord webhook or ntfy topic configured; entries will only be listed here.")
    if cfg.get("github_repo"):
        try:
            update(cfg, check_only=True)
        except UpdateError as e:
            print(f"(Update check skipped: {e})")
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


def cmd_update(cfg: Dict[str, Any], args) -> int:
    if not cfg.get("wow_path"):
        print(f"Run `{prog()} setup` first.")
        return 1
    if not args.check:
        if not ensure_terms(cfg, args.accept_terms):
            return 1
        save_config(cfg)
    try:
        if args.zip:
            if game_running() and not args.force:
                print("WoW seems to be running. Close it first, or use --force.")
                return 1
            version = install_zip(Path(args.zip), cfg["wow_path"])
            print(f"Installed Forever Chronicaller {version}.")
        else:
            update(cfg, check_only=args.check, force=args.force)
    except UpdateError as e:
        print(f"Update failed: {e}")
        return 1
    return 0


def choose_wow_path(cfg: Dict[str, Any], given: Optional[str], assume_yes: bool) -> Optional[str]:
    if given:
        return given
    if cfg.get("wow_path") and looks_like_wow(Path(cfg["wow_path"])):
        return cfg["wow_path"]
    found = find_wow_dirs()
    if len(found) == 1 and (assume_yes or input(f"Install into {found[0]}? [Y/n]: ").strip().lower() in ("", "y", "yes")):
        return str(found[0])
    if len(found) > 1:
        print("Found several WoW folders:")
        for i, p in enumerate(found, 1):
            print(f"  {i}. {p}")
        pick = input("Which one? (number, or paste a path): ").strip()
        if pick.isdigit() and 1 <= int(pick) <= len(found):
            return str(found[int(pick) - 1])
        return pick or None
    print("Couldn't find WoW: Forever automatically.")
    path = input("Paste the WoW: Forever folder (the one with Wow.exe in it): ").strip().strip('"')
    return path or None


def cmd_install(cfg: Dict[str, Any], args) -> int:
    if not ensure_terms(cfg, args.accept_terms, interactive=not args.yes):
        return 1
    wow = choose_wow_path(cfg, args.wow, args.yes)
    if not wow:
        print("No folder chosen; nothing installed.")
        return 1
    if not looks_like_wow(Path(wow)):
        print(f"{wow} doesn't look like a WoW folder (no Wow*.exe, Interface or WTF).")
        if args.yes or input("Install there anyway? [y/N]: ").strip().lower() not in ("y", "yes"):
            return 1
    if game_running() and not args.force:
        print("WoW seems to be running. Close it, then run the installer again.")
        return 1
    cfg["wow_path"] = wow
    try:
        if args.zip:
            version = install_zip(Path(args.zip), wow)
        elif bundled_zip():
            version = install_zip(bundled_zip(), wow)
        elif cfg.get("github_repo"):
            update(cfg, force=args.force)
            version = installed_version(wow)
        else:
            print("No addon zip found next to the installer and no github_repo configured.")
            return 1
    except UpdateError as e:
        print(f"Install failed: {e}")
        return 1
    save_config(cfg)
    print(f"\nForever Chronicaller {version} is installed in {addon_dir(wow)}")
    print("Start the game, make sure it's enabled in the AddOns list, and type /chron in game.")
    print(f"Optional: `{prog()} setup` for Discord / phone notifications.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="fcompanion", description="Forever Chronicaller companion app")
    p.add_argument("--version", action="version", version=VERSION)
    sub = p.add_subparsers(dest="command", required=True)
    st = sub.add_parser("setup", help="configure the WoW folder, Discord and ntfy")
    st.add_argument("--accept-terms", action="store_true", help="agree to the terms in PRIVACY.md without being asked")
    sub.add_parser("privacy", help="show permissions, data and risks (the install disclaimer)")
    sub.add_parser("test", help="send a test notification")
    w = sub.add_parser("watch", help="post new chronicle entries while you play")
    w.add_argument("--once", action="store_true", help="check once and exit")
    i = sub.add_parser("install", help="find WoW: Forever and install the addon")
    i.add_argument("--wow", help="the WoW: Forever folder (skip auto-detection)")
    i.add_argument("--zip", help="install this addon zip")
    i.add_argument("--yes", action="store_true", help="don't ask questions")
    i.add_argument("--force", action="store_true", help="install even if the game is running")
    i.add_argument("--accept-terms", action="store_true", help="agree to the terms in PRIVACY.md without being asked")
    u = sub.add_parser("update", help="install the latest addon release (or a zip you have)")
    u.add_argument("--check", action="store_true", help="only check, don't install")
    u.add_argument("--force", action="store_true", help="install even if the game is running")
    u.add_argument("--zip", help="install this zip instead of downloading")
    u.add_argument("--accept-terms", action="store_true", help="agree to the terms in PRIVACY.md without being asked")
    return p


def cmd_privacy(cfg: Dict[str, Any], args) -> int:
    print(DISCLAIMER.format(privacy=privacy_location()))
    agreed = int(cfg.get("accepted_terms") or 0)
    print(f"You agreed to terms version {agreed}." if agreed else "You haven't agreed to the terms yet.")
    return 0


COMMANDS = {"setup": cmd_setup, "test": cmd_test, "watch": cmd_watch, "update": cmd_update, "install": cmd_install, "privacy": cmd_privacy}


def main(argv: Optional[List[str]] = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    # Double-clicked standalone program (no arguments): run the installer and keep
    # the window open at the end so the player can read what happened.
    double_clicked = FROZEN and not argv
    if double_clicked:
        argv = ["install"]
        print(f"Forever Chronicaller installer {VERSION}\n")
    try:
        args = build_parser().parse_args(argv)
        cfg = load_config()
        return COMMANDS[args.command](cfg, args)
    except KeyboardInterrupt:
        return 1
    except Exception as e:  # show the problem instead of a window that just vanishes
        if not double_clicked:
            raise
        print(f"\nSomething went wrong: {type(e).__name__}: {e}")
        return 1
    finally:
        if double_clicked:
            try:
                input("\nPress Enter to close...")
            except EOFError:
                pass


if __name__ == "__main__":
    sys.exit(main())
