#!/usr/bin/env bash
# Print the Changelog.md section for a version (default: the .toc version).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-$(sed -n 's/^## Version: *//p' ForeverChronicler.toc | tr -d '\r')}
awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' Changelog.md
