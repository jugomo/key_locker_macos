#!/bin/bash
# Builds KeyLocker.app from the Swift sources in Sources/.
#
# The app is deliberately NOT sandboxed: the global CGEventTap used to block
# keyboard/trackpad/mouse input system-wide is not permitted inside the App
# Sandbox, so this can't be a Mac App Store build.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="KeyLocker"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

echo "Compiling..."
swiftc \
    -O \
    -o "$CONTENTS/MacOS/$APP_NAME" \
    -framework AppKit \
    -framework IOKit \
    -framework Security \
    -framework Carbon \
    Sources/*.swift

cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "Generating app icon..."
ICON_MASTER="$BUILD_DIR/icon_master.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift Resources/make_icon.swift "$ICON_MASTER"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo
echo "Next steps:"
echo "  1. Move or run $APP_BUNDLE (e.g. copy it to /Applications)."
echo "  2. Launch it once, then go to System Settings > Privacy & Security >"
echo "     Accessibility and Input Monitoring, and enable KeyLocker in both."
echo "  3. Click the lock icon in the menu bar to set a password and activate the lock."
