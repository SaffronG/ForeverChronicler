#!/usr/bin/env bash
# Build dist/ForeverChronicler-<version>.zip containing only what the game needs
# (plus dist/ForeverChronicler-Installer-<version>.zip, see the end of this script):
# the .toc, every file it lists, README and Changelog, inside a ForeverChronicler/ folder.
# Unzip it into World of Warcraft/<client>/Interface/AddOns/.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=ForeverChronicler
VERSION=$(sed -n 's/^## Version: *//p' "$NAME.toc" | tr -d '\r')
[ -n "$VERSION" ] || { echo "No '## Version:' in $NAME.toc" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME" dist

cp "$NAME.toc" README.md Changelog.md PRIVACY.md "$STAGE/$NAME/"
while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in ''|'#'*) continue ;; esac
    [ -f "$line" ] || { echo "File listed in $NAME.toc is missing: $line" >&2; exit 1; }
    mkdir -p "$STAGE/$NAME/$(dirname "$line")"
    cp "$line" "$STAGE/$NAME/$line"
done < "$NAME.toc"

OUT="dist/$NAME-$VERSION.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qr - "$NAME") > "$OUT"
echo "$OUT"

# Installer bundle for players: companion app + launchers + the addon zip.
# Unzip anywhere, double-click Install.bat (Windows) or run ./install.sh.
BUNDLE="$NAME-Installer"
mkdir -p "$STAGE/$BUNDLE"
cp companion/fcompanion.py companion/fc_telemetry.py companion/README.md companion/Install.bat companion/install.sh PRIVACY.md "$STAGE/$BUNDLE/"
cp "$OUT" "$STAGE/$BUNDLE/"
INSTALLER="dist/$BUNDLE-$VERSION.zip"
rm -f "$INSTALLER"
(cd "$STAGE" && zip -qr - "$BUNDLE") > "$INSTALLER"
echo "$INSTALLER"
