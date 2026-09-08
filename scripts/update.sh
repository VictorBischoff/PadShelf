#!/bin/zsh
# Developer update: fetch the latest source and rebuild its installer.
set -eu
cd "${0:A:h}/.."
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit or stash local changes before updating.' >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo 'Switch to main before updating.' >&2; exit 1; }
git fetch origin main
git merge --ff-only origin/main
swift test
./build.sh
./scripts/package-dmg.sh
echo 'Update built: open ../PadShelf-macOS.dmg and replace the app in Applications.'
