import AppKit
import SwiftUI

final class EditorState: ObservableObject {
    weak var view: NSTextView?
    func insert(_ content: String) {
        guard let view else { return }
        view.insertText(content, replacementRange: view.selectedRange())
        view.window?.makeFirstResponder(view)
    }
    func wrap(_ marker: String) {
        guard let view else { return }
        let range = view.selectedRange()
        let selected = (view.string as NSString).substring(with: range)
        view.insertText(marker + selected + marker, replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + (marker as NSString).length, length: range.length))
        view.window?.makeFirstResponder(view)
    }
    func prefix(_ prefix: String) {
        guard let view else { return }
        let selection = view.selectedRange()
        let location = (view.string as NSString).lineRange(for: NSRange(location: selection.location, length: 0)).location
        view.insertText(prefix, replacementRange: NSRange(location: location, length: 0))
        view.setSelectedRange(NSRange(location: selection.location + (prefix as NSString).length, length: selection.length))
        view.window?.makeFirstResponder(view)
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let editor: EditorState
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.delegate = context.coordinator
        view.string = text
        view.textContainerInset = NSSize(width: 10, height: 10)
        editor.view = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
        editor.view = view
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
