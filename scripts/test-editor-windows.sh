#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

python3 - "$ROOT/Sources/Cardify.swift" "$TEMP_DIR/EditorWindowCoordinator.swift" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('@MainActor final class EditorWindowCoordinator:')
end = source.index('\nprivate struct EditorWindowProbe:', start)
pathlib.Path(sys.argv[2]).write_text('import AppKit\nimport SwiftUI\n' + source[start:end] + '\n')

# The scene must gate the editor before construction and retain URL routing.
root = source[source.index('private struct EditorWindowRoot:'):]
assert 'if isEditor { ContentView() }' in root
assert 'EditorWindowProbe { isEditor = true }' in root
assert '.onOpenURL' in root and 'pendingURL = url' in root
assert 'CommandGroup(replacing: .newItem)' in root
probe = source[source.index('private struct EditorWindowProbe:'):source.index('private struct EditorWindowRoot:')]
assert 'self.window === window, coordinator.window === window' in probe
PY

swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$TEMP_DIR/module-cache" -parse-as-library \
    "$TEMP_DIR/EditorWindowCoordinator.swift" "$ROOT/Tests/EditorWindows/main.swift" -o "$TEMP_DIR/editor-windows"
"$TEMP_DIR/editor-windows"
