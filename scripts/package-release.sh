#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Overlyric.app/Contents/Info.plist)"
ARCHIVE="Overlyric-${VERSION}-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Overlyric.app "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "Packaged $(pwd)/dist/$ARCHIVE"
