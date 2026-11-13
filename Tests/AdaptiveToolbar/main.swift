import AppKit
import SwiftUI

// The toolbar only needs these editor actions; no user document is loaded.
final class EditorState {
    func wrap(_ marker: String) {}
    func prefix(_ prefix: String) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
func toolbarSize(_ width: CGFloat) -> NSSize {
    let toolbar = AdaptiveFormattingToolbar(editor: EditorState(), onLinkNote: {}, onZotero: {})
    let host = NSHostingView(rootView: toolbar.frame(width: width, alignment: .leading))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 120)
    host.layoutSubtreeIfNeeded()
    return host.fittingSize
}
let narrow = toolbarSize(280)
let normal = toolbarSize(340)
let wide = toolbarSize(720)
precondition(abs(narrow.width - 280) < 1 && abs(normal.width - 340) < 1 && abs(wide.width - 720) < 1,
             "Toolbar must fit the available width")
precondition(normal.height > wide.height + 8, "Narrow toolbar must wrap to two rows")
precondition(abs(narrow.height - normal.height) < 2, "Typical narrow widths must stay at two rows")
precondition(normal.height < 75 && wide.height < 50, "Toolbar must leave room for the editor")
print("Adaptive toolbar fits narrow and wide widths and wraps to two rows")
