#!/bin/zsh
set -eu
cd "${0:A:h}/.."
[[ -d ../PadShelf.app ]] || { echo 'Run ./build.sh first.' >&2; exit 1; }
STAGE=$(mktemp -d .build/dmg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto ../PadShelf.app "$STAGE/PadShelf.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname PadShelf -srcfolder "$STAGE" -format UDZO -ov ../PadShelf-macOS.dmg
hdiutil verify ../PadShelf-macOS.dmg
