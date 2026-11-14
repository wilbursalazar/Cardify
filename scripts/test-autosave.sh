#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-autosave.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
python3 - "$ROOT/Sources/Cardify.swift" "$ROOT/Tests/Autosave/SaveChecks.swift.in" "$TEMP_DIR/SaveChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
methods = source[source.index('    func saveMarkdown(saveAs:'):source.index('    func scheduleAutosave()')]
template = Path(sys.argv[2]).read_text()
Path(sys.argv[3]).write_text(template.replace('    // SAVE_METHODS\n', methods))
PY
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/cache" -parse-as-library "$TEMP_DIR/SaveChecks.swift" -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
