#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kaster-register.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/cache" "$ROOT/Sources/KeywordRegister.swift" "$ROOT/Tests/Register/main.swift" -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
