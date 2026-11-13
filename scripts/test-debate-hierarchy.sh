#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-debate-hierarchy.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache" \
    "$ROOT/Sources/DebateNotes.swift" "$ROOT/Sources/DebateHierarchy.swift" "$ROOT/Tests/DebateHierarchy/main.swift" -o "$TEMP_DIR/debate-hierarchy"
"$TEMP_DIR/debate-hierarchy"
