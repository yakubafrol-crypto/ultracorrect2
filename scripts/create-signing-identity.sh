#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
existing=28107DCFD48A5B3B21DC6726144ACFFDDCE44E0A
if security find-identity -v -p codesigning | grep -F "$existing" >/dev/null; then
  echo "Using legacy permanent identity $existing"
  exit 0
fi
if security find-identity -v -p codesigning | grep -F 'UltraCorrect Self-Signed' >/dev/null; then
  echo 'UltraCorrect Self-Signed already exists. Set UC_SIGNING_IDENTITY to its SHA-1.'
  exit 0
fi
# Security.framework creates the private key directly in the login keychain.
swift scripts/CreateSigningIdentity.swift
security find-identity -v -p codesigning
echo 'Set UC_SIGNING_IDENTITY to the new SHA-1 and record it in PLATFORM-NOTES.md.'
