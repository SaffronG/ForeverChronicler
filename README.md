# Forever Chronicaller

Automatically chronicles your adventure and tracks personal goals.

## Install
Copy (or symlink) this folder into `World of Warcraft/Interface/AddOns/ForeverChronicaller/`.
The folder name must match `ForeverChronicaller.toc`.

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
| `/chron config` | open the options page |

Goals that complete automatically:
`level 30`, `zone Stranglethorn Vale`, `quest The Defias Brotherhood` (or `quest <questID>` for an exact match).
Anything else is a free-form goal you tick off yourself.

## Files
- `Core.lua` – SavedVariables (persistence), event dispatch
- `Chronicle.lua` – automatic event logging
- `Goals.lua` – goal parsing / auto-completion
- `Settings.lua` – options page (Settings API)
- `UI.lua` – window and slash commands

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