#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-debate.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache" \
    "$ROOT/Sources/DebateNotes.swift" "$ROOT/Tests/Debate/main.swift" -o "$TEMP_DIR/debate"
"$TEMP_DIR/debate"
