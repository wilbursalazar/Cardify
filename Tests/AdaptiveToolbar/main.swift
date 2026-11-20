import AppKit
import SwiftUI

enum EditorPresentationMode: String, CaseIterable {
    case visual, live, source
    var label: String { rawValue.capitalized }
    var description: String { rawValue }
}

// Minimal standalone editor stub for the toolbar layout regression.
final class EditorState {
    func wrap(_ marker: String) {}
    func prefix(_ prefix: String) {}
    func insert(_ content: String) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func toolbarSize(_ width: CGFloat) -> NSSize {
    let toolbar = AdaptiveFormattingToolbar(editor: EditorState(),
                                            presentation: .constant(.visual),
                                            onLinkNote: {}, onZotero: {}, onInsertImage: {})
    let host = NSHostingView(rootView: toolbar.frame(width: width, alignment: .leading))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 120)
    host.layoutSubtreeIfNeeded()
    return host.fittingSize
}
let narrow = toolbarSize(280)
let normal = toolbarSize(340)
let wide = toolbarSize(950)
precondition(abs(narrow.width - 280) < 1 && abs(normal.width - 340) < 1 && abs(wide.width - 950) < 1,
             "Toolbar must fit the available width")
precondition(normal.height > wide.height + 8, "Toolbar should wrap when constrained")
precondition(abs(narrow.height - normal.height) < 5, "Typical narrow widths should use the same wrapped layout")
precondition(normal.height < 90 && wide.height < 55, "Toolbar must leave room for the editor")
print("Kaster toolbar fits narrow and wide widths, with visible editor modes")
