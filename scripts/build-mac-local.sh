#!/bin/bash
# Build the direct-download Mac app in Release, signed with the local
# development identity, so repeated builds keep one code identity and macOS
# does not ask again for Photos access. Judge motion and feel on this build,
# never on Debug. The team comes from the ignored build/AppleSigning.xcconfig.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
config="$root/build/AppleSigning.xcconfig"
team="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$config" 2>/dev/null | head -1)"
if [ -z "$team" ]; then
  echo "Missing DEVELOPMENT_TEAM in build/AppleSigning.xcconfig" >&2; exit 1
fi
identity="${BACKUPDUCK_SIGN_IDENTITY:-Apple Development}"
output="${1:-$root/build/mac-release}"
cd "$root/apps/macos"
xcodebuild -project BackupDuck.xcodeproj -scheme BackupDuck -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$output" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
  PROVISIONING_PROFILE_SPECIFIER="" build | tail -3
app="$output/Build/Products/Release/BackupDuck.app"
codesign -dv "$app" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" | head -4
echo "$app"
