# Forever Chronicaller

Automatically chronicles your adventure and tracks personal goals.

How it all fits together (diagrams, data flow, component map): [Topology.md](Topology.md).

## Install
**Easiest:** from the [latest release](https://github.com/SaffronG/ForeverChronicaller/releases/latest), close WoW and then:
- **Windows:** download `ForeverChronicaller-Installer-<version>-windows.exe` and double-click it. If SmartScreen warns about an unknown publisher, click *More info* → *Run anyway*.
- **Linux:** download `ForeverChronicaller-Installer-<version>-linux.tar.gz`, then `tar xzf` it and run `./ForeverChronicaller-Installer`.

No Python needed. It finds your WoW: Forever folder (or asks you for it) and installs the addon.

(The `ForeverChronicaller-Installer-<version>.zip` bundle does the same with your own Python: `Install.bat` / `install.sh`.)

**Manually:**
1. Unzip `ForeverChronicaller-<version>.zip` (from `scripts/package.sh` or a GitHub release) into your WoW: Forever folder's `Interface/AddOns/`, so you end up with `Interface/AddOns/ForeverChronicaller/ForeverChronicaller.toc`.
2. Start the game, check that **Forever Chronicaller** is enabled in the AddOns list on the character screen, and log in.
3. Type `/chron` to open it, or `/chron help` for all commands.

(Developers: you can also copy or symlink this repo folder into `Interface/AddOns/ForeverChronicaller/`.)

If the addon shows as "out of date", either tick "Load out of date AddOns" on the
character select AddOns screen or change `## Interface:` in the .toc to your client's
number (in game: `/run print((select(4, GetBuildInfo())))`).

## What gets chronicled automatically
- Level ups, first visit to each zone, quest turn-ins, deaths, achievements, goals achieved
- Each type can be switched off, and the chronicle size can be limited, in Options → AddOns → Forever Chronicaller (`/chron config`)

## Commands (`/chron` or `/fc`)
| Command | Effect |
|---|---|
| `/chron` | open/close the window |
| `/chron note <text>` | write a note in your chronicle |
| `/chron goal <text>` | add a goal |
| `/chron goals` | list goals |
| `/chron done <n>` / `/chron del <n>` | complete / delete goal n |
| `/chron recent [n]` | print last n entries to chat |
| `/chron way <n>` | point the waypoint arrow at location goal n |
| `/chron tracker` | show/hide the on-screen goal tracker |
| `/chron share <n> [name]` | share goal n with your group, or whisper it to a friend (they need the addon) |
| `/chron export` / `/chron import [undo]` | back up / restore your chronicle as a text string |
| `/chron journey` | open the Journey graphs and statistics |
| `/chron together <name> <goal>` | a goal you complete together with a friend |
| `/chron invite <n> <name>` | invite another friend to together goal n |
| `/chron sync` | save now (reloads the UI) so the companion app posts your latest entries |
| `/chron config` | open the options page |
| `/chron version` | show your version (you're told automatically if a group member has a newer one) |
| `/chron errors [clear]` | show (or clear) errors the addon caught; include these in bug reports |
| `/chron help` | list all commands |

Goals that complete automatically:
`level 30`, `zone Stranglethorn Vale`, `quest The Defias Brotherhood` (or `quest <questID>` for an exact match).
Anything else is a free-form goal you tick off yourself.

Location goals: **Ctrl + right-click** a spot on a zone map, or use `/chron goal here` or `/chron goal 45.2 63.1`.
The game's waypoint arrow guides you there, and the goal completes when you arrive (open world only).
The **Goals** tab works like the quest log: pick a goal on the left to see its details and progress, write notes for it, or point the arrow, complete or delete it.
The **Journey** tab (`/chron journey`) graphs your level, gold, quests, zones and deaths over time, and sums up your path through the world and how long each level took.
**Together goals:** `/chron together Buddy level 30` (or `/chron together Buddy here` to meet up) creates a goal you and a friend complete together. Each of you does your part, and it's achieved when everyone has. Add each other as friends so progress syncs automatically, even if one of you was offline.
Open goals are listed in a small on-screen tracker (drag the title to move it, click to collapse, `/chron tracker` to hide it).
Every open location goal appears as a gold star on the world map. Click a star to point the arrow at it.

## Files
- `Core.lua` – SavedVariables (persistence), event dispatch
- `Chronicle.lua` – automatic event logging
- `Goals.lua` – goal parsing / auto-completion
- `MapGoals.lua` – location goals, world map menu, waypoint arrow
- `MapPins.lua` / `MapPins.xml` – world map pins for open location goals
- `Tracker.lua` – on-screen goal tracker
- `Comms.lua` – addon-to-addon messaging (chunking, queue, restrictions)
- `Sharing.lua` – share goals with your group / friends
- `SharedGoals.lua` – together goals: invites, per-member progress, offline-safe syncing
- `Export.lua` – export/import strings and their window
- `Settings.lua` – options page (Settings API)
- `Journey.lua` – progress snapshots, graphs and journey statistics (Journey tab)
- `UI.lua` – window and slash commands

## Backup / moving to another computer
- **In game:** `/chron export` and copy the text (Ctrl+C). On the other computer, `/chron import`, paste (Ctrl+V), then **Merge** or **Replace**. `/chron import undo` reverts the last import until you log out.
- **By file:** your data lives in `WTF/Account/<account>/<realm>/<character>/SavedVariables/ForeverChronicaller.lua`. Copy that file (with the game closed) to the same place on the other computer.

## Companion app (optional)
`companion/fcompanion.py` posts your new chronicle entries to **Discord** or your **phone** (ntfy), and can install addon updates from GitHub releases. It runs outside the game and only reads the addon's saved files. See [companion/README.md](companion/README.md).

## Development / releasing
- Build an installable zip: `scripts/package.sh` → `dist/ForeverChronicaller-<version>.zip`. Unzip it into `Interface/AddOns/`.
- Every push to `main` runs the tests (Lua 5.1 and 5.4, plus the companion on Linux and Windows).
- **Release (automatic):**
  1. Bump `## Version:` in the `.toc` and `VERSION` in `companion/fcompanion.py`.
  2. Rename `## [Unreleased]` in `Changelog.md` to `## [x.y.z] - date`, and add a fresh `## [Unreleased]` above it.
  3. Commit and push to `main`.
  4. The **Release** workflow notices the new version, runs all checks, and builds standalone installers on real Windows and Linux machines (Python bundled in, no install needed). It test-installs each one into a fake WoW folder, then publishes release `vx.y.z` with:
     - `ForeverChronicaller-Installer-x.y.z-windows.exe`
     - `ForeverChronicaller-Installer-x.y.z-linux.tar.gz`
     - `ForeverChronicaller-x.y.z.zip` (manual install)
     - `ForeverChronicaller-Installer-x.y.z.zip` (the Python version, for macOS or anyone else)
- Pushes that don't change the version publish nothing. You can also start the Release workflow by hand from the Actions tab.

Run the tests with `lua tests/run.lua .` from the repo root (Lua 5.1+). They use a fake WoW API, so in-game testing is still needed for frames, the options page and the world map.

Data is saved per character in `WTF/Account/<acct>/<realm>/<char>/SavedVariables/ForeverChronicaller.lua`.

## Proposed Features
- Create shared goals that require you and a friend to do something
- Share goals with party members
- Add goal-create context menu when you right-click a location on the map and allow you to add a goal to go there and have an arrow pointing you to your goal
- Add a seperate quest-style menu for your goals
- Backup chronicles and load from another computer
- Add graphs/visualizers for your progress and journey
- Configure auto-chronicaller
- Discord webhhooks and a push-notif config
- Create a simple installer
- Add CI/CD pipeline for auto-deploy
- Create an auto-update and auto-reload feature