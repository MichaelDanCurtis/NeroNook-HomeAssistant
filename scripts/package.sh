#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)"
app="$PWD/build/Home Assistant Module.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R "$bin/NookPluginSDK_NookPluginSDK.bundle" "$app/Contents/Resources/"
cp "$bin/HomeAssistantPlugin" "$app/Contents/MacOS/HomeAssistantPlugin"
cp Resources/NookPlugin.json "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>cafe.nero.plugin.homeassistant</string>
<key>CFBundleName</key><string>Home Assistant Module</string>
<key>CFBundleExecutable</key><string>HomeAssistantPlugin</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Read rooms and devices from your chosen Home Assistant server and send commands you explicitly select.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
codesign --force --options runtime --sign "${NERONOOK_SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/build/NeroNook-HomeAssistant-0.2.2.zip"
