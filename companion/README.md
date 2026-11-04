# Forever Chronicaller companion app

A small program that runs **outside** the game, next to the addon. It needs Python 3.8 or newer and nothing else.

WoW addons can't use the internet, so the companion does the parts the addon can't:

- **Discord and phone notifications** for new chronicle entries (level ups, goals achieved, new zones, deaths, …)

## How it works
The game saves addon data only when you **log out** or **reload** the UI. The companion watches those saved files and posts any entries it hasn't posted before.

To post right away while playing, type `/chron sync` in game. It asks, then reloads your UI.

The first time it sees a character, it only remembers where that character is up to. It won't post your whole history.

## Setup
1. Install Python from [python.org](https://www.python.org/) (Windows: tick "Add python.exe to PATH").
2. In this folder, run:
   ```
   python fcompanion.py setup
   ```
   - **WoW folder:** the folder that contains `Interface` and `WTF`.
   - **Discord webhook (optional):** in your Discord server, open the channel's settings → Integrations → Webhooks → New Webhook → Copy Webhook URL. Treat it like a password.
   - **ntfy topic (optional, for phone notifications):** install the free **ntfy** app, subscribe to a topic name that's hard to guess (for example `chase-wow-8f3k2`), and enter the same name here. Anyone who knows the topic name can read it.
3. `python fcompanion.py test` sends a test message.
4. `python fcompanion.py watch` runs while you play. Leave it open, and stop it with Ctrl+C.

The settings are stored in `%APPDATA%\forever-chronicaller\config.json` (Windows) or `~/.config/forever-chronicaller/config.json`. There you can also choose which entry types are posted (`post_kinds`; quests are off by default) and limit it to certain characters (`characters`).

## Development
`python3 -m unittest discover -s companion/tests`
