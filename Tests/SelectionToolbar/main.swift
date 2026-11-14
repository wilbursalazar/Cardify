let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
let view = LinkCompletionTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
view.isRichText = false; view.allowsUndo = true; view.font = .systemFont(ofSize: 14)
view.textContainer?.containerSize = NSSize(width: 400, height: 2000)
scroll.documentView = view; window.contentView!.addSubview(scroll)
window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
let header = "---\ncard_id: 1\n---\n"
view.string = header + "Selected note text"
view.setFrontmatterHidden(true)
let range = (view.string as NSString).range(of: "Selected note text")
view.setSelectedRange(range)
view.layoutManager!.ensureLayout(for: view.textContainer!)
private let state = SelectionToolbarState()
state.refresh(view, in: scroll)
precondition(state.anchor != nil, "selecting visible body text should show the toolbar")
private let host = NSHostingView(rootView: SelectionToolbarButton(title: "B", help: "Bold") { state.apply(.bold) })
host.frame = NSRect(x: 10, y: 260, width: 36, height: 28)
window.contentView!.addSubview(host)
host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
func findButton(_ item: NSView) -> NSButton? {
    if let button = item as? NSButton { return button }
    for child in item.subviews { if let button = findButton(child) { return button } }
    return nil
}
guard let button = findButton(host) else { fatalError("The hosted toolbar button was not created") }
precondition(!button.acceptsFirstResponder, "toolbar buttons must not steal the text selection")
precondition(window.firstResponder === view && view.selectedRange() == range)
button.performClick(nil)
precondition(view.string == header + "**Selected note text**", "hosted button must format the selected body")
precondition(window.firstResponder === view, "formatting must leave focus in the text view")
precondition(view.selectedRange().length == range.length)
state.dismiss()
precondition(state.anchor == nil)
state.refresh(view, in: scroll)
precondition(state.anchor == nil, "Escape dismissal must persist until the selection changes")
view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
state.refresh(view, in: scroll)
precondition(state.anchor == nil, "a caret alone must not show a toolbar")
print("Hosted selection toolbar preserves focus, formats text, and dismisses")
