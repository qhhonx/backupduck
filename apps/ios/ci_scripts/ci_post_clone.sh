#!/bin/sh
set -eu
cd "${CI_PRIMARY_REPOSITORY_PATH:?}"
./scripts/xcode-cloud-setup.sh
