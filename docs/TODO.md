# TODO

Work top to bottom. Tick items off (`[x]`) as they're finished, in the same commit as the change.
Target client: WoW: Forever 1.60.1 (retail 12.1.5-style API, Midnight-style addon restrictions).

## Now
- [x] **Apply two fixes to existing code**
  - [x] Set `## Interface:` in `ForeverChronicler.toc` to the real client number (check in game: `/run print((select(4, GetBuildInfo())))`; the client reports `16001`)
  - [x] Replace the `GetQuestReward` hook in `Chronicle.lua` with the `QUEST_TURNED_IN` event (quest ID → title via `C_QuestLog`); make quest goals match on ID where possible

- [x] Confirm the Interface number in game: WoW: Forever 1.60.1 reports `16001` (not `120105`)
- [x] Do a first in-game test (`/chron goal level 2`, `/chron note hello`, `/reload`, check persistence)

## Next (planned for the build day)
- [x] **#1 Configure auto-chronicler** – Settings API options page; on/off per event type (level, zone, quest, death, achievement), optional entry cap
- [x] **#7 Map goals** – modifier + right-click on world map → context menu "Set as goal"; use built-in user waypoint + super-tracking for the arrow; custom map pins for goals; auto-complete on proximity (open world only)
- [x] **#7b Map pins for all location goals** – custom world-map pins (MapCanvas data provider + XML pin template) so every open location goal shows on the map, not just the one with the active waypoint. Deferred from #7 because it needs an XML template that can only really be checked in game
- [x] **#2 Goal tracker / quest-style menu** (categories were left out; notes cover it for now)
  - [x] #2a On-screen tracker frame (own frame, not Blizzard's objective tracker)
  - [x] #2b Quest-log-style goal log with details (description, type, created/completed dates, progress)
- [x] **#3 Share goals with party** – register addon message prefix; send/accept popup; chunk messages >255 bytes; validate incoming data; outgoing queue that waits while messaging is restricted (instances during encounters / M+ / PvP)

## Later
- [x] **#4 Backup / load elsewhere** – export/import string (serialize + compress + Base64 if available); merge rules; document copying the SavedVariables file; consider account-wide data
- [x] **#5 Graphs / visualizers** – record samples (level, played time, gold) over time; in-game line/bar charts
- [x] **#6 Shared goals with a friend** – builds on #3; offline sync queue, resync on login/group join, conflict rules; progress is trust-based
- [x] **#8 CI/CD** – GitHub repo; Actions: luacheck, stub-API smoke test, package zip + GitHub Release on tag

- [x] **#6b Together goals for locations** – needs MapGoals' arrival check to report "my part done" for shared goals

- [x] Create the GitHub repository and push (`git remote add origin …`, `git push -u origin main --tags`). Needs the user, since there's no remote or `gh` CLI here. CI starts working once it's pushed

## Next: 0.4.1
- [x] **Reorganize the repository**: addon code into `src/<feature>/`, developer docs into `docs/`
- [x] Check in game that the addon still loads from the `src/` subfolders
- [x] **Professions, crafting and recipes**: auto-entries (new profession, every 25 skill, max skill, recipes learned with trainer bursts summed up, first craft per item, craft milestones), recipe % completion per profession, Professions tab with bars, Recipes/Crafts graphs in the Journey tab, export/import
- [ ] Check professions in game: that `GetProfessionInfo`'s skill line ID matches `C_TradeSkillUI.GetBaseProfessionInfo().professionID` (otherwise records are matched by name), that `NEW_RECIPE_LEARNED` and `TRADE_SKILL_ITEM_CRAFTED_RESULT` fire on WoW: Forever, and that recipe totals look right
- [x] **Night elf window and parchment chronicle**: themed window (sky gradient, stars, crescent moon, silver borders, Morpheus title, themed buttons and tabs), chronicle on a parchment scroll with rollers, event colours kept as readable ink
- [x] **0.9.5 Window themes**: Night Elf, Alliance, Horde, Blood Elf; `/chron theme`, options dropdown, live repaint (`THEME_CHANGED`)
- [ ] Check the themes in game: each theme's colours, crest textures (`Interface\Timer\Alliance-Logo` / `Horde-Logo`), Skurri/Friz title fonts, the options dropdown
- [ ] Check the new look in game: parchment atlas or fallback colours, Morpheus title font, crescent moon mask, button states, ink colours readable for every entry type
- [x] **Fix the misspelled name**: `ForeverChronicaller` → `ForeverChronicler` everywhere (toc, folder, saved data, globals, slash/popup names, release assets, companion, docs), with carry-over of old saved data and installs
- [ ] Check the rename in game: an old character's chronicle is carried over after installing 0.6.0 with the installer, and only one copy of the addon is listed
- [ ] Idea: profession goals (`/chron goal tailoring 300`, `/chron goal recipes tailoring 80%`)
- [ ] **Grafana dashboard** (free tier): importable dashboard JSON (`grafana/`), with panels for errors by version, error locations, success rate, latency p50/p95 and traces. Waiting on Grafana access
- [ ] Before switching telemetry on: drop `error.message` from metric labels (keep it on traces) to limit series on the free tier, add `service.instance.id` (= the random install ID), set the `OTEL_ENDPOINT` / `OTEL_HEADERS` secrets, then set `FEATURE_TELEMETRY = True` (+ `FC.FEATURES.diagnostics`), update PRIVACY.md §3 and the DISCLAIMER, and bump `TERMS_VERSION`

