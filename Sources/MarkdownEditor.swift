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
    func discardUndoHistory() {
        clearPendingSelection()
        (view as? LinkCompletionTextView)?.discardEditorUndo()
    }
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
    private let textUndoManager = UndoManager()
    // Hiding metadata changes only presentation attributes. The source string,
    // UTF-16 offsets and the text view's undo manager are never replaced.
    private var wantsHiddenFrontmatter = false
    private var hiddenFrontmatterRange: NSRange?
    private var originalFrontmatterAttributes: [(NSRange, [NSAttributedString.Key: Any])] = []

    static func frontmatterRange(in text: String) -> NSRange? { frontmatterInfo(in: text)?.range }

    static func frontmatterInfo(in text: String) -> (range: NSRange, isCardify: Bool)? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        func lineContent(_ range: NSRange) -> String {
            var end = NSMaxRange(range)
            while end > range.location && [10, 13].contains(Int(source.character(at: end - 1))) { end -= 1 }
            return source.substring(with: NSRange(location: range.location, length: end - range.location))
        }
        func delimiter(_ line: String) -> Bool {
            guard line.hasPrefix("---") else { return false }
            return line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
        }
        let first = source.lineRange(for: NSRange(location: 0, length: 0))
        var opening = lineContent(first)
        if opening.hasPrefix("\u{feff}") { opening.removeFirst() }
        guard delimiter(opening) else { return nil }
        let mapping = try! NSRegularExpression(pattern: #"^([\p{L}_][\p{L}\p{N}_. -]*|'(?:[^']|'')*'|"(?:[^"\\]|\\.)*")[ \t]*:[ \t]*(.*)$"#)
        var at = NSMaxRange(first)
        var hasMapping = false
        var hasCardifyMarker = false
        var allowsNested = false
        while at < source.length {
            let line = source.lineRange(for: NSRange(location: at, length: 0))
            let content = lineContent(line)
            if delimiter(content) { return hasMapping ? (NSRange(location: 0, length: NSMaxRange(line)), hasCardifyMarker) : nil }
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { at = NSMaxRange(line); continue }
            if content.hasPrefix(" ") || content.hasPrefix("\t") {
                guard hasMapping && allowsNested else { return nil }
            } else if content.hasPrefix("- ") || content == "-" {
                // YAML block sequences may be unindented after `tags:`.
                guard hasMapping && allowsNested else { return nil }
            } else {
                let value = content as NSString
                guard let match = mapping.firstMatch(in: content, range: NSRange(location: 0, length: value.length)) else { return nil }
                let key = value.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
                let raw = value.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                hasMapping = true
                hasCardifyMarker = hasCardifyMarker || key == "card_id" || key == "cardify_index"
                allowsNested = raw.isEmpty || raw.hasPrefix("#") || raw == "|" || raw == "|-" || raw == "|+" || raw == ">" || raw == ">-" || raw == ">+"
            }
            at = NSMaxRange(line)
        }
        return nil
    }

    func setFrontmatterHidden(_ hidden: Bool) {
        guard hidden != wantsHiddenFrontmatter || (hidden && hiddenFrontmatterRange == nil) else { return }
        wantsHiddenFrontmatter = hidden
        if hidden { hideFrontmatterIfPossible() } else { restoreFrontmatterAttributes() }
    }

    private func hideFrontmatterIfPossible() {
        guard wantsHiddenFrontmatter, hiddenFrontmatterRange == nil,
              let storage = textStorage, let range = Self.frontmatterRange(in: string), range.length > 0 else { return }
        let selection = selectedRange()
        var saved: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range, options: []) { attrs, effective, _ in saved.append((effective, attrs)) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 0.1; paragraph.maximumLineHeight = 0.1; paragraph.lineSpacing = 0
        hiddenFrontmatterRange = range; originalFrontmatterAttributes = saved
        storage.beginEditing()
        storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear, .paragraphStyle: paragraph], range: range)
        storage.endEditing()
        if selectedRange() != selection { setSelectedRange(selection) }
        needsDisplay = true
    }

    private func restoreFrontmatterAttributes() {
        guard hiddenFrontmatterRange != nil, let storage = textStorage else { hiddenFrontmatterRange = nil; originalFrontmatterAttributes = []; return }
        let selection = selectedRange()
        storage.beginEditing()
        for (range, attributes) in originalFrontmatterAttributes where NSMaxRange(range) <= storage.length {
            storage.setAttributes(attributes, range: range)
        }
        storage.endEditing()
        hiddenFrontmatterRange = nil; originalFrontmatterAttributes = []
        if selectedRange() != selection, NSMaxRange(selection) <= storage.length { setSelectedRange(selection) }
        needsDisplay = true
    }

    // Select the editable document body when metadata is concealed. Selecting
    // the invisible header too would make Delete, Cut, and replacement fail
    // the metadata protection check below.
    override func selectAll(_ sender: Any?) {
        guard let hidden = hiddenFrontmatterRange else { super.selectAll(sender); return }
        let start = NSMaxRange(hidden)
        setSelectedRange(NSRange(location: start, length: (string as NSString).length - start))
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if let hidden = hiddenFrontmatterRange, affectedCharRange.location < NSMaxRange(hidden) {
            if undoManager?.isUndoing == true || undoManager?.isRedoing == true {
                // Undoing a previously visible metadata edit is still allowed;
                // restore its normal attributes before AppKit applies it.
                restoreFrontmatterAttributes()
            } else {
                return false
            }
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func didChangeText() {
        super.didChangeText()
        if wantsHiddenFrontmatter && hiddenFrontmatterRange == nil { hideFrontmatterIfPossible() }
    }

    // List continuation operates on the actual UTF-16 source, including CRLF.
    // This is intentionally limited to bullet/task lists outside fenced code.
    static func listNewline(in text: String, selection: NSRange) -> (NSRange, String)? {
        let source = text as NSString
        guard selection.length == 0, selection.location != NSNotFound, selection.location <= source.length else { return nil }
        if let metadata = frontmatterRange(in: text), selection.location < NSMaxRange(metadata) { return nil }
        let probe = selection.location == source.length && source.length > 0 ? source.length - 1 : selection.location
        let line = source.lineRange(for: NSRange(location: probe, length: 0))
        // A caret immediately after a newline is on the following empty line.
        if selection.location == NSMaxRange(line) && selection.location > line.location && [10, 13].contains(Int(source.character(at: selection.location - 1))) { return nil }
        var contentEnd = NSMaxRange(line)
        while contentEnd > line.location && [10, 13].contains(Int(source.character(at: contentEnd - 1))) { contentEnd -= 1 }
        guard selection.location <= contentEnd else { return nil }
        let before = source.substring(with: NSRange(location: 0, length: line.location))
        var fence: (Character, Int)?
        for previous in before.components(separatedBy: .newlines) {
            let trimmed = previous.drop(while: { $0 == " " })
            guard previous.count - trimmed.count <= 3, let mark = trimmed.first, mark == "`" || mark == "~" else { continue }
            let count = trimmed.prefix(while: { $0 == mark }).count
            guard count >= 3 else { continue }
            if let open = fence {
                if open.0 == mark && count >= open.1 && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else { fence = (mark, count) }
        }
        guard fence == nil else { return nil }
        let contentRange = NSRange(location: line.location, length: contentEnd - line.location)
        let content = source.substring(with: contentRange)
        let pattern = try! NSRegularExpression(pattern: #"^([ \t]*)([-+*])([ \t]+)(?:\[([ xX])\]([ \t]+|$))?"#)
        guard let match = pattern.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)),
              selection.location >= line.location + NSMaxRange(match.range) else { return nil }
        let s = content as NSString
        let remainder = s.substring(from: NSMaxRange(match.range))
        if remainder.trimmingCharacters(in: .whitespaces).isEmpty { return (contentRange, "") }
        let indent = s.substring(with: match.range(at: 1)), bullet = s.substring(with: match.range(at: 2)), spacing = s.substring(with: match.range(at: 3))
        let task = match.range(at: 4).location != NSNotFound
        let suffix = task ? "[ ] " : ""
        var newline = NSMaxRange(line) > contentEnd ? source.substring(with: NSRange(location: contentEnd, length: NSMaxRange(line) - contentEnd)) : ""
        if newline.isEmpty {
            let all = text as NSString
            var i = 0
            while i < all.length {
                let c = all.character(at: i)
                if c == 13 { newline = i + 1 < all.length && all.character(at: i + 1) == 10 ? "\r\n" : "\r"; break }
                if c == 10 { newline = "\n"; break }
                i += 1
            }
        }
        if newline.isEmpty { newline = "\n" }
        return (selection, newline + indent + bullet + spacing + suffix)
    }

    override func insertNewline(_ sender: Any?) {
        if let (range, replacement) = Self.listNewline(in: string, selection: selectedRange()) {
            insertText(replacement, replacementRange: range)
        } else {
            super.insertNewline(sender)
        }
    }
    override var undoManager: UndoManager? { textUndoManager }
    @objc func undo(_ sender: Any?) { if textUndoManager.canUndo { textUndoManager.undo() } }
    @objc func redo(_ sender: Any?) { if textUndoManager.canRedo { textUndoManager.redo() } }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) { return textUndoManager.canUndo }
        if menuItem.action == #selector(redo(_:)) { return textUndoManager.canRedo }
        return super.validateMenuItem(menuItem)
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return textUndoManager.canUndo }
        if item.action == #selector(redo(_:)) { return textUndoManager.canRedo }
        return super.validateUserInterfaceItem(item)
    }

    // Text supplied by a different draft or another control invalidates the
    // ranges and targets captured by previous AppKit text undo operations.
    func replaceEditorText(_ text: String) {
        guard string != text else { return }
        restoreFrontmatterAttributes()
        breakUndoCoalescing()
        textUndoManager.removeAllActions()
        string = text
        hideFrontmatterIfPossible()
    }
    func discardEditorUndo() {
        breakUndoCoalescing()
        textUndoManager.removeAllActions()
    }

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
    @AppStorage("hideEditorFrontmatter") private var hideFrontmatter = true
    @State private var hiddenCustomHeader: String?
    var body: some View {
        let metadata = LinkCompletionTextView.frontmatterInfo(in: text)
        let header = metadata.map { (text as NSString).substring(with: $0.range) }
        // A plain mapping may be prose between two horizontal rules. Keep it
        // visible until the user explicitly chooses to hide that exact block.
        let isHidden = metadata.map { $0.isCardify ? hideFrontmatter : (header != nil && header == hiddenCustomHeader) } ?? false
        return VStack(spacing: 0) {
            if let metadata, let header {
                HStack {
                    Button(isHidden ? "Show Metadata" : "Hide Metadata") {
                        if metadata.isCardify { hideFrontmatter.toggle() }
                        else { hiddenCustomHeader = isHidden ? nil : header }
                        if let view = editor.view { view.window?.makeFirstResponder(view) }
                    }
                        .font(.caption).buttonStyle(.plain)
                        .help(isHidden ? "Reveal the Markdown frontmatter for editing" : "Hide the Markdown frontmatter")
                    Spacer()
                }.padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
            }
            MarkdownTextView(text: $text, editor: editor, completion: completion, hideFrontmatter: isHidden, onFollowLink: onFollowLink)
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
    let hideFrontmatter: Bool
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
        view.font = .systemFont(ofSize: 14, weight: .regular)
        view.isRichText = false; view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false; view.isAutomaticTextReplacementEnabled = false
        view.allowsUndo = true; view.delegate = context.coordinator; view.string = text; view.textContainerInset = NSSize(width: 16, height: 16)
        view.handleCompletionKey = { [weak coordinator = context.coordinator] event in coordinator?.parent.completion.handleKey(event) ?? false }
        view.followLink = { [weak coordinator = context.coordinator] target in coordinator?.parent.onFollowLink(target) }
        scroll.documentView = view; editor.view = view; completion.view = view
        view.setFrontmatterHidden(hideFrontmatter)
        editor.applyPendingSelection()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? LinkCompletionTextView else { return }
        if view.string != text { view.replaceEditorText(text); completion.close() }
        view.setFrontmatterHidden(hideFrontmatter)
        editor.view = view; completion.view = view
        editor.applyPendingSelection()
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let view = scroll.documentView as? LinkCompletionTextView else { return }
        view.discardEditorUndo()
        view.delegate = nil
        view.handleCompletionKey = nil
        view.followLink = nil
        if coordinator.parent.editor.view === view { coordinator.parent.editor.view = nil }
        if coordinator.parent.completion.view === view { coordinator.parent.completion.view = nil }
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
