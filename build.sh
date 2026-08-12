#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Open Anyway"
BUNDLE_ID="com.toshonjennings.openanyway"
VERSION="0.2.0"

cd "$(dirname "$0")"
APP="build/${APP_NAME}.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>OpenAnyway</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHumanReadableCopyright</key><string>Toshon Jennings</string>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc \
    -target arm64-apple-macos14.0 \
    -O -whole-module-optimization \
    -framework AppKit -framework SwiftUI -framework ServiceManagement \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/OpenAnyway"

# Ad-hoc signature: required for the login-item registration to be accepted, and
# it keeps the app itself off the very list it exists to clear.
codesign --force --sign - "$APP"

echo "Built $APP"
