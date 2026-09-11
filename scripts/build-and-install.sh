#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ${1:-} == --help ]]; then
  printf 'Usage: %s [installation-directory]\nBuilds a Release DMG, installs the app, and launches it.\n' "$0"
  exit 0
fi
bash scripts/package.sh
bash scripts/install.sh build/DuoFX.dmg "${1:-/Applications}"
