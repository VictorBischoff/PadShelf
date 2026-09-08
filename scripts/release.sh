#!/bin/zsh
# Run from a clean checkout after committing a VERSION bump.
set -eu
cd "${0:A:h}/.."
VERSION=$(cat VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit or stash local changes first.' >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo 'Release from main.' >&2; exit 1; }
REPOSITORY=VictorBischoff/PadShelf
TAG="v$VERSION"
git fetch origin main
git merge --ff-only origin/main
# Stop if fetching changed the version under this invocation.
[[ "$(cat VERSION)" == "$VERSION" ]] || { echo 'Version changed after fetching; run again.' >&2; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo 'This version already has a local tag. Bump VERSION first.' >&2; exit 1; }
swift test
./build.sh
./scripts/package-dmg.sh
/usr/bin/ditto -c -k --sequesterRsrc --keepParent ../PadShelf.app ../PadShelf-macOS.zip
# Icon generation can vary between macOS tool versions; release only a committed source tree.
git diff --quiet || { echo 'Build changed tracked assets. Commit them and rerun.' >&2; exit 1; }
git push origin main
git tag -a "$TAG" -m "PadShelf $VERSION"
git push origin "$TAG"
gh release create "$TAG" ../PadShelf-macOS.dmg ../PadShelf-macOS.zip --repo "$REPOSITORY" --verify-tag --title "PadShelf $VERSION" --generate-notes
