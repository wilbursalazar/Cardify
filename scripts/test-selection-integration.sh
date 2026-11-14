#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-selection-integration.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
cp -R "$ROOT/Sources" "$TEMP_DIR/Sources"
python3 - "$TEMP_DIR/Sources/Cardify.swift" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
assert s.count('@main struct CardifyApp:') == 1
p.write_text(s.replace('@main struct CardifyApp:', 'struct CardifyApp:', 1))
PY
swiftc -target "$(uname -m)-apple-macos13.0" -parse-as-library -module-cache-path "$TEMP_DIR/cache" \
    "$TEMP_DIR"/Sources/*.swift "$ROOT/Tests/SelectionToolbar/Integration.swift" -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
