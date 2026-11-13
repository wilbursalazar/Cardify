#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-editor-undo.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
python3 - "$ROOT/Sources/MarkdownEditor.swift" "$TEMP_DIR/EditorView.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('final class LinkCompletionTextView: NSTextView {')
end = source.index('// Kept in the editor', start)
stubs = '''import AppKit
struct CardLinkTarget {}
struct CardLink { let target = CardLinkTarget() }
enum CardLinkParser { static func link(in: String, atUTF16: Int) -> CardLink? { nil } }
'''
Path(sys.argv[2]).write_text(stubs + source[start:end])
PY
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache" \
    "$TEMP_DIR/EditorView.swift" "$ROOT/Tests/EditorUndo/main.swift" -o "$TEMP_DIR/editor-undo"
"$TEMP_DIR/editor-undo"
