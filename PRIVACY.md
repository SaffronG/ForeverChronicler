# Privacy, permissions and risks

**Terms version 1.** The installer shows a summary of this page and asks you to agree before it installs anything.

Forever Chronicaller has two parts:
- **The addon** runs inside WoW: Forever.
- **The companion app** (`ForeverChronicaller-Installer` / `fcompanion.py`) runs on your computer. It installs and updates the addon, and can optionally post to Discord or your phone.

You can use the addon without the companion.

**In short:**
- **Nothing is sent anywhere unless you turn it on.**
- Your chronicle stays on your computer.
- Telemetry (anonymous diagnostics) is **off by default** and never contains your character names, chat or chronicle text.

---

## 1. What each part can access (permissions)

### The addon (inside the game)
WoW gives addons a sandbox. They **cannot** use the internet, read or write your files, or run programs. Within that sandbox, this addon:

| Accesses | Why |
|---|---|
| Your character's level, XP, zone, money, quests turned in, deaths, achievements, map position | To write the chronicle, check goals and draw graphs |
| Its own saved data (`WTF/Account/<account>/<realm>/<character>/SavedVariables/ForeverChronicaller.lua`) | To remember your chronicle, goals and settings. WoW writes this file on logout or `/reload` |
| Your friend list's online status and group roster | To know when friends can receive together-goal updates |
| **Hidden addon messages** to your group, or whispers to players you choose | Only when you share a goal, use together goals, or are in a group (version check). See [section 2](#2-what-data-exists-and-where-it-goes) |
| The world map and the game's waypoint arrow | Location goals |

### The companion app (on your computer)
| Permission | What exactly | When |
|---|---|---|
| **Read** files | The addon's SavedVariables files under your WoW folder's `WTF` folder | `watch` (and telemetry, if you opt in) |
| **Write** files | `Interface/AddOns/ForeverChronicaller/` (installing and updating the addon). Its own folder: `%APPDATA%\forever-chronicaller\` on Windows, `~/.config/forever-chronicaller/` on Linux (config, state, backups, telemetry spool) | `install`, `update`, `setup`, `watch` |
| **List running programs** | Process **names** only (`tasklist` / `ps`), to check whether WoW is running before replacing files | `install`, `update` |
| **Network** | `api.github.com` and `github.com` (update checks and downloads); your Discord webhook; your ntfy server; the telemetry endpoint, **only if you opt in** | Only for the features you use |

It **never** reads your WoW account password or login, game memory, chat logs, screenshots, or anything outside the folders above. It never runs anything from your saved data, which it reads as plain data.

Administrator rights are not required. If WoW is installed in a protected folder (such as `Program Files`), Windows may ask.

---

## 2. What data exists and where it goes

| Data | Stored | Leaves your computer? |
|---|---|---|
| Chronicle entries, goals, notes, stats, progress samples | Your SavedVariables file (local) | **No**, unless you set up Discord/ntfy (below) or export it yourself |
| Settings, error log | SavedVariables (local) | No (telemetry, if you opt in, sends errors with personal data removed; see section 3) |
| Companion config: WoW folder, Discord webhook URL, ntfy topic | `config.json` (local; readable only by you on Linux/macOS) | No. The webhook URL is never printed or logged |
| **Shared goals** (`/chron share`) | Sent as an addon message | **Yes, to the players you share with**: goal text, notes and type, and your character name, which the game attaches to every message |
| **Together goals** (`/chron together`) | Sent as addon whispers | **Yes, to the members of that goal**: goal text and members' names and progress times |
| **Version check** | Sent to your group | **Yes, to your group**: the addon version number |
| **Discord / ntfy posts** (optional) | Sent by the companion | **Yes, to that Discord channel or ntfy topic**: new chronicle entries (text, level, zone) and your character and realm name. Anyone who can read the channel or knows the ntfy topic can read them. Public ntfy topics are not private |
| **Update checks** | Companion → GitHub | GitHub sees a normal web request: your IP address and the program version |
| **Telemetry** | Off by default | Only if you opt in: see section 3 |

The maintainer runs **no server** that receives your chronicle, goals, names or game data.

---

## 3. Telemetry (opt-in, off by default)

> Telemetry is being added in the next version. Until then nothing is collected. This section describes what it will and will not contain.

Telemetry helps fix bugs: which version crashed where, and how long things take. It is:

- **Off by default.** You're asked once (the default answer is *No*), and you can change it any time with `ForeverChronicaller-Installer telemetry on|off`.
- **Anonymous.** It's identified only by a random ID created when you opt in and deleted when you opt out. It isn't linked to your WoW account, characters or computer name.

**Would be collected (only when opted in):**
- Addon and companion **version**, operating system type (Windows/Linux/macOS), Python version.
- **Errors**: the error type, plus the file and line where it happened (for example `Goals.lua:42: attempt to index a nil value`). Quoted text, numbers that could identify you, file paths before `Interface/AddOns`, and user names are removed.
- **Traces and latency** of companion operations (install, update, download, posting to Discord/ntfy): how long each step took and whether it succeeded, with HTTP status codes but never URLs.
- In-game performance, only if you also turn on *Performance diagnostics* in the addon options: how many times each internal handler ran and how long it took (names like `PLAYER_LEVEL_UP`, never your data).

**Never collected:** character, account, realm or friend names; chronicle, goal or note text; chat; zone names; map coordinates; your WoW folder path; the Discord webhook or ntfy topic; your computer or user name.

**Where it goes:** to an OpenTelemetry endpoint run by the maintainer. The endpoint is shown when you opt in. If no endpoint is configured, opted-in data is only written to a local file (`telemetry-spool.jsonl` in the companion folder) that you can read and delete. Like any web request, the endpoint can see your IP address.

---

## 4. Risks

Please read these before installing.

| Risk | What could happen | What protects you | What you can do |
|---|---|---|---|
| **Botched or interrupted update** | A crash, full disk or power cut while the companion swaps addon files could leave the addon folder missing or incomplete, so the addon doesn't load | Every zip is checked before anything is touched (paths, size, required files). The old version is **moved to a backup folder first** and **put back automatically** if the swap fails | Restore from `backups/` in the companion folder, or reinstall. **Your chronicle is not in the addon folder** (it's in `WTF/`), so updates never touch it. Back it up anyway: `/chron export` |
| **Updating while the game runs** | WoW may load a mix of old and new files, causing errors until you restart | Install and update refuse while WoW runs (unless you use `--force`) | Close WoW first. After an update, restart the game; `/reload` isn't enough when files were added |
| **A bad release** | A new version could have a bug that breaks a feature | Each feature is isolated, so an error in one doesn't stop the chronicle. `/chron errors` shows what failed. Releases are only published after automated tests pass | Reinstall the previous version from `backups/` or from the GitHub releases page |
| **Untested in the real game** | This is a new project. Many parts have been tested against a simulated game, not WoW: Forever itself | Error isolation and logging, as above | Report problems with the output of `/chron errors` |
| **Data loss in game** | The chronicle size limit (if you set one) deletes the oldest entries. *Import → Replace* overwrites your data | The limit is off by default. Replace asks first, and `/chron import undo` works until you log out | Keep `/chron export` backups, or copy your SavedVariables file |
| **Unsigned program** | Windows SmartScreen shows "unknown publisher", and some antivirus tools wrongly flag programs built with PyInstaller | The `.exe` is built by GitHub Actions from the public source code; the build log and release are public | Download only from the official [releases page](https://github.com/SaffronG/ForeverChronicaller/releases) |
| **Third-party services** | Discord, ntfy, GitHub and the telemetry provider have their own privacy policies. A leaked webhook URL lets others post to your channel | All optional. The webhook is stored locally and never logged | Use a hard-to-guess ntfy topic. Delete and recreate the webhook if it leaks |
| **Shared/together goals are trust-based** | Another player could fake their progress on a goal you share with them | Only members can update a goal, nobody can mark *your* part done, and all messages are validated | Only do together goals with people you trust |
| **Server rules** | WoW: Forever may have its own rules about addons or outside programs | The companion only reads and writes files. It never touches the game client, its memory or network traffic | Check the server's rules |

---

## 5. Your controls

- **See what's stored:** `/chron export` (in game), or open the SavedVariables file and the companion's `config.json` in a text editor.
- **Delete everything:**
  - Delete `Interface/AddOns/ForeverChronicaller/`, the addon's SavedVariables files, and the companion folder (`%APPDATA%\forever-chronicaller` or `~/.config/forever-chronicaller`).
  - Remove the Discord webhook in Discord.
- **Stop sharing:** don't use share or together goals, or turn off *Allow shared goals* in the options.

---

## 6. No warranty

This is a free, hobby project provided **as is**, without warranty of any kind. Use it at your own risk. The maintainer is not responsible for lost data, account actions by the server, or damage from using it.

Questions or problems: [open an issue](https://github.com/SaffronG/ForeverChronicaller/issues).
