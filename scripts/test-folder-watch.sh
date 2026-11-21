#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kaster-watch.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT"/Sources/{KasterLibrary,SidebarFolders,KasterTypesetter,KasterVault,Zettelkasten,BranchIDs,IDModes,NoteEditing,CuratedIndex,HabitTracker,TodoList,DebateNotes,CardLibrary,NotePicker,DebateIDs,CardLinks,LinkNavigation,MarkdownRendering,PDFLinkSupport}.swift \
  "$ROOT/Tests/FolderWatch/main.swift" -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
