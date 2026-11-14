import AppKit
import SwiftUI

@main struct SelectionToolbarIntegration {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        var draft = "# Card\n\nSelect this phrase for editing."
        let editor = EditorState()
        let host = NSHostingView(rootView: MarkdownEditor(text: Binding(get: { draft }, set: { draft = $0 }), editor: editor, onFollowLink: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 300, height: 250), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard let view = editor.view else { fatalError("Editor did not attach its text view") }
        window.makeFirstResponder(view)
        let selected = (view.string as NSString).range(of: "this phrase")
        view.setSelectedRange(selected)
        view.delegate?.textViewDidChangeSelection?(Notification(name: NSTextView.didChangeSelectionNotification, object: view))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        func findButton(_ item: NSView, tooltip: String) -> NSButton? {
            if let button = item as? NSButton, button.toolTip == tooltip { return button }
            for child in item.subviews { if let result = findButton(child, tooltip: tooltip) { return result } }
            return nil
        }
        guard let bold = findButton(host, tooltip: "Bold") else { fatalError("Selection toolbar did not appear in the full editor") }
        precondition(!bold.acceptsFirstResponder)
        let sample = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.maxY - 12), to: host.superview)
        let hit = host.hitTest(sample)
        precondition(hit === view || (hit?.isDescendant(of: view) == true), "toolbar overlay must not block normal clicks in the editor")
        bold.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(view.string.contains("**this phrase**") && window.firstResponder === view)
        print("Full editor shows selection toolbar and preserves text-view hit testing")
    }
}
