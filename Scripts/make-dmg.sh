#!/bin/bash
# 打一个可直接拖到「应用程序」的 DMG。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Task Manager"
APP="$ROOT/build/$APP_NAME.app"
VERSION="${VERSION:-$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 1.0)}"
DMG="$ROOT/build/TaskManager-$VERSION.dmg"

[ -d "$APP" ] || { echo "先跑 make build" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> 准备 DMG 内容"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 把安装说明一起放进去 —— 没有 Apple 公证，用户第一次打开一定会被 Gatekeeper 拦
cat > "$STAGE/READ ME FIRST.txt" <<'NOTE'
Task Manager for macOS
======================

1. Drag "Task Manager.app" onto the Applications folder.

2. The first launch will be blocked, because this app is not
   notarized by Apple (that requires a paid Apple Developer ID).
   macOS will say it "cannot be opened" or "is damaged".

   To open it:
     System Settings > Privacy & Security > scroll down >
     click "Open Anyway" next to Task Manager > confirm.

   Or, in Terminal:
     xattr -dr com.apple.quarantine "/Applications/Task Manager.app"

   You only need to do this once.

3. No password, no admin rights, no permission prompts are needed
   to use the app. It reads everything through public system APIs.

Source: https://github.com/ethan6945/macos-task-manager
NOTE

echo "==> hdiutil create"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo "==> 完成: $DMG ($(du -h "$DMG" | cut -f1))"
