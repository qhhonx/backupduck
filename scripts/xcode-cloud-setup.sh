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
mkdir -p build
# Xcode's bundled Python can predate the standard-library TOML parser. Keep
# compatibility dependencies isolated from the Cloud image's system packages.
python3 -m venv build/cloud-python
build/cloud-python/bin/python -m pip install --disable-pip-version-check 'tomli==2.2.1'
build/cloud-python/bin/python scripts/check-release.py
printf 'DEVELOPMENT_TEAM = %s\n' "${CI_TEAM_ID:?}" > build/AppleSigning.xcconfig
