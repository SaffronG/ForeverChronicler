# Changelog

Newest first. Every change gets an entry here and its own commit (see `CLAUDE.md`).

## [Unreleased]

### Added
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
- The `.toc` Interface number is `30300` (3.3.5) but the target client uses the 12.1.5-style API. Tracked in `TODO.md`.
- Quest tracking hooks `GetQuestReward` instead of the modern `QUEST_TURNED_IN` event. Tracked in `TODO.md`.
- `main.lua` and `persistance.lua` are the original prototype files. They aren't loaded by the `.toc` and can be deleted.
