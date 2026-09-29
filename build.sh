#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="build/oh-my-usage.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 Core.swift App.swift -o "$APP/Contents/MacOS/oh-my-usage" -framework AppKit -framework ServiceManagement
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>oh-my-usage</string>
<key>CFBundleIdentifier</key><string>local.oh-my-usage</string>
<key>CFBundleName</key><string>oh-my-usage</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf '%s\n' "Built: $APP"
