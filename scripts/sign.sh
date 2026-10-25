#!/bin/bash
set -euo pipefail
if [[ $# != 1 || ! -d "$1" ]]; then echo 'Usage: sign.sh <app>' >&2; exit 2; fi
identity="${UC_SIGNING_IDENTITY:-28107DCFD48A5B3B21DC6726144ACFFDDCE44E0A}"
if [[ "$identity" == '-' || -z "$identity" ]]; then echo 'A permanent identity is required.' >&2; exit 1; fi
security find-identity -v -p codesigning | grep -F "$identity" >/dev/null || {
  echo 'Signing identity is missing. Run scripts/create-signing-identity.sh on the development Mac.' >&2; exit 1;
}
codesign --force --options runtime --timestamp=none --sign "$identity" "$1"
codesign --verify --deep --strict "$1"
codesign -dv --verbose=4 "$1"
