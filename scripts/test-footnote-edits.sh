#!/bin/bash
# Source-chip edits go through the editor: one undo step each, and the cursor stays put.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kaster-footnote-edits.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
python3 - "$ROOT/Sources/MarkdownEditor.swift" "$TEMP_DIR/EditorView.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('final class EditorState: ObservableObject {')
end = source.index('// Kept in the editor', start)
Path(sys.argv[2]).write_text('import AppKit\nimport SwiftUI\n' + source[start:end])
PY
swiftc -target "$(uname -m)-apple-macos13.0" -parse-as-library -module-cache-path "$TEMP_DIR/cache" \
  "$TEMP_DIR/EditorView.swift" \
  "$ROOT"/Sources/{FootnoteSources,ZoteroSearch,KasterVault,Zettelkasten,BranchIDs,IDModes,NoteEditing,CuratedIndex,HabitTracker,TodoList,DebateNotes,CardLibrary,NotePicker,DebateIDs,CardLinks,LinkNavigation,MarkdownRendering,PDFLinkSupport}.swift \
  "$ROOT/Tests/FootnoteEdits/main.swift" -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
