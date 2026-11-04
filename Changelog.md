# Changelog

Newest first. Every change gets an entry here and its own commit (see `CLAUDE.md`).

## [Unreleased]

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
- "Location goal arrival distance" slider (5–100 yards) on the options page.

### Changed
- `Goals.lua`: new `FC:CreateGoal(kind, target, text)` used by both `/chron goal` and the map menu. Goals now fire `GOAL_ADDED`, `GOAL_COMPLETED` and `GOAL_REMOVED` internal messages.
- `.toc` Interface number set to `120105` for the WoW: Forever client (12.1.5-style API). **Not yet confirmed in game.** Check with `/run print((select(4, GetBuildInfo())))`.
- Quest tracking now uses the `QUEST_TURNED_IN` event instead of hooking `GetQuestReward`. The title comes from `C_QuestLog.GetTitleForQuestID`, falling back to the open quest frame, then `Quest #<id>`.

### Added
- Options page (Options → AddOns → Forever Chronicaller, or `/chron config`) built with the retail Settings API (new `Settings.lua`):
  - On/off switch for each automatic entry type: level ups, new zones, quest turn-ins, deaths, achievements, goals achieved. Counters (deaths, quests, visited zones) are still tracked when an entry type is off.
  - Chronicle size limit slider (0 = unlimited, up to 5000). The limit is applied only when a new entry is added, so moving the slider never deletes anything by itself.
  - Settings are saved for each character in `ForeverChronicallerDB.settings`. Older saves get the defaults automatically.
  - Not yet tested in game; the Settings API calls are based on retail 11.x/12.x.
- Quest goals can target a quest ID (`/chron goal quest 12345`) for exact matching. Matching by name still works.
- `TODO.md` with the planned feature roadmap.
- `CLAUDE.md` with working rules for future contributors (human or AI).
- Git repository and this changelog.

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
