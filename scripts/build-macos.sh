#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=14.0
# Stripping host proc-macro dylibs during a release build can produce a
# malformed Mach-O LINKEDIT on macOS. Strip the final application below.
export CARGO_PROFILE_RELEASE_STRIP=none
./scripts/fetch-sparkle.sh
export CARGO_ENCODED_RUSTFLAGS=$(printf '%s\037%s' "--remap-path-prefix=$PWD=/backupduck" "--remap-path-prefix=$HOME=/builder")
cargo build --locked --release --target aarch64-apple-darwin -p backupduck-native --features folder-source
app=build/macos/BackupDuck.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp apps/macos/BackupDuck/Info.plist "$app/Contents/Info.plist"
python3 scripts/stamp-version.py "$app/Contents/Info.plist"
ditto build/dependencies/sparkle/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
cp assets/BackupDuck.icns "$app/Contents/Resources/"
cp LICENSE "$app/Contents/Resources/"
cp build/dependencies/sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
cp -R apps/apple/Resources/*.lproj "$app/Contents/Resources/"
cp apps/apple/Resources/DuckBrand.png "$app/Contents/Resources/"
xcrun --sdk macosx swiftc -swift-version 5 -O -module-cache-path build/SwiftModuleCache-mac \
 -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macos14.0 -parse-as-library \
 -debug-prefix-map "$PWD=/backupduck" -F build/dependencies/sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
 -import-objc-header crates/native/include/backupduck.h \
 apps/apple/Shared/*.swift apps/macos/BackupDuck/*.swift target/aarch64-apple-darwin/release/libbackupduck_native.a \
 -framework Security -framework SystemConfiguration -framework AVFoundation -framework QuickLookThumbnailing -framework ImageIO -framework CoreServices -framework AppKit -framework SwiftUI -framework Photos -framework Vision -lsqlite3 -lz -liconv \
 -o "$app/Contents/MacOS/BackupDuck"
# Keep a stable local development identity across builds. This optional file is
# ignored by Git; release/CI builds may supply the environment variable instead.
signing_identity="${BACKUPDUCK_MAC_SIGN_IDENTITY:-}"
if [ "${BACKUPDUCK_RELEASE:-0}" != 1 ] && [ -z "$signing_identity" ] && [ -f build/macos-signing-identity ]; then
  IFS= read -r signing_identity < build/macos-signing-identity || true
fi
if [ "${BACKUPDUCK_RELEASE:-0}" = 1 ]; then signing_identity=-; fi
codesign --force --sign - "$app/Contents/Frameworks/Sparkle.framework"
xcrun strip -S "$app/Contents/MacOS/BackupDuck"
codesign --force --sign "${signing_identity:--}" --identifier app.backupduck "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
