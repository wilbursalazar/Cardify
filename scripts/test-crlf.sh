#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cardify-crlf.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$test_dir/cache" \
  Sources/{CardLibrary,CuratedIndex,NotePicker,Zettelkasten,NoteEditing,BranchIDs,IDModes,InlineTemplates}.swift \
  Tests/CRLF/main.swift -o "$test_dir/check"
"$test_dir/check"
