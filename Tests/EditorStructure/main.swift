import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
let scroll = NSScrollView(frame: window.contentView!.bounds)
let view = LinkCompletionTextView(frame: NSRect(x: 0, y: 0, width: 450, height: 800))
view.isRichText = false; view.allowsUndo = true; view.font = .systemFont(ofSize: 14)
view.textContainer?.containerSize = NSSize(width: 450, height: 2000)
scroll.documentView = view; window.contentView = scroll; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
let undo = view.undoManager!; undo.groupsByEvent = false
func set(_ text: String) { view.setFrontmatterHidden(false); view.replaceEditorText(text); view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)) }
func pressEnter() { undo.beginUndoGrouping(); view.insertNewline(nil); undo.endUndoGrouping() }
func height() -> CGFloat { view.layoutManager!.ensureLayout(for: view.textContainer!); return view.layoutManager!.usedRect(for: view.textContainer!).height }

let header = "---\r\ncard_id: \"1a\"\r\ntags: reading\r\n---\r\n"
let original = header + "# An idea\r\n\r\nBody."
set(original)
let expectedRange = NSRange(location: 0, length: (header as NSString).length)
precondition(LinkCompletionTextView.frontmatterRange(in: original) == expectedRange)
precondition(LinkCompletionTextView.frontmatterRange(in: "---\nImportant evidence\n---\n# Title") == nil, "prose between horizontal rules must not be hidden")
precondition(LinkCompletionTextView.frontmatterRange(in: "---\ncard_id: 1a\n# unclosed") == nil, "unfinished metadata must stay visible")
let importedHeader = "---\r\n# imported comment\r\ncard_id: \"42a\"\r\ntags:\r\n  - research\r\n  - archive\r\n---\r\n"
let imported = importedHeader + "# Imported title\r\nBody."
precondition(LinkCompletionTextView.frontmatterRange(in: imported) == NSRange(location: 0, length: (importedHeader as NSString).length), "CRLF comments and nested YAML sequences must be recognized")
let unindented = "---\ntags:\n- research\n- archive\n---\n# Imported\n"
precondition(LinkCompletionTextView.frontmatterRange(in: unindented) != nil, "unindented YAML sequences must be recognized")
precondition(LinkCompletionTextView.frontmatterRange(in: "---\n# A real heading\nImportant evidence.\n---\n# Conclusion\n") == nil, "ordinary prose between rules must remain visible")
let ambiguousProse = "---\nClaim: Important evidence\n---\n# Conclusion\n"
let ambiguousInfo = LinkCompletionTextView.frontmatterInfo(in: ambiguousProse)
precondition(ambiguousInfo != nil && ambiguousInfo?.isCardify == false, "an ambiguous label can be hidden explicitly but must not auto-hide")
let customHeader = "---\nproject: research\n---\n"
let custom = customHeader + "# A project\n"
let customInfo = LinkCompletionTextView.frontmatterInfo(in: custom)
precondition(customInfo?.range == NSRange(location: 0, length: (customHeader as NSString).length) && customInfo?.isCardify == false, "custom YAML must offer explicit hide/reveal without auto-hiding")
let quotedCustom = "---\n'project name': research\n---\n# A project\n"
precondition(LinkCompletionTextView.frontmatterInfo(in: quotedCustom)?.isCardify == false, "quoted custom keys must be recognized without auto-hiding")
let unicodeCustom = "---\nprojeté: recherche\n---\n# A project\n"
precondition(LinkCompletionTextView.frontmatterInfo(in: unicodeCustom)?.isCardify == false, "Unicode custom keys must be recognized without auto-hiding")
precondition(LinkCompletionTextView.frontmatterInfo(in: original)?.isCardify == true, "Cardify IDs are recognized for automatic hiding")
set(custom)
let customSelection = view.selectedRange()
view.setFrontmatterHidden(true)
precondition(view.string == custom && view.selectedRange() == customSelection, "explicitly hiding custom metadata must preserve text and selection")
view.setFrontmatterHidden(false)
precondition(view.string == custom && view.selectedRange() == customSelection, "revealing custom metadata must preserve text and selection")
set(original)
precondition(LinkCompletionTextView.frontmatterRange(in: "---\ntags: research\n- A real bullet\n---\n") == nil, "a list after a scalar is not safely identifiable as metadata")
undo.beginUndoGrouping(); view.insertText("!", replacementRange: view.selectedRange()); undo.endUndoGrouping()
let edited = original + "!", selection = view.selectedRange(), visibleHeight = height()
precondition(undo.canUndo)
view.setFrontmatterHidden(true)
precondition(view.string == edited && view.selectedRange() == selection, "hiding must preserve exact CRLF text and selection")
precondition(undo.canUndo, "hiding must preserve existing undo history")
precondition(height() < visibleHeight - 20, "hidden metadata must not occupy its previous lines")
view.setSelectedRange(NSRange(location: 5, length: 0))
view.insertText("X", replacementRange: view.selectedRange())
precondition(view.string == edited, "hidden metadata must be protected from edits")
view.setSelectedRange(selection)
view.setFrontmatterHidden(false)
precondition(view.string == edited && view.selectedRange() == selection && undo.canUndo, "revealing must preserve text, selection and undo")
undo.undo()
precondition(view.string == original, "undo must work after hiding and revealing")
undo.redo()
precondition(view.string == edited, "redo must work after hiding and revealing")

