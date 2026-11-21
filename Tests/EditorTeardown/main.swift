@testable import KasterApp
import AppKit
import SwiftUI

// Closing a window while text is selected (the selection toolbar showing) must not crash.
// Kaster aborted three times on Nov 20: the editor's teardown changed published toolbar state
// while SwiftUI was dismantling the window.
@main struct EditorTeardown {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        for round in 0..<3 {
            var draft = "# Card \(round)\n\nSelect this phrase for editing."
            let editor = EditorState()
            autoreleasepool {
                let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 320, height: 260), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: MarkdownEditor(text: Binding(get: { draft }, set: { draft = $0 }), editor: editor, onFollowLink: { _ in }))
                window.makeKeyAndOrderFront(nil)
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                guard let view = editor.view else { fatalError("Editor did not attach its text view") }
                window.makeFirstResponder(view)
                view.setSelectedRange((view.string as NSString).range(of: "this phrase"))
                view.delegate?.textViewDidChangeSelection?(Notification(name: NSTextView.didChangeSelectionNotification, object: view))
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                // Close the window: SwiftUI dismantles the editor.
                window.close()
                window.contentView = nil
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            precondition(editor.view == nil, "The closed editor lets go of its text view")
        }
        print("Editor teardown: closing a window with the selection toolbar showing passed")
    }
}
