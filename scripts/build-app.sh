#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
for input in Package.swift Resources/Info.plist Resources/MinimalNotch.entitlements; do
  test -f "$input" || { echo "Missing input: $input" >&2; exit 1; }
done
# Refuse symlinked output components before writing any build artifacts.
for output in .build build build/MinimalNotch.app build/MinimalNotch.app/Contents build/MinimalNotch.app/Contents/MacOS; do
  test ! -L "$output" || { echo "Unsafe output: $output" >&2; exit 1; }
done
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MinimalNotch"
test -f "$BIN" || { echo "Missing executable" >&2; exit 1; }
APP="$ROOT/build/MinimalNotch.app"
mkdir -p "$APP/Contents/MacOS"
for output in "$APP/Contents/MacOS/MinimalNotch" "$APP/Contents/Info.plist" "$APP/Contents/_CodeSignature" "$APP/Contents/_CodeSignature/CodeResources"; do
  test ! -L "$output" || { echo "Unsafe output: $output" >&2; exit 1; }
done
cp "$BIN" "$APP/Contents/MacOS/MinimalNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements Resources/MinimalNotch.entitlements "$APP"
codesign --verify --strict "$APP"
echo "$APP"
