# Forever Chronicaller: rules for contributors (Claude and humans)

A World of Warcraft addon that chronicles adventures and tracks goals. Read `README.md` for features, `TODO.md` for what's next and `Changelog.md` for history.

## Target client
- **WoW: Forever 1.60.1**: interface and APIs match **retail 12.1.5**. Addon restrictions are similar to **Midnight**.
- Use modern retail APIs, such as `C_Map`, `C_SuperTrack`, `C_QuestLog`, `C_ChatInfo`, the Settings API, the Menu API, `CreateLine` and `BackdropTemplate`. Don't write code for 3.3.5 or vanilla.
- Midnight restrictions: don't build features on the combat log or on combat data (health, auras, cooldowns), which are secret or unavailable. Addon messages are blocked in instances during encounters, M+ and PvP, so queue them.
- Addons have **no network or file access**. Saved data reaches disk only on logout or `/reload`. Anything external (Discord, auto-update, installer) belongs in a separate companion app.

## Workflow rules
0. **Ask before each step.** Before starting each `TODO.md` item or pipeline step, tell the user what the next step is and ask whether to continue. After committing a step, stop, report what changed and ask again. Never chain several steps without approval.
1. **Follow `TODO.md`.** Work items top to bottom unless the user says otherwise. Tick items off (`[x]`) when finished. Add new tasks that come up to the right section.
2. **One change = one commit.** Each finished, self-contained change (one TODO item or one fix) gets its own commit. Don't bundle unrelated changes.
3. **Every commit updates `Changelog.md`.** Add an entry under `## [Unreleased]` (Added / Changed / Fixed / Removed) in the same commit as the change. When a version is released, move Unreleased under a version heading with the date.
4. **Update `TODO.md` in the same commit** as the change it relates to.
5. **Keep `README.md` current** when commands, features or install steps change.
6. **Verify before committing.** At minimum run `luac -p` on every changed `.lua` file. Exercise logic with a stub-API harness where practical, and note in the changelog anything that still needs testing in game.
7. **Commit messages:** a short imperative summary line, then a blank line and details if needed.
8. **Don't** delete user files, rewrite history or push to a remote unless the user asks.

## Layout
- `ForeverChronicaller.toc`: manifest. Load order: Core → Chronicle → Goals → Settings → UI.
- `Core.lua`: saved data (`ForeverChronicallerDB`), event dispatch, internal message system (`FC:On` / `FC:Fire`).
- `Chronicle.lua`: automatic logging (`FC:AddEntry`).
- `Goals.lua`: goal parsing and auto-completion.
- `Settings.lua`: options page (`FC.db.settings`, `FC:OpenSettings`).
- `UI.lua`: window and slash commands (`/chron`, `/fc`).
- `main.lua`, `persistance.lua`: original prototype. Not loaded, can be deleted.
