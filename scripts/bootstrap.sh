#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v swift >/dev/null || { echo 'Install Swift 6.' >&2; exit 1; }
if [[ "$(uname -s)" == Darwin ]]; then
  xcodebuild -checkFirstLaunchStatus
  for tool in xcodegen gitleaks; do
    command -v "$tool" >/dev/null || brew install "$tool"
  done
fi
./scripts/check-core-purity.sh
./scripts/fetch-resources.sh
