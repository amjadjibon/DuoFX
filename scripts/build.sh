#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project DuoFX.xcodeproj -scheme DuoFX \
  -configuration "${CONFIGURATION:-Debug}" -derivedDataPath build build
