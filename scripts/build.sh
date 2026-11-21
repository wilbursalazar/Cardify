#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Kaster.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/module-cache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Typst is bundled so cards typeset offline on any Mac. Set KASTER_TYPST to choose the binary.
TYPST_BIN="${KASTER_TYPST:-$(command -v typst || true)}"
rm -rf "$APP/Contents/Resources/typst"; mkdir -p "$APP/Contents/Resources/typst"
cp -R "$ROOT/Resources/Typst/packages" "$APP/Contents/Resources/typst/packages"
cp "$ROOT/Resources/Typst/NOTICE.md" "$APP/Contents/Resources/typst/NOTICE.md"
if [ -n "$TYPST_BIN" ]; then
    cp -L "$TYPST_BIN" "$APP/Contents/Resources/typst/typst"; chmod 755 "$APP/Contents/Resources/typst/typst"
    echo "Bundled $("$TYPST_BIN" --version) ($(lipo -archs "$TYPST_BIN"))"
else
    echo "warning: typst not found; install it (brew install typst) or set KASTER_TYPST. Kaster will fall back to an installed typst or the basic renderer." >&2
fi
SOURCES=("$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/App/*.swift "$ROOT/Sources/Main.swift")
for ARCH in arm64 x86_64; do
    swiftc -target "$ARCH-apple-macos13.0" -module-cache-path "$ROOT/build/module-cache" -parse-as-library -O "${SOURCES[@]}" -o "$ROOT/build/Kaster-$ARCH"
done
lipo -create "$ROOT/build/Kaster-arm64" "$ROOT/build/Kaster-x86_64" -output "$APP/Contents/MacOS/Kaster"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
