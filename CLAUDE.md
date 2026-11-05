# Forever Chronicaller: rules for contributors (Claude and humans)

A World of Warcraft addon that chronicles adventures and tracks goals. Read `README.md` for features, `docs/Topology.md` for the architecture (diagrams, event/message flow, component map), `docs/TODO.md` for what's next and `Changelog.md` for history.

## Target client
- **WoW: Forever 1.60.1**: interface and APIs match **retail 12.1.5**. Addon restrictions are similar to **Midnight**.
- Use modern retail APIs, such as `C_Map`, `C_SuperTrack`, `C_QuestLog`, `C_ChatInfo`, the Settings API, the Menu API, `CreateLine` and `BackdropTemplate`. Don't write code for 3.3.5 or vanilla.
- Midnight restrictions: don't build features on the combat log or on combat data (health, auras, cooldowns), which are secret or unavailable. Addon messages are blocked in instances during encounters, M+ and PvP, so queue them.
- Addons have **no network or file access**. Saved data reaches disk only on logout or `/reload`. Anything external (Discord, auto-update, installer) belongs in a separate companion app.

## Workflow rules
0. **Ask before each step.** Before starting each `docs/TODO.md` item or pipeline step, tell the user what the next step is and ask whether to continue. After committing a step, stop, report what changed and ask again. Never chain several steps without approval.
   - **Exception:** the user can waive this for a session ("go through all the steps"). Then keep working through `docs/TODO.md` without stopping, still one commit per step, and give a short overview after each step. The waiver lasts only for that session.
1. **Follow `docs/TODO.md`.** Work items top to bottom unless the user says otherwise. Tick items off (`[x]`) when finished. Add new tasks that come up to the right section.
2. **One change = one commit.** Each finished, self-contained change (one TODO item or one fix) gets its own commit. Don't bundle unrelated changes.
3. **Every commit updates `Changelog.md`.** Add an entry under `## [Unreleased]` (Added / Changed / Fixed / Removed) in the same commit as the change. When a version is released, move Unreleased under a version heading with the date.
4. **Update `docs/TODO.md` in the same commit** as the change it relates to.
5. **Keep `README.md` current** when commands, features or install steps change. **Keep `docs/Topology.md` current** when files, events, internal messages, comm message types, saved data or the pipeline change. Its Mermaid diagrams must parse, because GitHub shows an error box otherwise.
5a. **Privacy:** anything that changes what is stored, sent, accessed or risked must update `PRIVACY.md` (and the in-game `/chron privacy` and companion `DISCLAIMER` summaries). Bump `TERMS_VERSION` in `companion/fcompanion.py` when users should agree again. Telemetry is opt-in and off by default, and must never include names, chronicle/goal/note text, chat, zones, coordinates, paths or secrets.
6. **Verify before committing.** Run `lua tests/run.lua .` (all tests must pass), `luac -p` on every changed `.lua` file, and check that `.xml` files are well-formed. Add tests in `tests/test_*.lua` for new logic, and extend the fake API in `tests/wow_stub.lua` as needed. Note in the changelog anything that still needs testing in game.
6a. **Robustness:** run new event handlers, listeners and commands through the framework (`FC:RegisterEvent`, `FC:On`, `FC:Command`) so errors are isolated by `FC:SafeCall`. Wrap any other entry point (hooks, timers, frame scripts that do real work) with `FC:SafeCall` too. Never let a new feature be able to break the chronicle.
7. **Commit messages:** a short imperative summary line, then a blank line and details if needed.
8. **Don't** delete user files, rewrite history or push to a remote unless the user asks.

## Layout
Addon code lives in `src/`, grouped by feature: `core/` (framework, messaging, versions), `chronicle/` (log and journey), `goals/` (goals, map, tracker), `sharing/` (sharing, together goals, export) and `ui/` (window, settings). Put a new file in the folder of the feature it belongs to, and list it in the `.toc`. Developer docs (`Topology.md`, `TODO.md`) live in `docs/`; README, Changelog, PRIVACY, SECURITY and this file stay at the root.

