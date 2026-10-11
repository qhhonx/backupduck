#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v rustup >/dev/null 2>&1; then
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT
  curl --fail --location --retry 3 https://sh.rustup.rs -o "$installer"
  sh "$installer" -y --profile minimal --default-toolchain none
fi
rustup toolchain install 1.90.0 --profile minimal
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin --toolchain 1.90.0
python3 scripts/check-release.py
mkdir -p build
printf 'DEVELOPMENT_TEAM = %s\n' "${CI_TEAM_ID:?}" > build/AppleSigning.xcconfig
