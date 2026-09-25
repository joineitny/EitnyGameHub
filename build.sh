#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$(dirname "$ROOT")/EitnyGameHub.app"
SOURCES="$ROOT/Sources"
RESOURCES="$ROOT/Resources"
[[ -d "$SOURCES" ]] || SOURCES="$ROOT"
[[ -d "$RESOURCES" ]] || RESOURCES="$ROOT"
BUILD=${GWENT_BRIDGE_BUILD_DIR:-"$(dirname "$ROOT")/../work/gwentbridge-build"}
mkdir -p "$BUILD/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path "$BUILD/module-cache" -parse-as-library "$SOURCES/EitnyGameHub.swift" "$SOURCES/SteamLibrary.swift" -o "$APP/Contents/MacOS/EitnyGameHub" -framework SwiftUI -framework AppKit
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path "$BUILD/module-cache" -parse-as-library "$SOURCES/GameSettings.swift" "$SOURCES/GameSettingsMain.swift" -o "$APP/Contents/Resources/GameSettings"
codesign --force --sign - "$APP/Contents/Resources/GameSettings"
cp "$RESOURCES/poe.sh" "$APP/Contents/Resources/poe.sh"
cp "$RESOURCES/poe-graphics.sh" "$APP/Contents/Resources/poe-graphics.sh"
cp "$RESOURCES/bridge.sh" "$APP/Contents/Resources/bridge.sh"
cp "$RESOURCES/App_Icon.png" "$APP/Contents/Resources/App_Icon.png"
cp "$RESOURCES/AppIconDisplay.png" "$APP/Contents/Resources/AppIconDisplay.png"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
chmod +x "$APP/Contents/Resources/bridge.sh"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>EitnyGameHub</string>
<key>CFBundleDisplayName</key><string>EitnyGameHub</string>
<key>CFBundleIdentifier</key><string>local.eitnygamehub.launcher</string>
<key>CFBundleExecutable</key><string>EitnyGameHub</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>NSDocumentsFolderUsageDescription</key><string>Библиотека Steam и игры находятся в выбранной папке данных EitnyGameHub.</string>
<key>NSDesktopFolderUsageDescription</key><string>Доступ к выбранной папке данных EitnyGameHub на рабочем столе.</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>EitnyDockIcon</string>
</dict></plist>
PLIST
cp "$RESOURCES/AppIcon.icns" "$APP/Contents/Resources/EitnyDockIcon.icns"
rm -f "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/EitnyIcon.icns"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
