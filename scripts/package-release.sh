#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(python3 -c 'import json; print(json.load(open("release.json"))["version"])')
app=build/macos/BackupDuck.app
codesign --verify --deep --strict "$app"
for arch in arm64 x86_64; do
  xcrun lipo "$app/Contents/MacOS/BackupDuck" -verify_arch "$arch"
done
# Published macOS builds must not embed a personal development certificate.
if ! codesign -dv "$app" 2>&1 | grep -q 'Signature=adhoc'; then
  echo 'Release app must use an ad hoc signature.' >&2; exit 1
fi
mkdir -p build/release
ditto -c -k --keepParent --norsrc "$app" "build/release/BackupDuck-$version-universal.zip"
if [ "${1:-}" = --mac-only ]; then exit 0; fi
cp apps/android/app/build/outputs/apk/release/app-release.apk "build/release/BackupDuck-$version-arm64.apk"
