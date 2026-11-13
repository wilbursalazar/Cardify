import AppKit
import SwiftUI

// NSTextView uses UTF-16 locations. This also keeps ordinary Markdown editable:
// a suggestion is inserted only after the user explicitly selects it.
struct LinkCompletionContext: Equatable {
    let range: NSRange
    let query: String
    static func find(in text: String, caret: Int) -> LinkCompletionContext? {
        let source = text as NSString
        guard caret > 0 && caret <= source.length else { return nil }
        let line = source.lineRange(for: NSRange(location: max(0, caret - 1), length: 0))
        let before = source.substring(with: NSRange(location: line.location, length: caret - line.location)) as NSString
        let last = before.range(of: "[", options: .backwards)
        guard last.location != NSNotFound else { return nil }
        var start = line.location + last.location
        // A single '[' remains ordinary Markdown; autocomplete starts at '[['.
        guard start > line.location && source.substring(with: NSRange(location: start - 1, length: 1)) == "[" else { return nil }
        start -= 1
        if start > line.location {
            let prior = source.substring(with: NSRange(location: start - 1, length: 1))
            if prior == "[" || prior == "!" { return nil }
            var count = 0, i = start
            while i > line.location && source.substring(with: NSRange(location: i - 1, length: 1)) == "\\" { count += 1; i -= 1 }
            if count % 2 == 1 { return nil }
        }
        let openLength = source.substring(with: NSRange(location: start, length: min(2, caret - start))) == "[[" ? 2 : 1
        let queryStart = start + openLength
        guard queryStart <= caret else { return nil }
        let query = source.substring(with: NSRange(location: queryStart, length: caret - queryStart))
        if query.contains(where: { "[]\n\r".contains($0) }) { return nil }
        let prefix = source.substring(with: NSRange(location: line.location, length: start - line.location))
        if prefix.filter({ $0 == "`" }).count % 2 == 1 { return nil }
        var fence: String?
        for earlierLine in source.substring(to: line.location).components(separatedBy: "\n") {
            let trimmed = earlierLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
            }
        }
        if fence != nil { return nil }
        var end = caret
        // Consume an editor's auto-paired closing delimiter, but no other text.
        let maxClosers = openLength == 2 ? 2 : 1
        while end < source.length && end - caret < maxClosers && source.substring(with: NSRange(location: end, length: 1)) == "]" { end += 1 }
        return LinkCompletionContext(range: NSRange(location: start, length: end - start), query: query)
    }
}

