# Forever Chronicler

Automatically chronicles your adventure and tracks personal goals.

**Privacy, permissions and risks:** [PRIVACY.md](PRIVACY.md). In short, everything stays on your computer unless you turn on sharing or Discord/phone posting. No telemetry is collected.

How it all fits together (diagrams, data flow, component map): [docs/Topology.md](docs/Topology.md).

## Install
**Easiest:** from the [latest release](https://github.com/SaffronG/ForeverChronicler/releases/latest), close WoW and then:
- **Windows:** download `ForeverChronicler-Installer-<version>-windows.exe` and double-click it. If SmartScreen warns about an unknown publisher, click *More info* → *Run anyway*.
- **Linux:** download `ForeverChronicler-Installer-<version>-linux.tar.gz`, then `tar xzf` it and run `./ForeverChronicler-Installer`.

No Python needed. It finds your WoW: Forever folder (or asks you for it) and installs the addon.

(The `ForeverChronicler-Installer-<version>.zip` bundle does the same with your own Python: `Install.bat` / `install.sh`.)

**Manually:**
1. Unzip `ForeverChronicler-<version>.zip` (from `scripts/package.sh` or a GitHub release) into your WoW: Forever folder's `Interface/AddOns/`, so you end up with `Interface/AddOns/ForeverChronicler/ForeverChronicler.toc`.
2. Start the game, check that **Forever Chronicler** is enabled in the AddOns list on the character screen, and log in.
3. Type `/chron` to open it, or `/chron help` for all commands.

(Developers: you can also copy or symlink this repo folder into `Interface/AddOns/ForeverChronicler/`.)

**Upgrading from 0.5.0 or older (spelled "Forever Chronicaller"):** the addon was renamed in 0.6.0, and WoW keeps saved data under the addon's folder name.
- **With the installer (recommended):** download the 0.6.0 installer once and run it. The updater built into 0.5.0 and older looks for the old name and can't find 0.6.0. The installer moves the old `ForeverChronicaller` folder to its backups, so the two don't load side by side, and copies each character's saved chronicle to the new name. The originals are kept. On your next login the addon says "Your chronicle from the old "Forever Chronicaller" was carried over."
- **Manually:** with WoW closed, delete `Interface/AddOns/ForeverChronicaller/`. Then, in each character's `WTF/Account/<account>/<realm>/<character>/SavedVariables/` folder, copy `ForeverChronicaller.lua` to `ForeverChronicler.lua` and keep the original. Do this before logging in with 0.6.0.

If the addon shows as "out of date", either tick "Load out of date AddOns" on the
character select AddOns screen or change `## Interface:` in the .toc to your client's
number (in game: `/run print((select(4, GetBuildInfo())))`).

## What gets chronicled automatically
- Level ups, first visit to each zone, quest turn-ins, deaths, achievements, goals achieved
- Professions: learning a profession, every 25 skill points, max skill. Recipes you learn (a trainer visit is summed up in one line). The first time you craft each item, and crafting milestones (10, 50, 100, 250, 500, then every 1000 items)
- Trophies: the first time you loot each notable item (Rare or better by default, adjustable in the options), with the boss it dropped from. The first time you defeat each dungeon or raid boss (per difficulty) and each rare monster or world boss in the open world. Repeat kills and loot are counted
- Companions, "the friends you made along the way": when a party or raid ends, who you were with, for how long and where ("Adventured with Buddy and Pal for 1 h 5 min in Westfall. First time with Pal."). Raids are summed up in one line, with the bosses you defeated together. Milestones for time together (1, 5, 10, 24, 100 hours), and an entry when you add someone to your friend list, with your shared history
- Each type can be switched off, and the chronicle size can be limited, in Options → AddOns → Forever Chronicler (`/chron config`)

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
| `/chron professions [list]` | open the Professions tab (or print it to chat with `list`) |
| `/chron letters` | read your daily letters and each day's stats |
| `/chron letter [YYYY-MM-DD]` | print a day's letter to chat (today if no date) |
| `/chron trophies` | bosses and rare foes you've slain, and how much notable loot you've found |
| `/chron companions [name]` | who you've adventured with, for how long, and which of them became friends (details for one companion with a name) |
| `/chron together <name> <goal>` | a goal you complete together with a friend |
| `/chron invite <n> <name>` | invite another friend to together goal n |
| `/chron sync` | save now (reloads the UI) so the companion app posts your latest entries |
| `/chron config` | open the options page |
| `/chron version` | show your version (you're told automatically if a group member has a newer one) |
| `/chron privacy` | what the addon stores and shares |
| `/chron errors [clear]` | show (or clear) errors the addon caught; include these in bug reports |
| `/chron help` | list all commands |

Goals that complete automatically:
`level 30`, `zone Stranglethorn Vale`, `quest The Defias Brotherhood` (or `quest <questID>` for an exact match).
Anything else is a free-form goal you tick off yourself.

Location goals: **Ctrl + right-click** a spot on a zone map, or use `/chron goal here` or `/chron goal 45.2 63.1`.
The game's waypoint arrow guides you there, and the goal completes when you arrive (open world only).
The window has a night elf look (moonlit sky, stars and silver borders), and the **Chronicle** tab is written on a parchment scroll. Every event keeps its own colour, shown as a darker ink so it reads well on the paper.
The **Goals** tab works like the quest log: pick a goal on the left to see its details and progress, write notes for it, or point the arrow, complete or delete it.
The **Journey** tab (`/chron journey`) graphs your level, gold, quests, zones, deaths, known recipes and crafts over time, and sums up your path through the world and how long each level took.
The **Letters** tab (`/chron letters`) turns each day of play into a letter home, written in a voice that fits your race (who you write to and how you sign off) and class (how you tell it). For example, a night elf druid writes "Beloved sister in Darnassus, … Under Elune's light, ever yours". Pick any day on the left to read its letter and that day's stats: time played, levels, gold, zones, quests, deaths and more. A day runs from 04:00 to 04:00, so a late night still counts as the day it started. Days from before this feature get letters too, built from the chronicle.
The **Professions** tab (`/chron professions`) shows a bar per profession for skill and **recipe completion in %**, plus how many items you crafted. Recipes are counted when you open that profession's window, so open each one once to fill in its percentage.
**Together goals:** `/chron together Buddy level 30` (or `/chron together Buddy here` to meet up) creates a goal you and a friend complete together. Each of you does your part, and it's achieved when everyone has. Add each other as friends so progress syncs automatically, even if one of you was offline.
Open goals are listed in a small on-screen tracker (drag the title to move it, click to collapse, `/chron tracker` to hide it).
Every open location goal appears as a gold star on the world map. Click a star to point the arrow at it.

## Files
Addon code is in `src/`, grouped by feature. Developer docs are in `docs/`.

- `src/core/Core.lua` – SavedVariables (persistence), event dispatch
- `src/chronicle/Chronicle.lua` – automatic event logging
- `src/goals/Goals.lua` – goal parsing / auto-completion
- `src/goals/MapGoals.lua` – location goals, world map menu, waypoint arrow
- `src/goals/MapPins.lua` / `MapPins.xml` – world map pins for open location goals
- `src/goals/Tracker.lua` – on-screen goal tracker
- `src/core/Comms.lua` – addon-to-addon messaging (chunking, queue, restrictions)
- `src/sharing/Sharing.lua` – share goals with your group / friends
- `src/sharing/SharedGoals.lua` – together goals: invites, per-member progress, offline-safe syncing
- `src/sharing/Export.lua` – export/import strings and their window
- `src/ui/Settings.lua` – options page (Settings API)
- `src/ui/Theme.lua` – night elf window style, parchment scroll and ink colours
- `src/chronicle/Journey.lua` – progress snapshots, graphs and journey statistics (Journey tab)
- `src/chronicle/Letters.lua` – daily ledger, letters in your race/class voice, Letters tab
- `src/chronicle/Professions.lua` – profession, recipe and crafting entries, recipe completion (Professions tab)
- `src/chronicle/Trophies.lua` – notable loot, bosses and rare monsters slain (`/chron trophies`)
- `src/chronicle/Companions.lua` – who you grouped with, for how long, group history, friends made (`/chron companions`)
- `src/ui/UI.lua` – window and slash commands

## Backup / moving to another computer
- **In game:** `/chron export` and copy the text (Ctrl+C). On the other computer, `/chron import`, paste (Ctrl+V), then **Merge** or **Replace**. `/chron import undo` reverts the last import until you log out.
- **By file:** your data lives in `WTF/Account/<account>/<realm>/<character>/SavedVariables/ForeverChronicler.lua`. Copy that file (with the game closed) to the same place on the other computer.

## Companion app (optional)
`companion/fcompanion.py` posts your new chronicle entries to **Discord** or your **phone** (ntfy), and can install addon updates from GitHub releases. It runs outside the game and only reads the addon's saved files. See [companion/README.md](companion/README.md).

## Development / releasing
- Build an installable zip: `scripts/package.sh` → `dist/ForeverChronicler-<version>.zip`. Unzip it into `Interface/AddOns/`.
- Every push to `main` runs the tests (Lua 5.1 and 5.4, plus the companion on Linux and Windows).
- **Release (automatic):**
  1. Bump `## Version:` in the `.toc` and `VERSION` in `companion/fcompanion.py`.
  2. Rename `## [Unreleased]` in `Changelog.md` to `## [x.y.z] - date`, and add a fresh `## [Unreleased]` above it.
  3. Commit and push to `main`.
  4. The **Release** workflow notices the new version, runs all checks, and builds standalone installers on real Windows and Linux machines (Python bundled in, no install needed). It test-installs each one into a fake WoW folder, then publishes release `vx.y.z` with:
     - `ForeverChronicler-Installer-x.y.z-windows.exe`
     - `ForeverChronicler-Installer-x.y.z-linux.tar.gz`
     - `ForeverChronicler-x.y.z.zip` (manual install)
     - `ForeverChronicler-Installer-x.y.z.zip` (the Python version, for macOS or anyone else)
- Pushes that don't change the version publish nothing. You can also start the Release workflow by hand from the Actions tab.

Run the tests with `lua tests/run.lua .` from the repo root (Lua 5.1+). They use a fake WoW API, so in-game testing is still needed for frames, the options page and the world map.

Data is saved per character in `WTF/Account/<acct>/<realm>/<char>/SavedVariables/ForeverChronicler.lua`.

## Proposed Features
- Create shared goals that require you and a friend to do something
- Share goals with party members
- Add goal-create context menu when you right-click a location on the map and allow you to add a goal to go there and have an arrow pointing you to your goal
- Add a seperate quest-style menu for your goals
- Backup chronicles and load from another computer
- Add graphs/visualizers for your progress and journey
- Configure auto-chronicler
- Discord webhhooks and a push-notif config
- Create a simple installer
- Add CI/CD pipeline for auto-deploy
- Create an auto-update and auto-reload feature