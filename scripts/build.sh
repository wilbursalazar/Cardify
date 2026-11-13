#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Cardify.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/module-cache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
swiftc -module-cache-path "$ROOT/build/module-cache" -parse-as-library -O "$ROOT/Sources/Cardify.swift" "$ROOT/Sources/HabitTemplate.swift" -o "$APP/Contents/MacOS/Cardify"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
