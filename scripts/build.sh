#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-signed}"
[[ "$mode" == signed || "$mode" == --unsigned-ci ]] || { echo 'Usage: build.sh [--unsigned-ci]' >&2; exit 2; }
./scripts/check-core-purity.sh
swift build
xcodegen generate
mkdir -p work
# Strictly monotonic local build number; CI supplies its monotonically growing run number.
if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then build=$((31+GITHUB_RUN_NUMBER)); else
  previous=30
  [[ ! -f work/build-number ]] || read -r previous < work/build-number
  build=$((previous+1)); echo "$build" > work/build-number
fi
xcodebuild -project UltraCorrect2.xcodeproj -scheme UltraCorrect -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath work/DerivedData \
  CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="$build" build
if [[ "$mode" == signed ]]; then
  for app in UltraCorrect UCTestHost; do ./scripts/sign.sh "work/DerivedData/Build/Products/Debug/$app.app"; done
fi
