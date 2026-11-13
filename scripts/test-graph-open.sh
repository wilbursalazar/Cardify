#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-graph-open.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
cp -R "$ROOT/Sources" "$TEMP_DIR/Sources"
python3 - "$TEMP_DIR/Sources/Cardify.swift" "$ROOT/Tests/GraphOpen/GraphOpen.swift.in" "$TEMP_DIR/GraphOpen.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
graph = source[source.index('    func showGraph()'):source.index('    func followLink(')]
# ContentView is a value type, but the test harness is a reference type. Capture
# it explicitly so Swift permits the same implicit member accesses in the mock.
graph = graph.replace('[weak editorWindow] url in', '[weak editorWindow, self] url in')
first = source[source.index('    func confirmReplaceDraft('):source.index('    func openFile()')]
second = source[source.index('    func loadFile('):source.index('    func chooseFolder()')]
template = Path(sys.argv[2]).read_text()
Path(sys.argv[3]).write_text(template.replace('    // GRAPH_AND_DRAFT_METHODS\n', graph + first + second))
PY
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache" -parse-as-library \
    "$TEMP_DIR"/Sources/{CardGraph,CardLibrary,CardLinks,LinkNavigation,NotePicker,Zettelkasten,NoteEditing,BranchIDs,IDModes,CuratedIndex,CardHistory,TodoList}.swift \
    "$TEMP_DIR/GraphOpen.swift" -o "$TEMP_DIR/graph-open-check"
"$TEMP_DIR/graph-open-check"
