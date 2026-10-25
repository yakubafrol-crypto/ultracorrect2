#!/bin/bash
set -euo pipefail
if [[ $# != 1 || "$1" != v2.* ]]; then echo 'Usage: reproduce.sh <v2.x-tag>' >&2; exit 2; fi
tag="$1"
root="$(mktemp -d "${TMPDIR:-/tmp}/uc-reproduce.XXXXXX")"
repo="${UC_REPRODUCE_REPOSITORY:-https://github.com/yakubafrol-crypto/ultracorrect2.git}"
# UC_REPRODUCE_REPOSITORY also permits a clean local tag clone before the public tag is created.
git clone --no-local --depth 1 --branch "$tag" "$repo" "$root/repo" > "$root/clone.log" 2>&1
cd "$root/repo"
mkdir -p work
cp "$root/clone.log" work/clone.log
git rev-parse HEAD > work/reproduced-commit.txt
scripts/check-core-purity.sh > work/purity.log 2>&1
swift build > work/build.log 2>&1
swift test --enable-code-coverage > work/tests.log 2>&1
swift run uc-sim --report work/uc-sim-report.json > work/sim.log 2>&1
python3 scripts/coverage.py --minimum 85 --output work/coverage.json > work/coverage.log 2>&1
python3 scripts/compare-evidence.py | tee work/reproduce-comparison.txt
echo "Reproduction logs: $root/repo/work"
