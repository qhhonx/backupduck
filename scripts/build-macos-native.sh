#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output=$1
shift
: "${MACOSX_DEPLOYMENT_TARGET:?Set the minimum macOS version}"
# Leave host proc-macro dylibs intact. Strip the final direct-download app.
export CARGO_PROFILE_RELEASE_STRIP=none
# Cargo can reuse an archive across changes to MACOSX_DEPLOYMENT_TARGET.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-target}/macos-$MACOSX_DEPLOYMENT_TARGET"

libraries=
for arch in "$@"; do
  case "$arch" in
    arm64) target=aarch64-apple-darwin ;;
    x86_64) target=x86_64-apple-darwin ;;
    *) echo "Unsupported Mac architecture: $arch" >&2; exit 1 ;;
  esac
  cargo build --locked --release --target "$target" -p backupduck-native --features folder-source
  libraries="$libraries $target"
done

# Build paths can contain spaces. Keep each archive as its own shell argument.
set --
for target in $libraries; do
  set -- "$@" "$CARGO_TARGET_DIR/$target/release/libbackupduck_native.a"
done
mkdir -p "$(dirname "$output")"
xcrun lipo -create "$@" -output "$output"
