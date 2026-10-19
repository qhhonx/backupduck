#!/bin/bash
# Run portable XCTest checks on a fresh, disposable simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/ios-tests
test_root=$(mktemp -d "$PWD/build/ios-tests/run.XXXXXX")
xcrun simctl list runtimes -j > "$test_root/runtimes.json"
python3 - "$test_root/runtimes.json" > "$test_root/destination" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    runtimes = json.load(source)["runtimes"]
available = [runtime for runtime in runtimes if runtime.get("isAvailable")
             and runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
available.sort(key=lambda runtime: tuple(map(int, runtime["version"].split("."))), reverse=True)
for runtime in available:
    phones = [device for device in runtime.get("supportedDeviceTypes", [])
              if device.get("productFamily") == "iPhone"]
    if phones:
        print(phones[0]["identifier"])
        print(runtime["identifier"])
        break
else:
    sys.exit("An available iOS runtime with an iPhone device type is required")
PY
device_type=$(sed -n '1p' "$test_root/destination")
runtime=$(sed -n '2p' "$test_root/destination")
simulator_id=$(xcrun simctl create "BackupDuck CI" "$device_type" "$runtime")
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  # Keep Tests.xcresult; the build products are ~270 MB per run.
  rm -rf "$test_root/DerivedData"
}
trap cleanup EXIT

xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
build_args=(-project apps/ios/BackupDuck.xcodeproj -scheme BackupDuck
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id"
  -derivedDataPath "$test_root/DerivedData" CODE_SIGNING_ALLOWED=YES
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
xcodebuild build-for-testing "${build_args[@]}"
xcrun simctl install "$simulator_id" "$test_root/DerivedData/Build/Products/Debug-iphonesimulator/BackupDuck.app"
# This permission applies only to the new simulator's synthetic photo library.
xcrun simctl privacy "$simulator_id" grant photos app.backupduck
xcodebuild test-without-building "${build_args[@]}" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$test_root/Tests.xcresult" \
  -only-testing:BackupDuckTests \
  -skip-testing:BackupDuckTests/LibraryTests \
  -skip-testing:BackupDuckTests/BackgroundTests \
  -skip-testing:BackupDuckTests/BackgroundPreparationTests/testVideoOriginalExportAndTransfer
printf 'XCTest results: %s/Tests.xcresult\n' "$test_root"