## Journey journal (epistolary record, 0.6.0+)
One letter per day (04:00 to 04:00) in a race/class voice, with that day's stats. Each step below adds data to the day's stats and, where it fits, a sentence to the letter. Combat-log and combat data stay off limits (Midnight rules).
- [x] **Step 1: daily letters + day viewer**: daily ledger (time played, level, gold, zones), per-day stats from the chronicle, letter composer with race (greeting, sign-off, faction fallback) and class (tone) voices, Letters tab (day list, letter, stats), `/chron letter [date]`, export/import
- [ ] **Step 2: travel**: subzones discovered (`ZONE_CHANGED`), hearthstone home (`HEARTHSTONE_BOUND`, `GetBindLocation`), flight paths learned/taken (`C_TaxiMap`), inns rested at (`PLAYER_UPDATE_RESTING`), distance walked (open world, from position samples)
- [x] **0.8.0 Trophies**: notable loot (first loot per item at or above a chosen quality, credited to a just-defeated boss), bosses defeated (`ENCOUNTER_END`/`BOSS_KILL`, first kill per difficulty), rare monsters and world bosses slain (target dead and not tap-denied, or corpse looted), `/chron trophies`, letter sentences + day stats, export/import
- [ ] Check trophies in game: `ENCOUNTER_END`/`BOSS_KILL`/`CHAT_MSG_LOOT`/`ENCOUNTER_LOOT_RECEIVED` fire and aren't secret, rare detection via `UnitClassification`/`UnitIsDead`/`UnitIsTapDenied`, loot strings on non-English clients
- [ ] **Step 3: growth**: gear changes and item level milestones (`PLAYER_EQUIPMENT_CHANGED`, `GetAverageItemLevel`), first rare/epic loot (done in 0.8.0), reputation standings (`UPDATE_FACTION`), new mounts/pets/toys/titles, gold earned vs spent
- [ ] **Step 4: atmosphere**: in-game time of day in the letter (`GetGameTime`), holidays (`C_Calendar`), screenshots taken (`SCREENSHOT_SUCCEEDED`), chapter headings at new zones/level bands
- [ ] **Step 5: dungeons and bosses**: instances entered (`GetInstanceInfo`); bosses defeated is done in 0.8.0 (check `ENCOUNTER_END` is allowed on WoW: Forever)
- [x] **Step 6: companions (0.9.0)**: who you grouped with and for how long, where, raids and bosses shared, time-together milestones, friends made (with shared history), group history, `/chron companions [name]`, letter sentences + day stats, export/import (local only; never posted by the companion by default)
- [ ] Check companions in game: roster names/class/race/level on `party`/`raid` units, roster known by `PLAYER_ENTERING_WORLD` (no split sessions on login), `C_FriendList.GetFriendInfoByIndex` names, cross-realm names
- [ ] Idea: a Companions tab in the window (the tab row is full at 640 px; needs a wider window or a "More" menu)
- [ ] **Step 7: companion**: post each finished day's letter to Discord/ntfy (off by default; needs the letter stored when the day ends)
- [ ] Check in game: Letters tab layout, race/class tokens from `UnitRace`/`UnitClass`, active-time ticker

## Separate project: companion app (outside the game)
- [x] **#10 Discord webhooks / push notifications** – done by watching the SavedVariables files (reliable) instead of the chat log (unclear whether addon output is logged). Posts on logout or `/chron sync`. Still to do: check WoW: Forever rules on external tools (it only reads files)
- [x] **#11 Auto-update / auto-reload**: in-game version check (0.2.0), plus `fcompanion.py update` (GitHub releases, validated zip, backup and rollback). Auto-*reload* isn't possible safely: the game must restart for new files, so the companion refuses while WoW runs – app pulls GitHub Releases; in-game "reload now?" popup; in-game version check over addon messages
- [x] **#9 Simple installer**: `fcompanion.py install` plus `Install.bat` / `install.sh`, shipped as the Installer zip
