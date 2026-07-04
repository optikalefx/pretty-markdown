#!/bin/bash
#
# Build PrettyMarkdown and assemble a signed .app bundle from scratch.
# Everything the bundle needs lives in Packaging/ so this is fully reproducible
# — never hand-edit outputs/PrettyMarkdown.app, re-run this instead.
#
set -euo pipefail

APP_NAME="PrettyMarkdown"
CONFIG="${1:-release}"                 # ./package.sh [debug|release]
ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/Packaging"
APP="$ROOT/outputs/$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
# SwiftPM resource bundle (theme.css, JS, Sample.md) — Bundle.module finds it
# in Contents/Resources when running from the .app.
cp -R "$(dirname "$BIN")/${APP_NAME}_${APP_NAME}.bundle" "$APP/Contents/Resources/"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Generating AppIcon.icns"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  x2=$((size * 2))
  sips -s format png -z "$size" "$size" "$PKG/AppIcon.png" \
    --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
  sips -s format png -z "$x2"   "$x2"   "$PKG/AppIcon.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Registering with LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null || true

echo "==> Done: $APP"
