@testable import KasterApp
import AppKit

@main struct Checks {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let view = LinkCompletionTextView(frame: window.contentView!.bounds)
        view.isRichText = false
        view.allowsUndo = true
        window.contentView!.addSubview(view)
        window.makeFirstResponder(view)
        let manager = view.undoManager!
        manager.groupsByEvent = false
        let lim = ZoteroSource(key: "D9QP9N8Q", cite: "Lim, *How Was the Canon Formed?*")
        let card = "# Canon\n\nClaim.[^1] More.[^2]\n\n[^1]: " + ZoteroFootnote.citation(lim, page: nil) + "\n[^2]: Tov, Emanuel. \u{201C}The Septuagint.\u{201D}\n"
        view.string = card
        let editor = EditorState()
        editor.view = view

        // A page typed in a chip: one edit, the cursor (in the heading) doesn't move, ⌘Z restores.
        view.setSelectedRange(NSRange(location: 4, length: 2))
        let edit = FootnoteSources.settingPage("42", label: "1", in: view.string)!
        precondition(!editor.replace([edit], expected: "stale text"), "A stale card is never edited")
        precondition(editor.replace([edit], expected: card))
        precondition(view.string.contains("[^1]: [Lim, *How Was the Canon Formed?*](zotero://select/library/items/D9QP9N8Q), 42.\n"), view.string)
        precondition(view.selectedRange() == NSRange(location: 4, length: 2), "Cursor stays: \(view.selectedRange())")
        precondition(manager.canUndo)
        manager.undo()
        precondition(view.string == card, "One undo restores the footnote")

        // Removing a footnote edits several places; a cursor after them shifts back with the text.
        let tail = (card as NSString).range(of: "More.").location
        view.setSelectedRange(NSRange(location: tail, length: 0))
        precondition(editor.replace(FootnoteSources.removing(label: "1", in: card), expected: card))
        precondition(!view.string.contains("[^1]") && view.string.contains("[^2]: Tov"), view.string)
        precondition(view.selectedRange().location == (view.string as NSString).range(of: "More.").location, "Cursor follows the text: \(view.selectedRange())")
        manager.undo()
        precondition(view.string == card, "One undo restores the marker and the definition: \(view.string.debugDescription)")

        // Going to a footnote selects its text.
        let source = FootnoteSources.parse(card)[1]
        editor.reveal(source.range)
        precondition((view.string as NSString).substring(with: view.selectedRange()) == "Tov, Emanuel. \u{201C}The Septuagint.\u{201D}")

        // Converting an older card replaces the whole text as one undoable edit.
        let legacy = "---\nzotero: K\nzotero-cite: \"Doe, *Book*\"\n---\n# Old\n\n> Quote\n\nSource: Doe, *Book*, 7.\n"
        view.string = legacy
        manager.removeAllActions()
        let converted = FootnoteSources.convertingLegacy(legacy)!
        precondition(editor.replace([(NSRange(location: 0, length: (legacy as NSString).length), converted.text)], expected: legacy))
        precondition(view.string == "# Old\n\n> Quote[^1]\n\n[^1]: [Doe, *Book*](zotero://select/library/items/K), 7.\n", view.string.debugDescription)
        manager.undo()
        precondition(view.string == legacy)
        print("Footnote edits: chip pages, removal, reveal and conversion are single undoable edits passed")
    }
}
