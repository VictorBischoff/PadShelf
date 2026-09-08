#!/bin/zsh
set -eu
cd "${0:A:h}"
./scripts/build-icon.sh
swift build -c release --arch arm64 --arch x86_64
APP="../PadShelf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
cp "$BIN_DIR/PadShelf" "$APP/Contents/MacOS/PadShelf"
cp Assets/PadShelf.icns "$APP/Contents/Resources/PadShelf.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PadShelf</string>
<key>CFBundleIdentifier</key><string>studio.padshelf.mac</string>
<key>CFBundleName</key><string>PadShelf</string>
<key>CFBundleDisplayName</key><string>PadShelf</string>
<key>CFBundleIconFile</key><string>PadShelf</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
