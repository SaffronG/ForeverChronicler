# TODO

Work top to bottom. Tick items off (`[x]`) as they're finished, in the same commit as the change.
Target client: WoW: Forever 1.60.1 (retail 12.1.5-style API, Midnight-style addon restrictions).

## Now
- [ ] **Apply two fixes to existing code**
  - [ ] Set `## Interface:` in `ForeverChronicaller.toc` to the real client number (check in game: `/run print((select(4, GetBuildInfo())))`; expected ~`120105`)
  - [ ] Replace the `GetQuestReward` hook in `Chronicle.lua` with the `QUEST_TURNED_IN` event (quest ID → title via `C_QuestLog`); make quest goals match on ID where possible

## Next (planned for the build day)
- [ ] **#1 Configure auto-chronicaller** – Settings API options page; on/off per event type (level, zone, quest, death, achievement), optional entry cap
- [ ] **#7 Map goals** – modifier + right-click on world map → context menu "Set as goal"; use built-in user waypoint + super-tracking for the arrow; custom map pins for goals; auto-complete on proximity (open world only)
- [ ] **#2 Goal tracker / quest-style menu** – own on-screen tracker frame (don't hook Blizzard's objective tracker); goal log with details (description, category, created date, progress)
- [ ] **#3 Share goals with party** – register addon message prefix; send/accept popup; chunk messages >255 bytes; validate incoming data; outgoing queue that waits while messaging is restricted (instances during encounters / M+ / PvP)

## Later
- [ ] **#4 Backup / load elsewhere** – export/import string (serialize + compress + Base64 if available); merge rules; document copying the SavedVariables file; consider account-wide data
- [ ] **#5 Graphs / visualizers** – record samples (level, played time, gold) over time; in-game line/bar charts
- [ ] **#6 Shared goals with a friend** – builds on #3; offline sync queue, resync on login/group join, conflict rules; progress is trust-based
- [ ] **#8 CI/CD** – GitHub repo; Actions: luacheck, stub-API smoke test, package zip + GitHub Release on tag

## Separate project: companion app (outside the game)
- [ ] **#10 Discord webhooks / push notifications** – addon prints tagged lines; app tails `Logs/WoWChatLog.txt` (`/chatlog`) and posts to webhook / ntfy / Pushover; check WoW: Forever rules on external tools
- [ ] **#11 Auto-update / auto-reload** – app pulls GitHub Releases; in-game "reload now?" popup; in-game version check over addon messages
- [ ] **#9 Simple installer** – locate WoW: Forever install, copy addon (and companion app)
