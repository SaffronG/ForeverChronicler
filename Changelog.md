# Changelog

Newest first. Every change gets an entry here and its own commit (see `CLAUDE.md`).

## [Unreleased]

### Changed
- **Fixed the addon's name: "Forever Chronicaller" is now "Forever Chronicler"** (`ForeverChronicler.toc`, `Interface/AddOns/ForeverChronicler/`, saved table `ForeverChroniclerDB`, chat prefix `[Chronicler]`, release files `ForeverChronicler-<version>.zip` / `ForeverChronicler-Installer-…`, companion config folder `forever-chronicler`, repository `SaffronG/ForeverChronicler`). Slash commands (`/chron`, `/fc`) and the addon-message prefix `FChron` are unchanged, so players on older versions still sync with you.
- **Your chronicle is carried over.** The addon also loads the old `ForeverChronicallerDB` and adopts it if this character's new chronicle is still fresh. Otherwise the old data is left alone, never deleted. The installer moves the old `ForeverChronicaller` addon folder to its backups (both would load otherwise), copies each character's `ForeverChronicaller.lua` saved file to `ForeverChronicler.lua` (originals kept), copies the old config folder, and switches the update repository to the new name. The companion's watcher reads either name. `TERMS_VERSION` 2: the disclaimer lists the one-time copy.
- **Upgrading from 0.5.0 or older:** the updater built into older installers looks for the old file names and can't find this version, so download the new installer once. Manual installs: see "Upgrading from 0.5.0 or older" in the README. Released Changelog sections keep the old name, because that's what those versions were called.
- Still to test: the companion tests (CI runs them, Python wasn't available locally), and the carry-over in game.

## [0.5.0] - 2026-11-05

A new look: the window is styled after the night elves, and the chronicle is written on a parchment scroll, with every event keeping its colour. Telemetry stays switched off.

### Changed
- **New look: night elf style.** The main window has a moonlit sky (violet to deep teal), stars, a crescent moon, moon-silver borders and a Morpheus title. Tabs and buttons in the window (Goals, Journey, Professions) are restyled to match, and the active tab glows teal (new `src/ui/Theme.lua`).
- **The chronicle is written on a parchment scroll**, with aged edges and wooden rollers. Every event keeps its colour: bright colours made for dark backgrounds are shown as darker ink of the same hue (dates, levels and notes as brown ink), so they're readable on the paper. Saved entries and chat output are unchanged.
- Still to test in game: whether the parchment atlas is found (otherwise a drawn parchment is used), the Morpheus font, the crescent moon, and that every entry colour reads well.

## [0.4.2] - 2026-11-04

Adds professions, crafting and recipes to the chronicle, with recipe % completion, a Professions tab and Recipes/Crafts graphs. Telemetry stays switched off.

### Changed
- Confirmed in game on WoW: Forever 1.60.1: version 0.4.1 loads (Interface `16001`, files in `src/` subfolders), and goals, notes and saved data work across `/reload`.

### Added
- **Professions, crafting and recipes in the chronicle** (new `src/chronicle/Professions.lua`). Each type can be switched off in the options:
  - *Profession milestones:* learning a profession, every 25 skill points, max skill reached, unlearning. The first scan on a character is silent, so you don't get entries for what you already have.
  - *Recipes learned:* "Learned recipe: Silk Robe (Tailoring)" and recipe ranks. A burst of more than 3 (a trainer visit or a new profession) is summed up as "Learned 12 new Tailoring recipes".
  - *Crafting:* the first time you craft each item, plus milestones (10, 50, 100, 250, 500, then every 1000 crafts). Repeat crafts are only counted.
- **Recipe % completion** per profession. Recipes are counted while your own profession window is open (linked, guild and NPC-crafting windows are ignored), then kept up to date as you learn more.
- **Professions tab** (`/chron professions`, or `/chron professions list` for chat): one row per profession, with a skill bar, a recipe-completion bar with %, and how many items you crafted.
- **Recipes and Crafts graphs** in the Journey tab. Samples from before this version are skipped for these two series.
- Export/import includes professions and crafted-item counts (validated on import). The companion knows the new entry types but **doesn't post them unless you turn them on** in `post_kinds`.
- Still to test in game: that the profession events (`NEW_RECIPE_LEARNED`, `TRADE_SKILL_ITEM_CRAFTED_RESULT`, `SKILL_LINES_CHANGED`) fire on WoW: Forever, that recipe totals look right, and how the Professions tab looks. Events the client doesn't know are skipped instead of breaking the addon.

## [0.4.1] - 2026-11-04

Fixes the "Incompatible" status in the AddOns list (correct Interface number for WoW: Forever 1.60.1) and reorganizes the code into `src/`. Telemetry stays switched off.

### Fixed
- **Addon showed as "Incompatible".** The `.toc` `## Interface:` number was a guess (`120105`). WoW: Forever 1.60.1 actually reports `16001` (`select(4, GetBuildInfo())`), so the `.toc` now uses `16001`.

### Changed
- **Reorganized the repository.** Addon code moved from the root into `src/`, grouped by feature: `src/core/` (Core, Comms, VersionCheck), `src/chronicle/` (Chronicle, Journey), `src/goals/` (Goals, MapGoals, MapPins, Tracker), `src/sharing/` (Sharing, SharedGoals, Export) and `src/ui/` (Settings, UI). `Topology.md` and `TODO.md` moved to `docs/`. The `.toc` lists the new paths (load order unchanged), CI checks the XML files the `.toc` lists, and the telemetry scrubber also strips the new `src/<folder>/` prefix so error locations stay `File.lua:line`. Nothing changes for players: the release zip still has the `.toc` at the top of the `ForeverChronicaller/` folder. Still to test in game: that the client loads files from subfolders listed with `/` in the `.toc`.

## [0.4.0] - 2026-11-03

Adds an install-time disclaimer (privacy, permissions, risks). Telemetry is built and tested but **switched off by a feature flag**: this version collects nothing. It's planned to be switched on with the Grafana dashboard in 0.4.1.

### Changed
- **Telemetry is behind feature flags that are off** (`FEATURE_TELEMETRY = False` in the companion, `FC.FEATURES.diagnostics = false` in the addon). There's no opt-in question at install or setup, no `telemetry` command or `--telemetry` flag, no in-game diagnostics option or `/chron diagnostics`, and nothing is timed, collected or sent, even if a config file says "enabled". The disclaimer and `PRIVACY.md` say "no telemetry in this version" and describe the planned opt-in design separately. The code stays tested with the flags switched on in tests, and new tests check the shipped flag-off behaviour. The release smoke test checks that telemetry is unavailable.

### Added
- (Built but switched off, see *Changed*.) **Opt-in anonymous telemetry** (OpenTelemetry, OTLP/HTTP JSON; new `companion/fc_telemetry.py`, standard library only). **Off by default.**
  - The installer and `setup` ask once, with the default answer **No**, and remember the answer. `--yes` never opts in; only answering yes or `--telemetry` does.
  - `telemetry status | on | off | show | send`. `off` deletes the random install ID and all locally stored diagnostics.
  - **Traces:** spans for every command and step (`install.verify_zip`, `install.swap`, `update.check`, `update.download`, `watch.*`, `http.post`) with parent/child links, status and scrubbed exception events.
  - **Metrics:** `fc.operations`, `fc.operation.duration` (latency histogram), `fc.errors` (by type, code location and operation).
  - **Addon errors linked to a version:** `fc.addon.errors` (by addon version, `File.lua:line`, handler) plus `addon.error` spans with stack locations.
  - **In-game latency:** `fc.addon.handler.duration` and `.errors` histograms per handler.
  - Every free-text value is scrubbed (quoted text, paths, URLs, e-mail addresses, long numbers, colour codes), and only code names are accepted as labels. A test fills the saved data with personal data and checks that none of it appears in what would be sent. Payloads were checked against the official OTLP protobuf schema.
  - Destination: the `OTEL_ENDPOINT` / `OTEL_HEADERS` repository secrets baked into release builds, or the standard `OTEL_EXPORTER_OTLP_*` environment variables. Without an endpoint, opted-in data stays in a local spool file. Sending never blocks or breaks the program.
- Addon: errors now record the **addon version** and the **handler** that failed (local `/chron errors` log). (Switched off:) opt-in **Performance diagnostics** (options page or `/chron diagnostics on|off`, off by default): every event, message and command handler is timed into local latency buckets, which reset when the version changes and are deleted when turned off. The addon itself still sends nothing.
- The release workflow bakes in the telemetry endpoint from secrets (if set), and the smoke test checks that telemetry is off out of the box.

### Fixed
- Companion network functions (GitHub, Discord, ntfy) are looked up when called, not when defined, so tests can no longer accidentally reach the internet.
- `/chron diagnostics off` no longer re-records its own timing after deleting the data.
- All installer questions treat a closed input stream as the safe default (no / cancel).

### Added
- `PRIVACY.md`: privacy, permissions and risks (terms version 1). It covers what the addon and companion can access, what data exists and where it goes (a table per data type), opt-in telemetry (what would and would never be collected), a risk table (botched or interrupted update, updating while the game runs, bad releases, untested-in-game code, in-game data loss, the unsigned `.exe`, third-party services, trust in together goals, server rules) with protections and what you can do, how to see or delete everything, and a no-warranty notice. Shipped in the addon zip, the installer bundle and the standalone installers.
- Install-time disclaimer: `install`, `update` and `setup` show a summary (permissions, data, risks) and require typing **yes** once per terms version. The answer is stored with a timestamp. Declining changes nothing. Non-interactive use needs an explicit `--accept-terms`, so `--yes` alone refuses. `ForeverChronicaller-Installer privacy` shows the summary any time.
- In game: `/chron privacy`, plus a one-time note on first login that the chronicle stays on your computer.
- The release smoke test checks the consent flow: refuses without agreement, then installs normally and in double-click mode after "yes".

### Added
- `Topology.md`: a high-level map of the whole system. It has 11 Mermaid diagrams covering the system context, addon layers, the event and message hubs, a level-up walkthrough, the data model, the goal lifecycle, location goals, the messaging transport, together-goal sync, the companion app and the release pipeline. It also has tables mapping WoW events, internal messages, comm message types, files (component → functions → events in/out) and slash commands, plus the design constraints behind them and a suggested reading order. Linked from README and CLAUDE.md.

## [0.3.1] - 2026-11-03

First release published automatically, with **standalone installers for Windows and Linux** (no Python needed).

### Added
- The companion can be built as a standalone program (no Python needed):
  - It finds the addon zip embedded inside itself.
  - Run with no arguments (double-clicked), it starts the installer, shows any error instead of just closing, and waits for Enter at the end.
  - Messages show the program's real name instead of `python fcompanion.py`.
- The companion updates from `SaffronG/ForeverChronicaller` by default.
- Tests for standalone mode, plus a check that the companion's `VERSION` matches the `.toc` version.
- **Automatic releases** (`.github/workflows/release.yml`): pushing a new `.toc` version to `main` runs all checks, then builds standalone installers on real Windows and Linux machines with PyInstaller (Python bundled in, so players don't need it). Each one is smoke-tested by installing into a fake WoW folder, both normally and in double-click mode. Then GitHub release `v<version>` is published with the Windows `.exe`, the Linux `.tar.gz`, the addon zip, the Python installer bundle, and download instructions plus the changelog as notes. The Linux binary is built on Ubuntu 24.04 so it also runs on older distros.

### Changed
- CI (`.github/workflows/ci.yml`) runs on pushes to `main` and on pull requests, and the release workflow can reuse it. Companion tests now run on **Linux and Windows** with the current Python 3. The old 3.8 setting failed because `ubuntu-latest` (Ubuntu 26.04) no longer has Python 3.8.
- Releases no longer need a hand-pushed tag. The release workflow creates the tag.
## [0.3.0] - 2026-11-03

Adds the companion app: installer, Discord/phone notifications and auto-update. Give friends the **Installer** zip.

### Added
- Companion app (new `companion/fcompanion.py`, Python 3.8+, standard library only) for things addons can't do:
  - `watch` posts new chronicle entries to a **Discord webhook** and/or **ntfy** (phone push notifications). It reads the addon's SavedVariables files with a Lua-table parser that never executes anything, and remembers what it already posted, so it doesn't repeat and doesn't flood the channel with old history on first run.
  - Removes WoW colour codes and links, splits long messages under Discord's limit, blocks @mentions, and retries on rate limits. Errors never print the webhook URL.
  - `setup` (guided configuration, stored with private file permissions on Linux and macOS) and `test`.
  - Which entry types are posted can be configured (quests are off by default), as can which characters.
- Companion auto-update: `python fcompanion.py update` installs the newest GitHub release if it's newer than the installed addon (`--check` only reports, and `watch` checks at start). `update --zip <file>` installs a zip you already have.
  - Zips are validated before anything is touched: only `ForeverChronicaller/` paths, no `..` or absolute paths, a size limit, and the `.toc` must be present. Downloads must come from github.com.
  - The previous version is moved to a backups folder, and put back automatically if installing fails.
  - Refuses while WoW is running (`--force` overrides). Only process names are checked, so an open folder or editor showing `Wow.exe` doesn't count. After an update, restart the game; `/reload` isn't enough when new files were added.
- Installer: `python fcompanion.py install` finds WoW: Forever (common install folders, including `_retail_`-style subfolders, Wine and Lutris on Linux) or asks for the folder, then installs the addon. It uses a zip shipped next to it, `--zip`, or the latest GitHub release, and remembers the folder for `update` and `watch`.
  - `companion/Install.bat` (double-click on Windows; it checks for Python and explains how to get it) and `companion/install.sh`.
  - `scripts/package.sh` now also builds `dist/ForeverChronicaller-Installer-<version>.zip` (companion, launchers, README and the addon zip), and CI attaches it to releases.
- `/chron sync` in game: asks, then reloads the UI so the saved data is written and the companion posts straight away.
- CI runs the companion's tests on Python 3.8, including a check that the real addon zip passes the installer's validation.
## [0.2.0] - 2026-11-03

First version meant for playing. Everything below is tested against a fake game API (56 tests on Lua 5.1 and 5.4) but **not yet in the real game**. If something misbehaves, `/chron errors` lists what went wrong, and the rest of the addon keeps working.

### Added
- Location goals (new `MapGoals.lua`):
  - **Ctrl + right-click** on a zone in the world map opens a menu with "Set as goal: travel here". The map's normal zoom-out from right-clicking is undone so you stay on the map you clicked.
  - `/chron goal here` sets a goal at your current position. `/chron goal 45.2 63.1` sets one at those coordinates in your current zone.
  - New location goals place the game's own waypoint and guide arrow (user waypoint + super-tracking). `/chron way <n>` points the arrow back at goal n.
  - A goal completes automatically when you get within the arrival distance (default 20 yards, adjustable in options). Checked once per second, only while open location goals exist.
  - A goal only becomes completable after you've been more than twice the arrival distance away, so `/chron goal here` doesn't complete straight away.
  - The waypoint is cleared when its goal is completed (automatically or by hand) or deleted. It's only cleared if it's still the one this addon placed.
  - Open world only: the game doesn't report your position inside instances. If reading position ever errors (for example because of Midnight-style restrictions), polling stops with a single message and goals can still be ticked off by hand.
  - Not yet tested in game.
- World map pins for every open location goal (new `MapPins.lua` + `MapPins.xml`):
  - A gold star marks each open location goal on the map you're viewing, including parent maps such as the continent view. Goals outside the viewed map are hidden.
  - Hovering shows the goal text. Left-clicking points the waypoint arrow at that goal.
  - Pins update straight away when goals are added, completed or deleted while the map is open.
  - Built as a world map data provider with an XML pin template. Not yet tested in game; the pin template is the part most likely to need adjusting.
- "Location goal arrival distance" slider (5–100 yards) on the options page.
- On-screen goal tracker (new `Tracker.lua`), like the quest objective tracker:
  - Lists open goals (up to 8, then "+N more"). Level goals show progress, for example `(24/30)`, and location goals show live distance, for example `- 230 yd`.
  - Click a location goal to point the arrow at it. Click any other goal to open the Goals tab.
  - Drag the title to move it (position is saved). Click the title to collapse it.
  - Hidden automatically when there are no open goals. "Show goal tracker" option and `/chron tracker` toggle it.
  - Not yet tested in game.
- Quest-log-style Goals tab: the main window is wider (640 px), with the goal list on the left and a details panel on the right showing:
  - the goal's title and type, for example "Level goal - reach level 30" or "Location goal - arrive within 20 yd"
  - status: open with created date and age, or completed with date and how long it took
  - live progress (level, distance)
  - an editable **Notes** box (up to 500 characters), also shown in the tracker tooltip
  - Arrow / Done (Reopen) / Delete buttons
  - New goals are selected automatically. Clicking a row selects it.
- Goal sharing (new `Sharing.lua`): a **Share** button in the goal log, or `/chron share <n>`, sends a goal to your party, raid or instance group. `/chron share <n> <name>` whispers it to a friend instead.
  - Receivers get an Accept/Decline popup. Accepting adds a copy ("Shared by …" in the goal log) and tells the sender.
  - Level, zone, quest, location and free goals can be shared, including notes.
  - Incoming goals are validated (types, lengths, number ranges). Duplicates of goals you already have open are ignored, and at most 5 offers wait at once.
  - "Allow shared goals" option to ignore all offers.
- Together goals (new `SharedGoals.lua`): goals you complete with friends.
  - `/chron together <name> <goal>` (for example `/chron together Buddy level 30`) creates the goal and invites your friend, who gets a Join popup. `/chron invite <n> <name>` adds more friends (up to 10 members).
  - Each player's addon checks its own part (level, zone or quest, or "Done" for personal goals) and tells the others. The goal completes for everyone once every member who joined has done their part. The tracker and goal log show progress, for example `(1/2: Buddy ..., Chase done)`.
  - **Offline friends:** progress is only sent to members who are online (in your group, online on your friend list, or seen in the last 5 minutes). Anything else is remembered (saved) and sent when they come online, join your group, or every minute. Updates can arrive in any order, because state only moves forward.
  - Safety: only members can update a goal, nobody can mark *your* part done for you, the number of members is capped, and every message is validated. A sync can't loop forever. Progress is still trust-based: each client reports its own part.
  - Deleting a together goal tells the others you left.
  - Not yet tested in game. **Add each other as friends** so syncing works automatically.
- Together goals can be locations ("meet me here"): `/chron together Buddy here` or `/chron together Buddy 45.2 63.1`. Each member gets the waypoint arrow and a map pin, and their part is done on arrival (their arrow clears then). The tracker shows both distance and member progress. New `FC:GoalLocation(g, active)` gives the position for plain and together location goals.
- Export and import (new `Export.lua`) for backups or moving to another computer:
  - `/chron export` opens a window with your chronicle, goals, visited zones and stats as one text string, already highlighted for Ctrl+C.
  - `/chron import`: paste the string, then **Merge** (adds only missing entries and goals, so importing twice is safe) or **Replace** (asks first). `/chron import undo` reverts the last import until you log out.
  - Uses the game's built-in serialize, compress and Base64 tools when the client has them (`FC1C:` strings). Otherwise it uses a built-in text format (`FC1T:`).
  - The importer never runs code from the string. It parses and validates every record (types, lengths, ranges, nesting depth) and skips anything malformed. Truncated or damaged strings are rejected with a message.
  - Not yet tested in game, including the real `C_EncodingUtil` format.
- Journey tab with graphs and statistics (new `Journey.lua`, also `/chron journey`):
  - Line charts over time for **Level** (including XP progress, for example 12.4), **Gold**, **Quests**, **Zones** and **Deaths**, drawn with the client's line API, with min/max and date labels.
  - Summary: time adventuring, totals, average/fastest/slowest time per level, and **your path**: zones in the order you discovered them.
  - Progress snapshots are stored in `samples`: at login, level up, quest turn-in, new zone, death, and every 10 minutes, but only when something changed. They're capped at 2000 by thinning the oldest half, so the whole history stays. Samples are included in exports.
  - The chart needs at least a minute of history and fills in as you play. Not yet tested in game.
- Options page (Options → AddOns → Forever Chronicaller, or `/chron config`) built with the retail Settings API (new `Settings.lua`):
  - On/off switch for each automatic entry type: level ups, new zones, quest turn-ins, deaths, achievements, goals achieved. Counters (deaths, quests, visited zones) are still tracked when an entry type is off.
  - Chronicle size limit slider (0 = unlimited, up to 5000). The limit is applied only when a new entry is added, so moving the slider never deletes anything by itself.
  - Settings are saved for each character in `ForeverChronicallerDB.settings`. Older saves get the defaults automatically.
  - Not yet tested in game; the Settings API calls are based on retail 11.x/12.x.
- Quest goals can target a quest ID (`/chron goal quest 12345`) for exact matching. Matching by name still works.
- Error isolation: every event handler, internal listener and slash command now runs through `FC:SafeCall`. An error in one feature is logged and the user is told once, but the chronicle and everything else keep working.
  - `/chron errors` lists logged errors, and `/chron errors clear` clears them. Repeated identical errors are merged with a count. Up to 30 are kept, with short stack traces, in the saved data for bug reports.
  - Errors are also passed to the game's error handler, so BugSack and the Lua error window still see them.
- Slash command registry `FC:Command(names, usage, fn, order)`. Each module registers its own commands. `/chron help` (or an unknown command) lists them, and a command used without its required text prints its usage.
- In-game version check (new `VersionCheck.lua`): your version is announced to your group, and anyone running an older one is told once per session that a newer version exists (players with the newer version answer older announcements). `/chron version` shows yours.

### Changed
- `.toc` Interface number set to `120105` for the WoW: Forever client (12.1.5-style API). **Not yet confirmed in game.** Check with `/run print((select(4, GetBuildInfo())))`.
- Quest tracking now uses the `QUEST_TURNED_IN` event instead of hooking `GetQuestReward`. The title comes from `C_QuestLog.GetTitleForQuestID`, falling back to the open quest frame, then `Quest #<id>`.
- `Goals.lua`: new `FC:CreateGoal(kind, target, text)` used by both `/chron goal` and the map menu. Goals now fire `GOAL_ADDED`, `GOAL_COMPLETED` and `GOAL_REMOVED` internal messages.

### Fixed
- The `.toc` had no newline after its last line. The game doesn't mind, but some tools skipped `Journey.lua` because of it.

### Developer
- Addon messaging layer (new `Comms.lua`): `FC:SendComm` and `FC:OnComm`. It splits messages into chunks under the 255-byte limit and reassembles them, escapes every special and non-ASCII byte, and keeps an outgoing queue that waits while addon messages are restricted (instances during encounters, M+ or PvP) and sends at most 4 messages per second. Your own and malformed messages are ignored.
- `FC:SetGoalDescription`, `FC:DescribeGoalType`, and `FC:AddWindowTab(name, label, view)` so other modules can add their own tabs to the main window.
- `FC:WhenWorldMap(fn)` helper in `MapGoals.lua` to run code once the world map has loaded.
- Settings can now notify the addon when they change (`SETTINGS_CHANGED`), so changes apply straight away.
- Test suite in `tests/` (`lua tests/run.lua .`): a fake WoW API plus 18 tests covering the chronicle, goals, settings, location goals, map pins, error isolation and commands.
- Tests can now run two fake players talking to each other (`transfer(a, b)`).
- `scripts/package.sh` builds `dist/ForeverChronicaller-<version>.zip` containing only the files the game needs (the `.toc` and everything it lists, plus README and Changelog) in a `ForeverChronicaller/` folder. It fails if a listed file is missing.
- `scripts/release_notes.sh [version]` prints that version's Changelog section.
- GitHub Actions CI (`.github/workflows/ci.yml`):
  - Every push and pull request runs syntax checks, XML checks and all tests on Lua **5.1** (the game's version) and 5.4, and checks that the package builds.
  - Pushing a tag `vX.Y.Z` checks it matches the `.toc` version, then publishes a GitHub Release with the zip and the changelog section as notes.
- `.gitignore` for `dist/`.
- `TODO.md` with the planned feature roadmap.
- `CLAUDE.md` with working rules for future contributors (human or AI).
- Git repository and this changelog.

### Known issues
- The `.toc` Interface number `120105` is a best guess for the WoW: Forever client. If the addon shows as out of date, tick "Load out of date AddOns" or set the number from `/run print((select(4, GetBuildInfo())))`.
- Goal sharing, together goals and the version check need both players to have the addon. Together goals sync automatically only between friends (friend list), group members, or players who recently messaged you.
- Not yet tested in game: the options page, world map menu and pins, the tracker and window layout, export strings in the compressed format, and the line charts.

## [0.1.0] - 2026-11-03

### Added
- `ForeverChronicaller.toc` that saves data for each character (`ForeverChronicallerDB`).
- `Core.lua`: setup for saved data (replaces the file-based `persistance.lua` idea, since WoW addons can't access files), merging of new defaults into older saves, game-event dispatch, and an internal message system between modules.
- `Chronicle.lua`: automatic chronicle entries for the chronicle's start, level ups, first visit to each zone, deaths (with a counter), achievements and quest turn-ins (with a counter).
- `Goals.lua`: goals with automatic completion for `level <n>`, `zone <name>` and `quest <name>`, plus free-form goals. Completing a goal writes a chronicle entry that includes how long it took.
- `UI.lua`: a movable window with Chronicle and Goals tabs, goal checkboxes and delete buttons, an input box for notes and goals, and a stats line.
- Slash commands `/chron` and `/fc`: `note`, `goal`, `goals`, `done <n>`, `del <n>`, `recent [n]`.
- `README.md` with install steps, commands and the proposed features list.

### Known issues
- The `.toc` Interface number was `30300` (3.3.5) and quest tracking hooked `GetQuestReward`. Both fixed in Unreleased.
- `main.lua` and `persistance.lua` are the original prototype files. They aren't loaded by the `.toc` and can be deleted.
