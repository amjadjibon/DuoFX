#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
icon_dir=$(mktemp -d "${TMPDIR:-/tmp}/duofx-icon.XXXXXX")
trap 'rm -rf "$icon_dir"' EXIT
xcrun swiftc DuoFX/App/MenuBarIcon.swift scripts/generate-icon.swift -o "$icon_dir/generate-icon"
"$icon_dir/generate-icon" "$icon_dir/DuoFX.iconset"
iconutil -c icns "$icon_dir/DuoFX.iconset" -o DuoFX/Resources/DuoFX.icns
