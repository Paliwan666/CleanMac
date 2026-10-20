#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 编译 release"
swift build -c release --product CleanMac
BIN_DIR=$(swift build -c release --show-bin-path)

APP="dist/CleanMac.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CleanMac" "$APP/Contents/MacOS/CleanMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> 生成图标"
mkdir -p dist
swift scripts/make_icon.swift dist/icon_1024.png
ICONSET="dist/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" dist/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" dist/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" --output "$APP/Contents/Resources/AppIcon.icns"

echo "==> 签名（ad-hoc）"
codesign --force --sign - "$APP"

echo "==> 完成: $(cd dist && pwd)/CleanMac.app"
