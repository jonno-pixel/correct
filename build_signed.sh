#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
archive="build/JJS.xcarchive"

xcodebuild \
  -project JJS.xcodeproj \
  -scheme JJS \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  archive \
  "$@"

if [[ -n "${JJS_EXPORT_OPTIONS:-}" ]]; then
  xcodebuild \
    -exportArchive \
    -archivePath "$archive" \
    -exportPath build/export \
    -exportOptionsPlist "$JJS_EXPORT_OPTIONS"
fi
