import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
let container = NSView(frame: window.contentView!.bounds)
window.contentView = container
window.makeKeyAndOrderFront(nil)
func addView() -> LinkCompletionTextView {
    let view = LinkCompletionTextView(frame: container.bounds)
    view.isRichText = false
    view.allowsUndo = true
    container.addSubview(view)
    window.makeFirstResponder(view)
    view.undoManager!.groupsByEvent = false
    return view
}
var view: LinkCompletionTextView? = addView()
let manager = view!.undoManager!
let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
precondition(!view!.validateMenuItem(undoItem) && !view!.validateMenuItem(redoItem), "Empty history must disable menu undo and redo")
precondition(!view!.validateUserInterfaceItem(undoItem) && !view!.validateUserInterfaceItem(redoItem), "Empty history must disable validated undo and redo")
precondition(window.firstResponder?.undoManager === manager, "Menu responder must use the text view's undo manager")
manager.beginUndoGrouping()
view!.insertText("First", replacementRange: NSRange(location: 0, length: 0))
manager.endUndoGrouping()
precondition(manager.canUndo && view!.string == "First")
precondition(view!.validateMenuItem(undoItem) && !view!.validateMenuItem(redoItem), "Undo menu must be available after typing")
precondition(view!.validateUserInterfaceItem(undoItem) && !view!.validateUserInterfaceItem(redoItem), "Undo must be available after typing")
precondition(view!.responds(to: Selector(("undo:"))), "Focused editor must accept the undo action")
precondition(view!.tryToPerform(Selector(("undo:")), with: nil), "Undo must route through the first responder")
precondition(view!.string == "" && manager.canRedo, "Undo must restore the text")
precondition(!view!.validateMenuItem(undoItem) && view!.validateMenuItem(redoItem), "Redo menu must be available after undo")
precondition(!view!.validateUserInterfaceItem(undoItem) && view!.validateUserInterfaceItem(redoItem), "Redo must be available after undo")
precondition(view!.responds(to: Selector(("redo:"))), "Focused editor must accept the redo action")
precondition(view!.tryToPerform(Selector(("redo:")), with: nil), "Redo must route through the first responder")
precondition(view!.string == "First", "Redo must restore the text")
view!.replaceEditorText("Other draft")
precondition(!manager.canUndo && !manager.canRedo, "External text replacement must discard stale undo actions")
precondition(!view!.validateUserInterfaceItem(undoItem) && !view!.validateUserInterfaceItem(redoItem))
precondition(view!.string == "Other draft")
precondition(view!.tryToPerform(Selector(("undo:")), with: nil))
precondition(view!.string == "Other draft", "An empty undo stack must leave the replacement untouched")
manager.beginUndoGrouping()
view!.insertText("!", replacementRange: NSRange(location: (view!.string as NSString).length, length: 0))
manager.endUndoGrouping()
precondition(manager.canUndo)
view!.discardEditorUndo()
precondition(!manager.canUndo && !manager.canRedo, "Teardown must discard text actions")
view!.removeFromSuperview()
window.makeFirstResponder(nil)
view = nil
let next = addView()
next.replaceEditorText("Next draft")
precondition(next.undoManager !== manager && !next.undoManager!.canUndo, "New text view must not inherit old text undo")
precondition(window.firstResponder?.undoManager === next.undoManager)
print("Editor undo, redo, responder routing, external replacement, and teardown passed")
