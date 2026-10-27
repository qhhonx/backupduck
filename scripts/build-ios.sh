#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cargo fetch --locked
python3 apps/apple/Scripts/generate-third-party-licenses.py --platform ios --check
platform="${1:-simulator}"
case "$platform" in
 simulator) target=aarch64-apple-ios-sim; sdk=iphonesimulator; swift_target=arm64-apple-ios18.0-simulator;;
 device) target=aarch64-apple-ios; sdk=iphoneos; swift_target=arm64-apple-ios18.0;;
 *) echo 'Usage: build-ios.sh [simulator|device]' >&2; exit 1;;
esac
export IPHONEOS_DEPLOYMENT_TARGET=18.0
CARGO_PROFILE_RELEASE_STRIP=none cargo build --locked --release -p backupduck-native --no-default-features --target "$target"
app="build/ios/$platform/BackupDuck.app"
mkdir -p "$app"
cp apps/ios/BackupDuck/Info.plist "$app/Info.plist"
python3 scripts/stamp-version.py "$app/Info.plist" --ios
cp -R apps/apple/Resources/*.lproj "$app/"
rm -f "$app/ThirdPartyLicenses-ios.json"
cp apps/apple/Resources/BackupDuckLicense.txt apps/apple/Resources/ThirdPartyNotices-ios.txt "$app/"
cp apps/apple/Resources/DuckBrand.png "$app/"
set --
if [ "$platform" = simulator ]; then
    set -- -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker apps/ios/Simulator.entitlements
fi
xcrun --sdk "$sdk" swiftc -swift-version 5 -O -module-cache-path "build/SwiftModuleCache-ios/$platform" \
 -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" -target "$swift_target" -parse-as-library \
 "$@" -import-objc-header crates/native/include/backupduck.h \
 apps/ios/BackupDuck/*.swift apps/apple/Shared/*.swift "target/$target/release/libbackupduck_native.a" \
 -framework Security -framework SystemConfiguration -framework UIKit -framework SwiftUI -framework Photos -framework PhotosUI -framework AVFoundation -lsqlite3 -lz -liconv \
 -o "$app/BackupDuck"
if [ "$platform" = simulator ]; then codesign --force --sign - "$app"; fi
printf 'Built %s\n' "$app"
