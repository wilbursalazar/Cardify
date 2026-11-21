#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kaster-vault.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -parse-as-library -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT"/Sources/{KasterTypesetter,KasterVault,Zettelkasten,BranchIDs,IDModes,NoteEditing,CuratedIndex,HabitTracker,TodoList,DebateNotes,CardLibrary,NotePicker,DebateIDs,CardLinks,LinkNavigation,MarkdownRendering,PDFLinkSupport}.swift \
  "$ROOT/Tests/Vault/main.swift" -o "$TEMP_DIR/check" 2>&1 | grep -E "error" -A3 || true
"$TEMP_DIR/check"
