#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-pdf-links.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
cp -R "$ROOT/Sources" "$TEMP_DIR/Sources"
python3 - "$TEMP_DIR/Sources/Cardify.swift" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
entry = '@main struct CardifyApp:'
if source.count(entry) != 1:
    raise SystemExit('Expected exactly one Cardify app entry point')
path.write_text(source.replace(entry, 'struct CardifyApp:', 1))
PY
swiftc -target "$(uname -m)-apple-macos13.0" -parse-as-library -module-cache-path "$TEMP_DIR/module-cache" \
    "$TEMP_DIR"/Sources/*.swift "$ROOT/Tests/PreviewLinks/main.swift" -o "$TEMP_DIR/pdf-links-check"
"$TEMP_DIR/pdf-links-check"
