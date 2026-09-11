#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/configure-signing.py
xcodebuild -project DuoFX.xcodeproj -scheme DuoFX \
  -configuration "${CONFIGURATION:-Debug}" -derivedDataPath build build
