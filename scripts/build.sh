#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Cardify.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/module-cache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
SOURCES=("$ROOT/Sources/Cardify.swift" "$ROOT/Sources/HabitTemplate.swift" "$ROOT/Sources/MarkdownEditor.swift" "$ROOT/Sources/MarkdownRendering.swift" "$ROOT/Sources/NotePicker.swift")
for ARCH in arm64 x86_64; do
    swiftc -target "$ARCH-apple-macos13.0" -module-cache-path "$ROOT/build/module-cache" -parse-as-library -O "${SOURCES[@]}" -o "$ROOT/build/Cardify-$ARCH"
done
lipo -create "$ROOT/build/Cardify-arm64" "$ROOT/build/Cardify-x86_64" -output "$APP/Contents/MacOS/Cardify"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
