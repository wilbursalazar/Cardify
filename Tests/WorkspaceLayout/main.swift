import SwiftUI
import AppKit

final class ProbeCounter {
    var creations = 0
    weak var view: NSView?
}
final class ProbeTextView: NSTextView {
    private let editorUndoManager = UndoManager()
    override var undoManager: UndoManager? { editorUndoManager }
}
struct Probe: NSViewRepresentable {
    let counter: ProbeCounter
    var writing = false
    func makeNSView(context: Context) -> NSView {
        let view: NSView = writing ? ProbeTextView() : NSView()
        if let text = view as? NSTextView { text.allowsUndo = true; text.isRichText = false }
        counter.creations += 1
        counter.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
final class Model: ObservableObject {
    @Published var arrangement: WorkspaceArrangement = .editorLeft
    @Published var showSidebar = true
}
struct TestView: View {
    @ObservedObject var model: Model
    let editor: ProbeCounter
    let preview: ProbeCounter
    var body: some View {
        HStack(spacing: 0) {
            if model.showSidebar { Text("Notes").frame(width: 100) }
            WorkspaceSplitView(arrangement: model.arrangement) {
                Probe(counter: editor, writing: true)
            } preview: {
                Probe(counter: preview)
            }
        }
    }
}

@main struct Checks {
    static func main() {
        precondition(WorkspaceArrangement.stored("invalid") == .editorLeft)
        for mode in WorkspaceArrangement.allCases {
            precondition(WorkspaceArrangement.stored(mode.rawValue) == mode)
            for size in [CGSize(width: 600, height: 480), CGSize(width: 180, height: 120), CGSize.zero] {
                for fraction in [CGFloat(-5), 0, 0.5, 1, 5, .nan] {
                    let geometry = WorkspacePaneGeometry.calculate(size: size, arrangement: mode, fraction: fraction)
                    let bounds = CGRect(origin: .zero, size: size)
                    for rect in [geometry.editor, geometry.divider, geometry.preview] {
                        precondition(rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= bounds.maxX + 0.001 && rect.maxY <= bounds.maxY + 0.001)
                    }
                    if !geometry.editor.isEmpty && !geometry.preview.isEmpty { precondition(!geometry.editor.intersects(geometry.preview), "panes must not overlap") }
                    if mode == .editorAbove { precondition(geometry.editor.maxY <= geometry.preview.minY) }
                    else if mode == .previewLeft { precondition(geometry.preview.maxX <= geometry.editor.minX) }
                    else { precondition(geometry.editor.maxX <= geometry.preview.minX) }
                }
            }
        }
        let left = WorkspacePaneGeometry.calculate(size: CGSize(width: 600, height: 480), arrangement: .editorLeft, fraction: 0.5)
        precondition(left.editor.width >= 280 && left.preview.width >= 230, "sidebar-sized workspace must remain usable")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        let editor = ProbeCounter(), preview = ProbeCounter(), model = Model()
        let hosting = NSHostingView(rootView: TestView(model: model, editor: editor, preview: preview))
        hosting.frame = CGRect(x: 0, y: 0, width: 600, height: 480)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        hosting.layoutSubtreeIfNeeded()
        guard let oldEditor = editor.view as? ProbeTextView, let oldPreview = preview.view else { fatalError("Hosted panes were not created") }
        oldEditor.string = "A"
        guard let manager = oldEditor.undoManager else { fatalError("Editor undo manager missing") }
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        oldEditor.insertText("B", replacementRange: NSRange(location: 1, length: 0))
        manager.endUndoGrouping()
        oldEditor.setSelectedRange(NSRange(location: 1, length: 0))
        precondition(window.makeFirstResponder(oldEditor), "editor must accept focus")
        precondition(manager.canUndo && oldEditor.string == "AB")
        for mode in [WorkspaceArrangement.previewLeft, .editorAbove, .editorLeft] {
            model.arrangement = mode
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            hosting.layoutSubtreeIfNeeded()
            precondition(editor.view === oldEditor && preview.view === oldPreview && editor.creations == 1 && preview.creations == 1, "switching layouts must preserve both native views")
            precondition(window.firstResponder === oldEditor && oldEditor.selectedRange() == NSRange(location: 1, length: 0) && manager.canUndo, "switching layouts must preserve editor focus, selection, and undo")
        }
        for visible in [false, true, false, true] {
            model.showSidebar = visible
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            hosting.layoutSubtreeIfNeeded()
            precondition(editor.view === oldEditor && preview.view === oldPreview && editor.creations == 1 && preview.creations == 1,
                         "showing or hiding the sidebar must preserve both native views")
            precondition(window.firstResponder === oldEditor && oldEditor.selectedRange() == NSRange(location: 1, length: 0) && manager.canUndo,
                         "showing or hiding the sidebar must preserve focus, selection, and undo")
        }
        manager.undo()
        precondition(oldEditor.string == "A", "undo must remain functional after layout changes and sidebar toggles")
        print("Workspace arrangements, narrow sizing, and native view identity passed")
    }
}
