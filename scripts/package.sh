#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION=Release bash scripts/build.sh
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/duofx-package.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
ditto build/Build/Products/Release/DuoFX.app "$staging_dir/DuoFX.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname DuoFX -srcfolder "$staging_dir" -ov -format UDZO build/DuoFX.dmg
