#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
SWIFT_FLAGS=(-target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache")
COMMON=("$ROOT/Sources/CardLibrary.swift" "$ROOT/Sources/CuratedIndex.swift" "$ROOT/Sources/NotePicker.swift" "$ROOT/Sources/Zettelkasten.swift" "$ROOT/Sources/NoteEditing.swift" "$ROOT/Sources/BranchIDs.swift" "$ROOT/Sources/IDModes.swift")
swiftc "${SWIFT_FLAGS[@]}" "${COMMON[@]}" "$ROOT/Tests/Library/main.swift" -o "$TEMP_DIR/library"
"$TEMP_DIR/library"
swiftc "${SWIFT_FLAGS[@]}" "${COMMON[@]}" "$ROOT/Sources/InlineTemplates.swift" "$ROOT/Sources/WorkflowSettings.swift" "$ROOT/Tests/Workflow/main.swift" -o "$TEMP_DIR/workflow"
"$TEMP_DIR/workflow"
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
second = source[source.index('    func loadFile('):source.index('    func chooseFolder()')]
template = Path(sys.argv[2]).read_text()
Path(sys.argv[3]).write_text(template.replace('    // DRAFT_METHODS\n', first + second))
PY
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library "$TEMP_DIR/DraftChecks.swift" -o "$TEMP_DIR/draft"
"$TEMP_DIR/draft"