final class EditorState: ObservableObject {
    weak var view: NSTextView?
    private var pendingSelection: (range: NSRange, text: String)?
    func selectWhenReady(range: NSRange, text: String) {
        pendingSelection = (range, text)
        applyPendingSelection()
    }
    func clearPendingSelection() { pendingSelection = nil }
    func editorTextDidChange(_ view: NSTextView) {
        guard let pending = pendingSelection else { return }
        if view.string == pending.text { applyPendingSelection() } else { pendingSelection = nil }
    }
    func applyPendingSelection() {
        guard let view, let pending = pendingSelection, view.string == pending.text else { return }
        pendingSelection = nil
        guard pending.range.location != NSNotFound, NSMaxRange(pending.range) <= (view.string as NSString).length else { return }
        view.setSelectedRange(pending.range)
        view.scrollRangeToVisible(pending.range)
        view.window?.makeFirstResponder(view)
    }
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

final class LinkCompletionTextView: NSTextView {
    var handleCompletionKey: ((NSEvent) -> Bool)?
    var followLink: ((CardLinkTarget) -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let manager = layoutManager, let container = textContainer, manager.numberOfGlyphs > 0 {
            var point = convert(event.locationInWindow, from: nil)
            point.x -= textContainerOrigin.x; point.y -= textContainerOrigin.y
            let glyph = manager.glyphIndex(for: point, in: container)
            if glyph < manager.numberOfGlyphs,
               manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) {
                let location = manager.characterIndexForGlyph(at: glyph)
                if let link = CardLinkParser.link(in: string, atUTF16: location) {
                    followLink?(link.target)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if handleCompletionKey?(event) == true { return }
        super.keyDown(with: event)
    }
}


// Kept in the editor's view hierarchy: suggestions never steal the text cursor.
final class LinkCompletionState: ObservableObject {
    @Published var visible = false
    @Published var matches: [CardifyNote] = []
    @Published var selectedIndex = 0
    @Published var message = ""
    private(set) var context: LinkCompletionContext?
    private var suppressed: LinkCompletionContext?
    private var cachedFolder = ""
    private var cachedNotes: [CardifyNote] = []
    private var loading = false
    private var scanFailed = false
    private var scanToken = UUID()
    weak var view: NSTextView?

    func refresh(in view: NSTextView) {
        self.view = view
        guard view.selectedRange().length == 0,
              let found = LinkCompletionContext.find(in: view.string, caret: view.selectedRange().location) else {
            close(); suppressed = nil; return
        }
        guard found != suppressed else { visible = false; return }
        suppressed = nil
        context = found
        let defaults = UserDefaults.standard
        let preferred = defaults.string(forKey: "notesFolder") ?? ""
        let fallback = defaults.string(forKey: "saveFolder") ?? ""
        let folder = preferred.isEmpty ? fallback : preferred
        if folder != cachedFolder {
            cachedFolder = folder
            cachedNotes = []
            loading = false
            scanFailed = false
            scanToken = UUID()
            if !folder.isEmpty { loadNotes(folder: folder, token: scanToken) }
        } else if !folder.isEmpty && cachedNotes.isEmpty && !loading && !visible {
            scanToken = UUID()
            loadNotes(folder: folder, token: scanToken)
        }
        if folder.isEmpty { message = "Choose your notes folder to search." }
        else if loading { message = "Searching notes…" }
        else if scanFailed { message = "Can't read this notes folder. Choose it again." }
        else { message = "No matching notes." }
        matches = Array(cachedNotes.lazy.filter { $0.canLink && (found.query.isEmpty || $0.path.localizedStandardContains(found.query)) }.prefix(30))
        selectedIndex = min(selectedIndex, max(0, matches.count - 1))
        visible = true
    }
    private func loadNotes(folder: String, token: UUID) {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = CardifyNoteIndex.scan(folder: URL(fileURLWithPath: folder, isDirectory: true))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanToken == token else { return }
                self.cachedNotes = found ?? []
                self.scanFailed = found == nil
                self.loading = false
                if let view = self.view { self.refresh(in: view) }
            }
        }
    }
    func close() {
        visible = false
        context = nil
        matches = []
        selectedIndex = 0
        scanToken = UUID()
        cachedFolder = ""
        cachedNotes = []
        loading = false
        scanFailed = false
    }
    func dismiss() { suppressed = context; close() }
    func choose(_ note: CardifyNote) {
        guard let view, view.selectedRange().length == 0,
              let current = LinkCompletionContext.find(in: view.string, caret: view.selectedRange().location), current == context else { close(); return }
        close()
        view.insertText(note.wikiLink, replacementRange: current.range)
        view.window?.makeFirstResponder(view)
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: "notesFolder")
        cachedFolder = ""; cachedNotes = []; suppressed = nil
        if let view { view.window?.makeFirstResponder(view); refresh(in: view) }
    }
    func handleKey(_ event: NSEvent) -> Bool {
        guard visible else { return false }
        switch event.keyCode {
        case 53: dismiss(); return true
        case 125: if !matches.isEmpty { selectedIndex = min(matches.count - 1, selectedIndex + 1) }; return true
        case 126: if !matches.isEmpty { selectedIndex = max(0, selectedIndex - 1) }; return true
        case 36, 48, 76:
            guard matches.indices.contains(selectedIndex) else { return false }
            choose(matches[selectedIndex]); return true
        default: return false
        }
    }
}

struct MarkdownEditor: View {
    @Binding var text: String
    let editor: EditorState
    let onFollowLink: (CardLinkTarget) -> Void
    @StateObject private var completion = LinkCompletionState()
    var body: some View {
        VStack(spacing: 0) {
            MarkdownTextView(text: $text, editor: editor, completion: completion, onFollowLink: onFollowLink)
            if completion.visible {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(completion.matches.isEmpty ? completion.message : "Link a note · ↑↓ to select · Return to insert")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose Notes Folder…") { completion.chooseFolder() }
                        Button("Close") { completion.dismiss() }
                    }
                    if !completion.matches.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(completion.matches.enumerated()), id: \.element.id) { index, note in
                                    Button { completion.choose(note) } label: {
                                        Text(note.path).lineLimit(1).truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3).padding(.horizontal, 5)
                                            .background(index == completion.selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(maxHeight: 130)
                    }
                }.padding(8).background(Color(nsColor: .controlBackgroundColor))
                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.2)))
            }
        }
    }
}

private struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let editor: EditorState
    @ObservedObject var completion: LinkCompletionState
    let onFollowLink: (CardLinkTarget) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        let contentSize = scroll.contentSize
        let view = LinkCompletionTextView(frame: NSRect(origin: .zero, size: contentSize))
        view.minSize = NSSize(width: 0, height: contentSize.height)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.isRichText = false; view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false; view.isAutomaticTextReplacementEnabled = false
        view.allowsUndo = true; view.delegate = context.coordinator; view.string = text; view.textContainerInset = NSSize(width: 10, height: 10)
        view.handleCompletionKey = { [weak coordinator = context.coordinator] event in coordinator?.parent.completion.handleKey(event) ?? false }
        view.followLink = { [weak coordinator = context.coordinator] target in coordinator?.parent.onFollowLink(target) }
        scroll.documentView = view; editor.view = view; completion.view = view
        editor.applyPendingSelection()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text; completion.close() }
        editor.view = view; completion.view = view
        editor.applyPendingSelection()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        init(_ parent: MarkdownTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.editor.editorTextDidChange(view)
            parent.text = view.string
            DispatchQueue.main.async { [weak self, weak view] in if let view { self?.parent.completion.refresh(in: view) } }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            DispatchQueue.main.async { [weak self, weak view] in if let view { self?.parent.completion.refresh(in: view) } }
        }
    }
}