// Normal body undo and redo must also work without revealing metadata.
set(original)
undo.beginUndoGrouping(); view.insertText("!", replacementRange: view.selectedRange()); undo.endUndoGrouping()
view.setFrontmatterHidden(true); undo.undo()
precondition(view.string == original, "body undo must work while metadata is hidden")
undo.redo(); precondition(view.string == original + "!", "body redo must work while metadata is hidden")
view.setFrontmatterHidden(false); precondition(view.string == original + "!")

// A prior metadata edit must remain undoable even when the metadata is hidden.
set(original)
let idLocation = (view.string as NSString).range(of: "1a").location
undo.beginUndoGrouping(); view.insertText("1b", replacementRange: NSRange(location: idLocation, length: 2)); undo.endUndoGrouping()
view.setFrontmatterHidden(true); undo.undo()
precondition(view.string == original, "undo must safely restore a previously visible metadata edit")
view.setSelectedRange(NSRange(location: idLocation, length: 0))
view.insertText("X", replacementRange: view.selectedRange())
precondition(view.string == original, "metadata must be hidden and protected again after undo")
undo.redo()
let revised = original.replacingOccurrences(of: "1a", with: "1b")
precondition(view.string == revised, "redo must restore the metadata edit while hidden")
view.setSelectedRange(NSRange(location: idLocation, length: 0))
view.insertText("X", replacementRange: view.selectedRange())
precondition(view.string == revised, "metadata must remain protected after redo")
view.setFrontmatterHidden(false)
precondition(view.string == revised)

func list(_ source: String, _ expected: String) {
    set(source); pressEnter()
    precondition(view.string == expected, "unexpected list result: \(view.string.debugDescription)")
    precondition(undo.canUndo, "list action must be undoable")
    undo.undo(); precondition(view.string == source, "undo must restore the original list")
    undo.redo(); precondition(view.string == expected, "redo must restore the continued list")
}
list("- First", "- First\n- ")
list("  * Nested", "  * Nested\n  * ")
list("- [x] Done", "- [x] Done\n- [ ] ")
list("\t+ [ ] Task", "\t+ [ ] Task\n\t+ [ ] ")
list("  - [ ] ", "")
list("- First\r\n- Second", "- First\r\n- Second\r\n- ")
precondition(LinkCompletionTextView.listNewline(in: "```\n- code", selection: NSRange(location: 10, length: 0)) == nil, "fenced code is not a list")
precondition(LinkCompletionTextView.listNewline(in: "- text", selection: NSRange(location: 0, length: 2)) == nil, "selected text uses normal Enter")

// Selection and focus transitions inside the metadata remain lossless.
set(original)
let metadataSelection = NSRange(location: idLocation, length: 2)
view.setSelectedRange(metadataSelection)
view.setFrontmatterHidden(true)
precondition(view.selectedRange() == metadataSelection && view.string == original)
window.makeFirstResponder(nil); window.makeFirstResponder(view)
precondition(view.selectedRange() == metadataSelection && view.string == original)
// Exercise text replacement over a metadata selection without touching the user's clipboard.
view.insertText("replacement", replacementRange: view.selectedRange())
precondition(view.string == original, "replacement of hidden metadata must be blocked")
view.setFrontmatterHidden(false)
precondition(view.string == original, "revealing after a blocked replacement must be lossless")
view.setSelectedRange(metadataSelection)
undo.beginUndoGrouping(); view.insertText("replacement", replacementRange: view.selectedRange()); undo.endUndoGrouping()
precondition(view.string.contains("replacement"), "replacement must work when metadata is visible")

// Replacing the document while metadata is hidden must restore attributes and
// hide only the new document's own header.
set(original); view.setFrontmatterHidden(true)
let replacement = "---\ncard_id: 2\n---\n# Different\n"
view.replaceEditorText(replacement)
precondition(view.string == replacement)
view.setSelectedRange(NSRange(location: 5, length: 0)); view.insertText("X", replacementRange: view.selectedRange())
precondition(view.string == replacement, "the replacement metadata must be protected")
view.setFrontmatterHidden(false)
precondition(view.string == replacement)

// Typing at the first visible position must not inherit the hidden tiny font.
set(header + "# Title")
view.setFrontmatterHidden(true)
view.setSelectedRange(NSRange(location: (header as NSString).length, length: 0))
undo.beginUndoGrouping(); view.insertText("X", replacementRange: view.selectedRange()); undo.endUndoGrouping()
let insertedFont = view.textStorage!.attribute(.font, at: (header as NSString).length, effectiveRange: nil) as? NSFont
precondition((insertedFont?.pointSize ?? 0) >= 10, "visible typing must not inherit the hidden font")
view.setFrontmatterHidden(false)
precondition(view.string == header + "X# Title")
print("Metadata conceal/reveal, CRLF, selection, undo, protection, and nested list continuation passed")
