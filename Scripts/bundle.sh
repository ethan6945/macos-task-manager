#!/bin/bash
# 构建并组装 Task Manager.app（不依赖 Xcode，只用 Command Line Tools）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="Task Manager"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/TaskManager"
[ -f "$BIN" ] || { echo "找不到可执行文件: $BIN" >&2; exit 1; }

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

VERSION="1.0"
BUILD_NUM="$(date +%Y%m%d%H%M)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>io.github.ethan6945.taskmanager</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$BUILD_NUM</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHumanReadableCopyright</key>  <string>致敬 Dave Plummer 的 Windows Task Manager</string>
</dict>
</plist>
PLIST

# 图标没生成过就先生成（纯脚本绘制，见 Scripts/MakeIcon.swift）
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "==> 生成 App 图标"
    mkdir -p "$ROOT/Resources"
    swiftc -O -parse-as-library "$ROOT/Scripts/MakeIcon.swift" -o "$ROOT/.build/makeicon" \
        && "$ROOT/.build/makeicon" "$ROOT/Resources" chip >/dev/null \
        && iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
fi
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc 签名"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    echo "   (签名失败，不影响本地运行)"

echo "==> 完成: $APP"
