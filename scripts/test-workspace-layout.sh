#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cardify-workspace-layout.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/cache" -parse-as-library \
    "$ROOT/Sources/WorkspaceSplitView.swift" "$ROOT/Sources/AppearanceSettings.swift" "$ROOT/Tests/WorkspaceLayout/main.swift" -o "$TEMP_DIR/workspace-layout"
"$TEMP_DIR/workspace-layout"
