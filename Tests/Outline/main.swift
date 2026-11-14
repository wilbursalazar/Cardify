import Foundation
import SwiftUI

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let fresh = OutlineDocument()
check(fresh.markdown == "<!-- cardify:outline -->\n\n# Outline\n\n- \n", "new outline uses ordinary Markdown")
check(OutlineDocument.fromMarkdown(fresh.markdown)?.markdown == fresh.markdown, "new outline round trip")
let original = "\u{FEFF}---\r\n# keep comment\r\ncard_id: \"1a\"\r\ntags: [memory, research]\r\n---\r\n\r\n<!-- cardify:outline -->\r\n\r\n# My outline\r\n\r\n- Parent\r\n  - Child [[Topic/Source|Alias]]\r\n    - Detail **bold**\r\n- Second\r\n"
guard var imported = OutlineDocument.fromMarkdown(original) else { fatalError("could not load CRLF outline") }
check(imported.markdown == original, "BOM, CRLF, comments and metadata round-trip exactly")
check(imported.rows.map(\.depth) == [0,1,2,0], "hierarchy parsed")
check(imported.rows[1].text == "Child [[Topic/Source|Alias]]", "wiki link preserved")
imported.rows[1].text = "Changed [[Topic/Source|Alias]]"
check(imported.markdown == original.replacingOccurrences(of: "Child [[Topic/Source|Alias]]", with: "Changed [[Topic/Source|Alias]]"), "editing a row keeps unrelated metadata")
let printed = imported.printMarkdown(cardID: "1a")
check(printed.contains("card_id: \"1a\""), "card ID available to printer")
check(!printed.contains("cardify:outline") && !printed.contains("tags:"), "marker and unrelated YAML omitted from print")
check(printed.contains("\u{2002}\u{2002}• Changed [[Topic/Source|Alias]]"), "print text preserves indentation and links")
check(!printed.contains("\r"), "CRLF source prints with LF line endings")
let crOnly = original.replacingOccurrences(of: "\r\n", with: "\r")
guard let crImported = OutlineDocument.fromMarkdown(crOnly) else { fatalError("could not load CR-only outline") }
check(crImported.markdown == crOnly, "CR-only source remains unchanged on disk")
let crPrinted = crImported.printMarkdown(cardID: "1a")
check(!crPrinted.contains("\r") && crPrinted.contains("# My outline\n\n• Parent\n"), "CR-only source prints as separate LF lines")

let unsupported = [
    "# unmarked note\n- item\n",
    fresh.markdown + "Additional paragraph\n",
    fresh.markdown + "\n",
    fresh.markdown.replacingOccurrences(of: "- ", with: "   - "),
    fresh.markdown.replacingOccurrences(of: "- ", with: "  - "),
    fresh.markdown.replacingOccurrences(of: "# Outline", with: "## Outline"),
    fresh.markdown.replacingOccurrences(of: "<!-- cardify:outline -->", with: "<!-- different -->"),
    "---\ncard_id: 1\n<!-- cardify:outline -->\n\n# Outline\n\n- item\n",
    fresh.markdown.replacingOccurrences(of: "# Outline\n", with: "# Outline\r\n"),
]
for text in unsupported { check(OutlineDocument.fromMarkdown(text) == nil, "unsupported note must stay in ordinary Markdown: \(text.debugDescription)") }
let noFinal = "<!-- cardify:outline -->\n\n# A\n\n- point"
check(OutlineDocument.fromMarkdown(noFinal)?.markdown == noFinal, "missing final newline preserved")
let empty = "<!-- cardify:outline -->\n\n# Empty\n\n"
check(OutlineDocument.fromMarkdown(empty)?.rows.isEmpty == true, "empty outline loads")

var outline = OutlineDocument()
outline.rows = [OutlineRow(text: "A", depth: 0), OutlineRow(text: "A1", depth: 1), OutlineRow(text: "A1a", depth: 2), OutlineRow(text: "A2", depth: 1), OutlineRow(text: "B", depth: 0), OutlineRow(text: "C", depth: 0)]
let a = outline.rows[0].id, a1 = outline.rows[1].id, a1a = outline.rows[2].id, a2 = outline.rows[3].id, b = outline.rows[4].id, c = outline.rows[5].id
check(!outline.indent(a), "first root cannot indent")
check(!outline.move(a, relativeTo: a1, after: false), "branch cannot move into itself")
check(outline.outdent(a1), "outdent child")
check(outline.rows.map(\.text) == ["A", "A2", "A1", "A1a", "B", "C"], "outdent keeps following siblings under their original parent")
check(outline.rows.map(\.depth) == [0,1,0,1,0,0], "outdent moves descendants with parent")
check(outline.indent(b), "indent after a prior branch")
check(outline.rows.map(\.depth) == [0,1,0,1,1,0], "indent preserves existing branches")
check(outline.move(a1, relativeTo: c, after: true), "move branch after last item")
check(outline.rows.map(\.text) == ["A", "A2", "C", "A1", "A1a", "B"], "move preserves subtree order")
check(outline.rows.map(\.depth) == [0,1,0,0,1,1], "move preserves subtree relative levels")
check(outline.appendLink("[[Sources/Memory]] — evidence", to: a2), "append a valid note link")
check(outline.rows.first(where: { $0.id == a2 })!.text.hasSuffix("[[Sources/Memory]] — evidence"), "link appended to requested row")
let beforeInvalid = outline
check(!outline.appendLink("[[bad]]\ninjection", to: a2) && !outline.appendLink("[[note]]", to: UUID()), "invalid and stale insertions rejected")
check(outline == beforeInvalid, "failed link insertion is non-destructive")
check(outline.descendantCount(a1) == 2, "descendant count")
check(outline.removeBranch(a1), "remove branch")
check(outline.rows.map(\.text) == ["A", "A2 [[Sources/Memory]] — evidence", "C"], "branch removal leaves unrelated points")
check(!outline.rows.contains(where: { $0.id == a1a }), "descendant removed with branch")

final class Box { var value = OutlineDocument() }
let box = Box(), manager = UndoManager(), history = OutlineUndoController()
manager.groupsByEvent = false
let binding = Binding<OutlineDocument>(get: { box.value }, set: { box.value = $0 })
let baseline = box.value
var edited = baseline; _ = edited.add(after: baseline.rows[0].id)
manager.beginUndoGrouping(); history.apply(edited, to: binding, manager: manager, name: "Add Point"); manager.endUndoGrouping()
check(box.value.rows.count == 2 && manager.canUndo, "structural change registers undo")
manager.undo(); check(box.value == baseline && manager.canRedo, "undo restores complete previous outline")
manager.redo(); check(box.value == edited, "redo restores branch")
box.value = OutlineDocument()
let unrelated = box.value
manager.undo(); check(box.value == unrelated, "stale undo cannot replace another outline")
print("Outline Markdown round-trip, safe import, hierarchy, links and structural undo passed")
