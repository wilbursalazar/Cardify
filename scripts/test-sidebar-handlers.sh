#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-sidebar-handlers.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
python3 - "$ROOT/Sources/Cardify.swift" "$ROOT/Tests/SidebarHandlers/Checks.swift.in" "$TEMP_DIR/Checks.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
first = source[source.index('    private var sidebarRoot:'):source.index('    private func revealSidebarNote(')]
second = source[source.index('    private func duplicateSidebarNote('):source.index('\n}\n\n// WindowGroup')]
methods = (first + second).replace('    private ', '    ')
old = 'try FileManager.default.trashItem(at: mutation.snapshot.url, resultingItemURL: nil)'
assert methods.count(old) == 1
methods = methods.replace(old, 'try fakeTrash(mutation.snapshot.url)')
template = Path(sys.argv[2]).read_text()
Path(sys.argv[3]).write_text(template.replace('    // HANDLERS\n', methods))
PY
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/cache" -parse-as-library \
  "$ROOT"/Sources/{CardLibrary,CuratedIndex,NotePicker,Zettelkasten,NoteEditing,BranchIDs,IDModes,CardLinks,LinkNavigation,CardGraph,CardHistory,SidebarFileActions}.swift \
  "$TEMP_DIR/Checks.swift" -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
