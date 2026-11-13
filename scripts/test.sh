#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
SWIFT_FLAGS=(-target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache")
COMMON=("$ROOT/Sources/CardLibrary.swift" "$ROOT/Sources/CuratedIndex.swift" "$ROOT/Sources/NotePicker.swift" "$ROOT/Sources/Zettelkasten.swift" "$ROOT/Sources/NoteEditing.swift" "$ROOT/Sources/BranchIDs.swift" "$ROOT/Sources/IDModes.swift")
swiftc "${SWIFT_FLAGS[@]}" "${COMMON[@]}" "$ROOT/Tests/Library/main.swift" -o "$TEMP_DIR/library"
"$TEMP_DIR/library"
swiftc "${SWIFT_FLAGS[@]}" "${COMMON[@]}" "$ROOT/Sources/InlineTemplates.swift" "$ROOT/Sources/AppearanceSettings.swift" "$ROOT/Sources/WorkflowSettings.swift" "$ROOT/Tests/Workflow/main.swift" -o "$TEMP_DIR/workflow"
"$TEMP_DIR/workflow"
swiftc "${SWIFT_FLAGS[@]}" "$ROOT/Tests/CRLFEditor/main.swift" -o "$TEMP_DIR/crlf-editor"
"$ROOT/scripts/test-crlf.sh"
"$ROOT/scripts/test-editor-undo.sh"
"$ROOT/scripts/test-debate.sh"
"$ROOT/scripts/test-debate-templates.sh"
"$ROOT/scripts/test-debate-ids.sh"
"$ROOT/scripts/test-debate-hierarchy.sh"
"$TEMP_DIR/crlf-editor"
swiftc "${SWIFT_FLAGS[@]}" "$ROOT/Sources/CardHistory.swift" "$ROOT/Tests/History/main.swift" -o "$TEMP_DIR/history"
"$TEMP_DIR/history"
swiftc "${SWIFT_FLAGS[@]}" "$ROOT/Sources/TodoList.swift" "$ROOT/Tests/TodoList/main.swift" -o "$TEMP_DIR/todo"
"$TEMP_DIR/todo"
swiftc "${SWIFT_FLAGS[@]}" "$ROOT/Sources/AppearanceSettings.swift" "$ROOT/Tests/Appearance/main.swift" -o "$TEMP_DIR/appearance"
"$TEMP_DIR/appearance"
swiftc "${SWIFT_FLAGS[@]}" "$ROOT/Sources/GraphMotion.swift" "$ROOT/Tests/GraphMotion/main.swift" -o "$TEMP_DIR/graph-motion"
"$TEMP_DIR/graph-motion"
swiftc "${SWIFT_FLAGS[@]}" "${COMMON[@]}" "$ROOT/Sources/CardLinks.swift" "$ROOT/Sources/LinkNavigation.swift" "$ROOT/Sources/CardGraph.swift" "$ROOT/Tests/Graph/main.swift" -o "$TEMP_DIR/graph"
"$TEMP_DIR/graph"
swiftc "${SWIFT_FLAGS[@]}" "$ROOT/Sources/LinkNavigation.swift" "$ROOT/Sources/CardLinks.swift" "$ROOT/Tests/LinkParser/main.swift" -o "$TEMP_DIR/link-parser"
"$TEMP_DIR/link-parser"
swiftc "${SWIFT_FLAGS[@]}" "$ROOT/Sources/LinkNavigation.swift" "$ROOT/Tests/LinkNavigation/main.swift" -o "$TEMP_DIR/link-navigation"
"$TEMP_DIR/link-navigation"
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library "$ROOT/Sources/CuratedIndex.swift" "$ROOT/Tests/IndexMetadata/IndexChecks.swift" -o "$TEMP_DIR/index"
"$TEMP_DIR/index"
python3 - "$ROOT/Sources/Cardify.swift" "$ROOT/Tests/Draft/DraftChecks.swift.in" "$TEMP_DIR/DraftChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
first = source[source.index('    func confirmReplaceDraft('):source.index('    func openFile()')]
switch_start = source.index('    func switchMode(to mode: String)')
switch = source[switch_start:source.index('    var body: some View', switch_start)]
navigation = source[source.index('    func navigateHistory('):source.index('    @discardableResult\n    func loadFile(')]
second = source[source.index('    func loadFile('):source.index('    func chooseFolder()')]
template = Path(sys.argv[2]).read_text()
Path(sys.argv[3]).write_text(template.replace('    // DRAFT_METHODS\n', switch + first + navigation + second))
PY
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library "$ROOT/Sources/CardHistory.swift" "$ROOT/Sources/TodoList.swift" "$TEMP_DIR/DraftChecks.swift" -o "$TEMP_DIR/draft"
"$TEMP_DIR/draft"
