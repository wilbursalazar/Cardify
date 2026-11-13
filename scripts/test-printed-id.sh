#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-id-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Use the production source, disabling only the app entry point so the test
# harness can provide its own @main without launching the app or writing files.
cp -R "$ROOT/Sources" "$TEMP_DIR/Sources"
python3 - "$TEMP_DIR/Sources/Cardify.swift" "$TEMP_DIR/Sources/Cardify.swift" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
old = '@main struct CardifyApp:'
if source.count(old) != 1:
    raise SystemExit('Expected exactly one Cardify app entry point')
Path(sys.argv[2]).write_text(source.replace(old, 'struct CardifyApp:', 1))
PY

swiftc -target "$(uname -m)-apple-macos13.0" -parse-as-library -module-cache-path "$TEMP_DIR/module-cache" \
    "$TEMP_DIR"/Sources/*.swift "$ROOT/Tests/PrintedID/main.swift" -o "$TEMP_DIR/printed-id-check"
"$TEMP_DIR/printed-id-check"