- `ForeverChronicaller.toc`: manifest. Load order: Core → Chronicle → Goals → MapGoals → MapPins (.lua then .xml) → Tracker → Comms → Sharing → SharedGoals → Export → VersionCheck → Settings → Theme → UI → Journey → Professions.
- `src/core/Core.lua`: saved data (`ForeverChronicallerDB`), error isolation (`FC:SafeCall`, `FC:Dispatch`, `/chron errors`), opt-in diagnostics, event dispatch, internal message system (`FC:On` / `FC:Fire`), slash command registry (`FC:Command(names, usage, fn, order)`).
- `src/chronicle/Chronicle.lua`: automatic logging (`FC:AddEntry`).
- `src/goals/Goals.lua`: goal parsing and auto-completion (`FC:CreateGoal`, `FC:AddGoal`). Fires `GOAL_ADDED`, `GOAL_COMPLETED`, `GOAL_REMOVED` and `GOALS_CHANGED`.
- `src/goals/MapGoals.lua`: location goals (`kind = "location"`), world map Ctrl + right-click menu, waypoint/super-track, arrival polling.
- `src/goals/MapPins.lua` / `MapPins.xml`: world map data provider and pin template. The pin mixin global (`ForeverChronicallerGoalPinMixin`) must be defined in the `.lua`, which loads before the `.xml`.
- `src/goals/Tracker.lua`: on-screen goal tracker (`FC:GoalProgressText`, `FC.RefreshTracker`). Distances come from `FC.goalDistance` (set by `MapGoals.lua`, which fires `LOCATIONS_UPDATED`).
- `src/core/Comms.lua`: addon messages (`FC:SendComm(type, fields, channel, target)`, `FC:OnComm(type, fn)`), prefix `FChron`. Incoming data is untrusted, so always validate it.
- `src/sharing/Sharing.lua`: goal sharing (`FC.GoalToFields` / `FC.FieldsToGoal` validate and convert goals for messages).
- `src/sharing/SharedGoals.lua`: together goals (`kind = "shared"`, members keyed by short name). Sync messages SGINV/SGJOIN/SGSYNC/SGLEAVE. Merges must only move state forward, and a reply is only sent if we know more (`knowsMore`), which keeps the sync from looping.
- `src/sharing/Export.lua`: export/import (`FC:ExportString`, `FC:ImportString(str, "merge"|"replace")`, `FC:UndoImport`). When adding new saved data, include it in the export and validate it in the importer.
- `src/core/VersionCheck.lua`: `FC.version` (from the .toc), `FC.CompareVersions`, version announcements to the group.
- **Feature flags:** `FEATURE_TELEMETRY` (companion) and `FC.FEATURES.diagnostics` (addon) are **off**. Don't switch them on without the user's go-ahead. Switching on also requires updating PRIVACY.md §3 and the DISCLAIMER, and bumping `TERMS_VERSION`. Tests for flagged code switch the flag on explicitly; keep the flag-off tests passing.
- Telemetry: the addon only records locally (`FC:Dispatch` timings when `settings.diagnostics` is on; `errorLog` entries carry `v` and `label`). `companion/fc_telemetry.py` turns those plus companion spans into OTLP. Use `TEL.span(...)` for new companion operations, and only pass fixed code names, numbers or values that went through `scrub()`. Extend the personal-data test in `companion/tests/test_telemetry.py` when adding fields.
- `src/ui/Settings.lua`: options page (`FC.db.settings`, `FC:OpenSettings`).
- `src/ui/Theme.lua`: the window's look (night elf frame, parchment, `FC:NightButton`, `FC:StylePanel`, colours in `FC.Theme`). Loads before UI.lua. New window views should use these helpers instead of Blizzard's red buttons. Chronicle text on the parchment goes through `FC.Ink`, which darkens colour codes for display only; never change the saved entry colours for it. Atlases are only used after checking `C_Texture.GetAtlasInfo`.
- `src/chronicle/Journey.lua`: progress samples (`FC.db.samples`, `FC:TakeSample`), stats (`FC:JourneyStats`) and the Journey tab charts. Loads after UI.lua and adds its tab on READY.
- `src/chronicle/Professions.lua`: profession/recipe/craft entries (`FC.db.professions`, `FC.db.crafted`), recipe % completion (counted while your own profession window is open) and the Professions tab. Events that might not exist on the client are registered through `tryEvent`.
- `src/ui/UI.lua`: main window (Chronicle tab, quest-log-style Goals tab, `FC:AddWindowTab` for extra tabs) and basic slash commands.
- `scripts/package.sh` (release zips from the `.toc` file list), `scripts/release_notes.sh`.
- `.github/workflows/ci.yml`: tests on every push to main and on PRs. It's also reusable (`workflow_call`).
- `.github/workflows/release.yml`: when a push to main has a `.toc` version with no `v<version>` tag yet, it runs ci.yml, builds the addon zips, builds standalone installers with PyInstaller on Windows and Ubuntu 24.04, smoke-tests them, and publishes the release. A release needs a matching `## [x.y.z]` Changelog section. Lint workflows with `actionlint`. **Every new addon file must be listed in the `.toc`**, otherwise it won't load or be packaged.
- Versions: when releasing, bump `## Version:` in the `.toc` **and** `VERSION` in `companion/fcompanion.py` together (a test checks they match).
- `companion/`: separate Python 3.8+ app (standard library only): `fcompanion.py` (setup/test/watch, SavedVariables parser, Discord/ntfy), tests in `companion/tests` (`python3 -m unittest discover -s companion/tests`). Never execute SavedVariables content, and never log secrets such as the webhook URL.
- `tests/`: `run.lua` (runner), `wow_stub.lua` (fake WoW API), `test_*.lua` (tests). Not loaded by the game. Several fake players can exist at once: `setup({ name = "Buddy" })`, then `transfer(a, b)` delivers a's addon messages to b.
