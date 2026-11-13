#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-debate-templates.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache" \
    "$ROOT/Sources/CardLibrary.swift" "$ROOT/Sources/CuratedIndex.swift" "$ROOT/Sources/NotePicker.swift" \
    "$ROOT/Sources/Zettelkasten.swift" "$ROOT/Sources/NoteEditing.swift" "$ROOT/Sources/BranchIDs.swift" \
    "$ROOT/Sources/IDModes.swift" "$ROOT/Sources/DebateNotes.swift" "$ROOT/Sources/DebateTemplates.swift" \
    "$ROOT/Tests/DebateTemplates/main.swift" -o "$TEMP_DIR/debate-templates"
"$TEMP_DIR/debate-templates"
