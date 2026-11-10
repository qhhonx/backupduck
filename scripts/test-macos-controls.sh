#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project apps/macos/BackupDuck.xcodeproj -scheme BackupDuckCatalog \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/macos-controls-tests \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test
