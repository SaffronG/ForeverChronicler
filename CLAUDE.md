# Forever Chronicaller: rules for contributors (Claude and humans)

A World of Warcraft addon that chronicles adventures and tracks goals. Read `README.md` for features, `TODO.md` for what's next and `Changelog.md` for history.

## Target client
- **WoW: Forever 1.60.1**: interface and APIs match **retail 12.1.5**. Addon restrictions are similar to **Midnight**.
- Use modern retail APIs, such as `C_Map`, `C_SuperTrack`, `C_QuestLog`, `C_ChatInfo`, the Settings API, the Menu API, `CreateLine` and `BackdropTemplate`. Don't write code for 3.3.5 or vanilla.
- Midnight restrictions: don't build features on the combat log or on combat data (health, auras, cooldowns), which are secret or unavailable. Addon messages are blocked in instances during encounters, M+ and PvP, so queue them.
- Addons have **no network or file access**. Saved data reaches disk only on logout or `/reload`. Anything external (Discord, auto-update, installer) belongs in a separate companion app.

## Workflow rules
0. **Ask before each step.** Before starting each `TODO.md` item or pipeline step, tell the user what the next step is and ask whether to continue. After committing a step, stop, report what changed and ask again. Never chain several steps without approval.
   - **Exception:** the user can waive this for a session ("go through all the steps"). Then keep working through `TODO.md` without stopping, still one commit per step, and give a short overview after each step. The waiver lasts only for that session.
1. **Follow `TODO.md`.** Work items top to bottom unless the user says otherwise. Tick items off (`[x]`) when finished. Add new tasks that come up to the right section.
2. **One change = one commit.** Each finished, self-contained change (one TODO item or one fix) gets its own commit. Don't bundle unrelated changes.
3. **Every commit updates `Changelog.md`.** Add an entry under `## [Unreleased]` (Added / Changed / Fixed / Removed) in the same commit as the change. When a version is released, move Unreleased under a version heading with the date.
4. **Update `TODO.md` in the same commit** as the change it relates to.
5. **Keep `README.md` current** when commands, features or install steps change.
6. **Verify before committing.** Run `lua tests/run.lua .` (all tests must pass), `luac -p` on every changed `.lua` file, and check that `.xml` files are well-formed. Add tests in `tests/test_*.lua` for new logic, and extend the fake API in `tests/wow_stub.lua` as needed. Note in the changelog anything that still needs testing in game.
6a. **Robustness:** run new event handlers, listeners and commands through the framework (`FC:RegisterEvent`, `FC:On`, `FC:Command`) so errors are isolated by `FC:SafeCall`. Wrap any other entry point (hooks, timers, frame scripts that do real work) with `FC:SafeCall` too. Never let a new feature be able to break the chronicle.
7. **Commit messages:** a short imperative summary line, then a blank line and details if needed.
8. **Don't** delete user files, rewrite history or push to a remote unless the user asks.

## Layout
- `ForeverChronicaller.toc`: manifest. Load order: Core → Chronicle → Goals → MapGoals → MapPins (.lua then .xml) → Tracker → Comms → Sharing → SharedGoals → Export → Settings → UI → Journey.
- `Core.lua`: saved data (`ForeverChronicallerDB`), error isolation (`FC:SafeCall`, `/chron errors`), event dispatch, internal message system (`FC:On` / `FC:Fire`), slash command registry (`FC:Command(names, usage, fn, order)`).
- `Chronicle.lua`: automatic logging (`FC:AddEntry`).
- `Goals.lua`: goal parsing and auto-completion (`FC:CreateGoal`, `FC:AddGoal`). Fires `GOAL_ADDED`, `GOAL_COMPLETED`, `GOAL_REMOVED` and `GOALS_CHANGED`.
- `MapGoals.lua`: location goals (`kind = "location"`), world map Ctrl + right-click menu, waypoint/super-track, arrival polling.
- `MapPins.lua` / `MapPins.xml`: world map data provider and pin template. The pin mixin global (`ForeverChronicallerGoalPinMixin`) must be defined in the `.lua`, which loads before the `.xml`.
- `Tracker.lua`: on-screen goal tracker (`FC:GoalProgressText`, `FC.RefreshTracker`). Distances come from `FC.goalDistance` (set by `MapGoals.lua`, which fires `LOCATIONS_UPDATED`).
- `Comms.lua`: addon messages (`FC:SendComm(type, fields, channel, target)`, `FC:OnComm(type, fn)`), prefix `FChron`. Incoming data is untrusted, so always validate it.
- `Sharing.lua`: goal sharing (`FC.GoalToFields` / `FC.FieldsToGoal` validate and convert goals for messages).
- `SharedGoals.lua`: together goals (`kind = "shared"`, members keyed by short name). Sync messages SGINV/SGJOIN/SGSYNC/SGLEAVE. Merges must only move state forward, and a reply is only sent if we know more (`knowsMore`), which keeps the sync from looping.
- `Export.lua`: export/import (`FC:ExportString`, `FC:ImportString(str, "merge"|"replace")`, `FC:UndoImport`). When adding new saved data, include it in the export and validate it in the importer.
- `Settings.lua`: options page (`FC.db.settings`, `FC:OpenSettings`).
- `Journey.lua`: progress samples (`FC.db.samples`, `FC:TakeSample`), stats (`FC:JourneyStats`) and the Journey tab charts. Loads after UI.lua and adds its tab on READY.
- `UI.lua`: main window (Chronicle tab, quest-log-style Goals tab, `FC:AddWindowTab` for extra tabs) and basic slash commands.
- `scripts/package.sh` (release zip from the `.toc` file list), `scripts/release_notes.sh`, `.github/workflows/ci.yml` (tests on Lua 5.1 + 5.4, releases on `v*` tags). **Every new addon file must be listed in the `.toc`**, otherwise it won't load or be packaged.
- `tests/`: `run.lua` (runner), `wow_stub.lua` (fake WoW API), `test_*.lua` (tests). Not loaded by the game. Several fake players can exist at once: `setup({ name = "Buddy" })`, then `transfer(a, b)` delivers a's addon messages to b.
- `main.lua`, `persistance.lua`: original prototype. Not loaded, can be deleted.
