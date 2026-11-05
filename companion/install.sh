#!/usr/bin/env sh
# Forever Chronicler installer: finds WoW: Forever and installs the addon.
cd "$(dirname "$0")" || exit 1
exec python3 fcompanion.py install "$@"
