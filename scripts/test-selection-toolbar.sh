#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-selection.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
python3 - "$ROOT/Sources/MarkdownEditor.swift" "$ROOT/Tests/SelectionToolbar/main.swift" "$TEMP_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
editor = source[source.index('final class LinkCompletionTextView: NSTextView {'):source.index('// Kept in the editor')]
toolbar = source[source.index('private final class SelectionToolbarState:'):source.index('struct MarkdownEditor: View {')]
stubs = '''import AppKit
import SwiftUI
struct CardLinkTarget {}
struct CardLink { let target = CardLinkTarget() }
enum CardLinkParser { static func link(in: String, atUTF16: Int) -> CardLink? { nil } }
'''
Path(sys.argv[3]).write_text(stubs + editor + toolbar + Path(sys.argv[2]).read_text())
PY
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/cache" "$TEMP_DIR/main.swift" -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
