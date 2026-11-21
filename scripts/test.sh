#!/bin/bash
# Kaster's tests. The code is compiled once into two testable libraries:
#   KasterCore  Sources/Core only. This also proves the core never needs screen code.
#   KasterApp   Sources/Core + Sources/App (everything except Sources/Main.swift), for tests
#               that drive real views, editors and windows.
# Each Tests/<Name>/ folder is compiled against one of them (named on its first line,
# `@testable import KasterCore` or `@testable import KasterApp`) and run.
#
#   scripts/test.sh                 every test
#   scripts/test.sh Vault Zotero    only those
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kaster-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FLAGS=(-target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/cache")

library() {   # library <name> <optimize?> <sources...>: compile once per run, on first use
    local name=$1 optimize=$2; shift 2
    [ -f "$WORK/lib/$name/lib$name.a" ] && return 0
    [ -f "$WORK/lib/$name/failed" ] && return 1
    mkdir -p "$WORK/lib/$name"
    local module=${name%Fast}
    local extra=(); [ "$optimize" = yes ] && extra=(-O)
    echo "▸ building $name"
    swiftc "${FLAGS[@]}" ${extra[@]+"${extra[@]}"} -parse-as-library -enable-testing -module-name "$module" \
        -emit-module -emit-module-path "$WORK/lib/$name/$module.swiftmodule" \
        -emit-library -static -o "$WORK/lib/$name/lib$name.a" "$@" || { touch "$WORK/lib/$name/failed"; return 1; }
}
core() { library KasterCore no "$ROOT"/Sources/Core/*.swift; }
app() { library KasterApp no "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/App/*.swift; }

failed=()
run() {   # run <name> [sources...]: defaults to every .swift file in Tests/<name>
    local name=$1; shift
    local sources=(); [ $# -gt 0 ] && sources=("$@"); [ ${#sources[@]} -eq 0 ] && sources=("$ROOT/Tests/$name"/*.swift)
    local lib; lib=$(grep -ho -m1 '@testable import Kaster[A-Za-z]*' "${sources[@]}" | head -1 | awk '{print $3}')
    local dir=KasterCore
    case "$name:$lib" in
        Performance:KasterCore) library KasterCoreFast yes "$ROOT"/Sources/Core/*.swift || { failed+=("$name"); return; }; dir=KasterCoreFast ;;
        *:KasterApp) app || { failed+=("$name"); return; }; dir=KasterApp ;;
        *) core || { failed+=("$name"); return; } ;;
    esac
    local parse=(); grep -q '@main' "${sources[@]}" && parse=(-parse-as-library)
    local optimize=(); [ "$name" = Performance ] && optimize=(-O)
    echo "▸ $name"
    if swiftc "${FLAGS[@]}" ${optimize[@]+"${optimize[@]}"} ${parse[@]+"${parse[@]}"} -I "$WORK/lib/$dir" -L "$WORK/lib/$dir" -l"$dir" \
        "${sources[@]}" -o "$WORK/$name" && (cd "$ROOT" && "$WORK/$name"); then :; else failed+=("$name"); fi
}

# Tests that still copy ContentView methods out of Cardify.swift (until those move into services).
extracted() {   # extracted <name> <template> <python that prints the methods>
    local name=$1 template=$2 script=$3
    mkdir -p "$WORK/gen/$name"
    python3 - "$ROOT/Sources/App/Cardify.swift" "$template" "$WORK/gen/$name/main.swift" <<<"$script" || { failed+=("$name"); return; }
    run "$name" "$WORK/gen/$name/main.swift"
}

wanted() { [ $# -eq 0 ] && return 0; local n; for n in "${SELECTED[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }
SELECTED=(); [ $# -gt 0 ] && SELECTED=("$@")
want() { [ ${#SELECTED[@]} -eq 0 ] || wanted "$1" "${SELECTED[@]}"; }

for dir in "$ROOT"/Tests/*/; do
    name=$(basename "$dir")
    case $name in Autosave|SidebarHandlers|IDModeSelection|Draft) continue ;; esac
    want "$name" && run "$name"
done

want Autosave && extracted Autosave "$ROOT/Tests/Autosave/SaveChecks.swift.in" '
from pathlib import Path; import sys
s = Path(sys.argv[1]).read_text()
m = s[s.index("    func saveMarkdown(saveAs:"):s.index("    func scheduleAutosave()")]
Path(sys.argv[3]).write_text(Path(sys.argv[2]).read_text().replace("    // SAVE_METHODS\n", m))'
want SidebarHandlers && extracted SidebarHandlers "$ROOT/Tests/SidebarHandlers/Checks.swift.in" '
from pathlib import Path; import sys
s = Path(sys.argv[1]).read_text()
a = s[s.index("    private var sidebarRoot:"):s.index("    private func revealSidebarNote(")]
b = s[s.index("    private func duplicateSidebarNote("):s.index("\n}\n\n// WindowGroup")]
m = (a + b).replace("    private ", "    ")
old = "try FileManager.default.trashItem(at: mutation.snapshot.url, resultingItemURL: nil)"
assert m.count(old) == 1
m = m.replace(old, "try fakeTrash(mutation.snapshot.url)")
Path(sys.argv[3]).write_text(Path(sys.argv[2]).read_text().replace("    // HANDLERS\n", m))'
want IDModeSelection && extracted IDModeSelection "$ROOT/Tests/IDModeSelection/Checks.swift.in" '
from pathlib import Path; import sys
s = Path(sys.argv[1]).read_text()
m = s[s.index("    func scanRoots("):s.index("    func insertTemplate(")]
Path(sys.argv[3]).write_text(Path(sys.argv[2]).read_text().replace("    // METHODS\n", m))'
want Draft && extracted Draft "$ROOT/Tests/Draft/DraftChecks.swift.in" '
from pathlib import Path; import sys
s = Path(sys.argv[1]).read_text()
first = s[s.index("    func confirmReplaceDraft("):s.index("    func openFile()")]
i = s.index("    func switchMode(to mode: String)")
switch = s[i:s.index("    var body: some View", i)]
nav = s[s.index("    func navigateHistory("):s.index("    @discardableResult\n    func loadFile(")]
second = s[s.index("    func loadFile("):s.index("    func chooseFolder()")]
Path(sys.argv[3]).write_text(Path(sys.argv[2]).read_text().replace("    // DRAFT_METHODS\n", switch + first + nav + second))'

if [ ${#failed[@]} -gt 0 ]; then echo; echo "✗ Failed: ${failed[*]}"; exit 1; fi
echo; echo "✓ All tests passed"
