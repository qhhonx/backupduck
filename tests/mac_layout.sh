#!/bin/bash
# macOS-only visual checks; renders fixture state, not the user's photo library.
set -euo pipefail
cd "$(dirname "$0")/.."
work=build/mac-layout-check
app="$work/LayoutCheck.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
python3 - <<'PY'
from pathlib import Path
import plistlib
Path('build/mac-layout-check/LayoutCheck.app/Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'app.backupduck.layout-tests',
    'CFBundleExecutable': 'LayoutCheck', 'CFBundleName': 'BackupDuck Layout Check',
    'CFBundlePackageType': 'APPL', 'CFBundleDevelopmentRegion': 'en',
    'CFBundleLocalizations': ['en', 'zh-Hans'], 'CFBundleShortVersionString': '0.1.0',
    'LSUIElement': True,
}))
PY
native_library="${BACKUPDUCK_LAYOUT_NATIVE_LIBRARY:-target/aarch64-apple-darwin/release/libbackupduck_native.a}"
if [[ -z "${BACKUPDUCK_LAYOUT_NATIVE_LIBRARY:-}" ]]; then
  MACOSX_DEPLOYMENT_TARGET=15.0 cargo build --locked --release --target aarch64-apple-darwin -p backupduck-native --features folder-source -j 2
fi
if [[ ! -d build/dependencies/sparkle/Sparkle.framework ]]; then ./scripts/fetch-sparkle.sh; fi
mkdir -p "$app/Contents/Frameworks"
ditto build/dependencies/sparkle/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
cp -R apps/apple/Resources/*.lproj "$app/Contents/Resources/"
cp apps/apple/Resources/DuckBrand.png "$app/Contents/Resources/"
cp apps/apple/Resources/DuckMenuBar.pdf "$app/Contents/Resources/"
sources=(apps/apple/Shared/*.swift)
for file in apps/macos/BackupDuck/*.swift; do
  # The renderer owns the process entry point; all production views stay intact.
  if [[ "$file" != */MacAppMain.swift ]]; then sources+=("$file"); fi
done
xcrun --sdk macosx swiftc -swift-version 5 -Onone -module-cache-path build/SwiftModuleCache-mac \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macos14.0 -parse-as-library \
  -F build/dependencies/sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -import-objc-header crates/native/include/backupduck.h \
  "${sources[@]}" tests/render_macos.swift \
  "$native_library" \
  -framework Security -framework SystemConfiguration -framework AppKit -framework SwiftUI \
  -framework Photos -framework PhotosUI -framework AVKit -framework Vision -framework AVFoundation -framework QuickLookThumbnailing -framework ImageIO -framework CoreServices -lsqlite3 -lz -liconv -o "$app/Contents/MacOS/LayoutCheck"
codesign --force --sign - "$app"
for language in en zh-Hans; do
  "$app/Contents/MacOS/LayoutCheck" "$work/screenshots/$language" -AppleLanguages "($language)" "$@"
done
