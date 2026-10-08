#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
# A fresh output directory keeps older builds available for rollback.
mkdir -p dist
output="$(mktemp -d "$PWD/dist/build-XXXXXX")"
trap 'echo "Build directory: $output"' EXIT
app="$output/EVE Connect.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/EVEConnect" "$app/Contents/MacOS/EVEConnect"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/render-icon.swift "$output"
iconutil -c icns "$output/EVEConnect.iconset" -o "$app/Contents/Resources/EVEConnect.icns"
codesign --sign "${SIGNING_IDENTITY:--}" --options runtime \
    --entitlements Resources/EVEConnect.entitlements "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
