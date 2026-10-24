#!/bin/sh
# Verify checked-in notices against every shipping dependency graph.
set -eu
cd "$(dirname "$0")/.."
exec python3 apps/apple/Scripts/generate-third-party-licenses.py --check "$@"
