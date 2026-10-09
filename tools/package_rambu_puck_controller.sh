#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/tools/rambu-puck-agent"
APP_RELATIVE_PATH="build/Rambu Puck.app/Contents/MacOS"
APP_DIR="$ROOT_DIR/build/Rambu Puck.app"

swift build -c release --package-path "$PACKAGE_DIR" --product RambuPuckController
BIN_DIR="$(swift build -c release --package-path "$PACKAGE_DIR" --show-bin-path)"

mkdir -p "$ROOT_DIR/$APP_RELATIVE_PATH"
mkdir -p "$APP_DIR/Contents/Resources"
install -m 755 "$BIN_DIR/RambuPuckController" "$APP_DIR/Contents/MacOS/RambuPuckController"
install -m 644 \
    "$PACKAGE_DIR/Resources/RambuPuckController-Info.plist" \
    "$APP_DIR/Contents/Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist"

echo "Packaged: $APP_DIR"
