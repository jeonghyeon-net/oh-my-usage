#!/bin/sh
set -eu
cd "$(dirname "$0")"

sh build.sh
APP="build/oh-my-usage.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/oh-my-usage-${VERSION}-arm64.dmg"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/oh-my-usage-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM

ditto "$APP" "$STAGING/oh-my-usage.app"
ln -s /Applications "$STAGING/Applications"
codesign --verify --strict "$STAGING/oh-my-usage.app"
hdiutil create -volname "oh-my-usage" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
printf '%s\n' "Packaged: $DMG"
