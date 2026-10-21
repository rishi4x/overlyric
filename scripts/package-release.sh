#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Overlyric.app/Contents/Info.plist)"
IMAGE="Overlyric-${VERSION}-macos-universal.dmg"
STAGING="$(mktemp -d "$PWD/dist/.dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto dist/Overlyric.app "$STAGING/Overlyric.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Overlyric" -srcfolder "$STAGING" -format UDZO -ov "dist/$IMAGE"
(cd dist && shasum -a 256 "$IMAGE" > SHA256SUMS.txt)
echo "Packaged $(pwd)/dist/$IMAGE"
