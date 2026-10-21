#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift scripts/generate-icons.swift
iconutil -c icns .build/AppIcon.iconset -o Resources/Icons/AppIcon.icns
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"
APP="dist/Overlyric.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Overlyric" "$APP/Contents/MacOS/Overlyric"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Icons/AppIcon.icns Resources/Icons/MenuBarIcon*.png "$APP/Contents/Resources/"
codesign --force --sign - --entitlements Resources/Overlyric.entitlements "$APP"
echo "Built $(pwd)/$APP"
