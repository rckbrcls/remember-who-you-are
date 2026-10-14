#!/bin/zsh
# Builds a release binary and wraps it in a menu-bar-only .app bundle.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/RememberWhoYouAre"
APP="build/Remember Who You Are.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/RememberWhoYouAre"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Frameworks"
SPARKLE=$(find .build/artifacts -type d -name Sparkle.framework -path "*macos*" | head -1)
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/RememberWhoYouAre" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RememberWhoYouAre</string>
<key>CFBundleIdentifier</key><string>com.rckbrcls.RememberWhoYouAre</string>
<key>CFBundleName</key><string>Remember Who You Are</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD}</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>SUFeedURL</key><string>${RWYA_FEED_URL:-https://rckbrcls.github.io/remember-who-you-are/appcast.xml}</string>
<key>SUPublicEDKey</key><string>${RWYA_ED_KEY:-}</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built: $APP"
pkill -9 -x RememberWhoYouAre 2>/dev/null || true
sleep 1
open "$APP"
