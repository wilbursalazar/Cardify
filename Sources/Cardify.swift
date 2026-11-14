import SwiftUI
import AppKit
import PDFKit
import CoreText

struct CardDocument {
    var text: String
    var portrait: Bool
    var fontSize: Double
    var dotGrid: Bool = false
    var pageSize: CGSize { portrait ? CGSize(width: 216, height: 360) : CGSize(width: 360, height: 216) }

    func pdf(includeLinks: Bool = false) -> Data? {
        let size = pageSize
        let inset: CGFloat = 27 // 3/8 inch, in PDF points
        let body = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let metadata = CardMetadata.parse(text)
        var idLine: CTLine?
        var idWidth: CGFloat = 0
        if let id = metadata.id {
            guard !id.contains(where: { $0.isNewline || $0.isASCII && $0.isWhitespace && $0 != " " }) else { return nil }
            var size: CGFloat = 6.5
            repeat {
                let attr = NSAttributedString(string: id, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor(calibratedWhite: 0.40, alpha: 1)])
                idLine = CTLineCreateWithAttributedString(attr)
                idWidth = CGFloat(CTLineGetTypographicBounds(idLine!, nil, nil, nil))
                if idWidth <= body.width { break }
                size -= 0.5
            } while size >= 5
            guard idWidth <= body.width else { return nil }
        }
        // Frontmatter is normally followed by a separator newline. Start the
        // visible card at its first line so its title can share the ID row.
        let visibleBody = metadata.id == nil ? metadata.body : String(metadata.body.drop(while: { $0 == "\n" || $0 == "\r" }))
        let attributed = MarkdownRendering.render(visibleBody, fontSize: CGFloat(fontSize))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var media = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        var location = 0
        var pageIndex = 0
        var linkHits: [CardPreviewLinks.Hit] = []
        repeat {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(media)
            if dotGrid {
                context.saveGState()
                context.setFillColor(gray: 0.82, alpha: 1)
                for y in stride(from: body.minY + 3, through: body.maxY - 3, by: 12) {
                    for x in stride(from: body.minX + 3, through: body.maxX - 3, by: 12) {
                        context.fillEllipse(in: CGRect(x: x - 0.45, y: y - 0.45, width: 0.9, height: 0.9))
                    }
                }
                context.restoreGState()
            }
            context.saveGState()
            context.clip(to: body)
            if let idLine {
                context.textPosition = CGPoint(x: body.maxX - idWidth, y: body.maxY - 7)
                CTLineDraw(idLine, context)
            }
            // Draw the first line beside the ID, then use the full width below it.
            var consumed = 0
            var textBody = body
            if idLine != nil {
                let availableWidth = body.width - idWidth - 5
                if availableWidth >= 24 {
                    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
                    let count = CTTypesetterSuggestLineBreak(typesetter, location, Double(availableWidth))
                    if count > 0 {
                        let line = CTTypesetterCreateLine(typesetter, CFRange(location: location, length: count))
                        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                        let origin = CGPoint(x: body.minX, y: body.maxY - ascent)
                        context.textPosition = origin
                        CTLineDraw(line, context)
                        if includeLinks { CardPreviewLinks.collect(line: line, origin: origin, page: pageIndex, into: &linkHits) }
                        consumed = count
                        textBody.size.height -= max(9, ceil(ascent + descent + leading + 1.5))
                    } else {
                        textBody.size.height -= 12
                    }
                } else {
                    // Very long IDs can occupy the full width; keep their own row.
                    textBody.size.height -= 12
                }
            }
            if location + consumed < attributed.length {
                let path = CGPath(rect: textBody, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location + consumed, length: 0), path, nil)
                CTFrameDraw(frame, context)
                if includeLinks { CardPreviewLinks.collect(frame: frame, page: pageIndex, into: &linkHits) }
                consumed += CTFrameGetVisibleStringRange(frame).length
            }
            context.restoreGState()
            context.endPDFPage()
            guard consumed > 0 else { context.closePDF(); return nil }
            location += consumed
            pageIndex += 1
        } while location < attributed.length
        context.closePDF()
        return includeLinks ? CardPreviewLinks.add(to: data as Data, hits: linkHits) : data as Data
    }
}

struct PDFPreviewRevision: Equatable {
    let mode: String
    let content: String
    let portrait: Bool
    let fontSize: Double
    let dotGrid: Bool
    let filePath: String?
}

// Draw each page synchronously so replacing a PDF never exposes PDFKit's
// asynchronously tiled, temporarily blank document view while typing.
final class PreviewPagesView: NSView {
    var document: PDFDocument?
    var pageRects: [NSRect] = []
    var linkHandler: ((CardLinkTarget) -> Void)?
    var linksEnabled = false
    private var pressedLink: CardLinkTarget?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let document, let context = NSGraphicsContext.current?.cgContext else { return }
        for (index, rect) in pageRects.enumerated() where rect.intersects(dirtyRect) {
            guard let page = document.page(at: index), let pageRef = page.pageRef else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            NSColor.white.setFill(); rect.fill()
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: rect.width / bounds.width, y: -rect.height / bounds.height)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.drawPDFPage(pageRef)
            context.restoreGState()
            NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    func link(at point: NSPoint) -> CardLinkTarget? {
        guard linksEnabled, let document else { return nil }
        for (index, rect) in pageRects.enumerated() where rect.contains(point) {
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let location = NSPoint(x: bounds.minX + (point.x - rect.minX) * bounds.width / rect.width,
                                   y: bounds.minY + (rect.maxY - point.y) * bounds.height / rect.height)
            for annotation in page.annotations.reversed() where annotation.bounds.contains(location) {
                guard let action = annotation.action as? PDFActionURL, let url = action.url else { continue }
                return CardPreviewLinks.target(from: url)
            }
        }
        return nil
    }
    override func mouseDown(with event: NSEvent) { pressedLink = link(at: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) {
        let released = link(at: convert(event.locationInWindow, from: nil))
        if let released, released == pressedLink { linkHandler?(released) }
        pressedLink = nil
    }
}

final class StablePDFPreviewView: NSView {
    let scrollView = NSScrollView()
    let pagesView = PreviewPagesView()
    private var displayedRevision: PDFPreviewRevision?
    private var displayedData: Data?

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = pagesView
        addSubview(scrollView)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutPages()
    }
    func setLinkHandler(_ handler: @escaping (CardLinkTarget) -> Void) { pagesView.linkHandler = handler }
    func update(data: Data?, revision: PDFPreviewRevision?) {
        guard let data else { pagesView.linksEnabled = false; return }
        if let displayedData, (revision != nil ? revision == displayedRevision : displayedRevision == nil && data == displayedData) {
            pagesView.linksEnabled = true
            return
        }
        guard let document = PDFDocument(data: data) else { pagesView.linksEnabled = false; return }
        let sameCard = displayedData != nil && displayedRevision?.mode == revision?.mode && displayedRevision?.filePath == revision?.filePath
        pagesView.linksEnabled = false
        pagesView.document = document
        displayedData = data; displayedRevision = revision
        layoutPages(resetScroll: !sameCard)
        pagesView.needsDisplay = true
        pagesView.linksEnabled = true
    }
    func cancelPending() { pagesView.linksEnabled = false; pagesView.linkHandler = nil }

    private func layoutPages(resetScroll: Bool = false) {
        let size = scrollView.contentSize
        guard size.width > 0, size.height > 0 else { return }
        let oldOrigin = scrollView.contentView.bounds.origin
        var width = max(1, size.width - 20)
        if let document = pagesView.document, document.pageCount == 1,
           let page = document.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            if bounds.height > 0 { width = min(width, max(1, size.height - 20) * bounds.width / bounds.height) }
        }
        var heights: [CGFloat] = []
        if let document = pagesView.document {
            for index in 0..<document.pageCount {
                let bounds = document.page(at: index)?.bounds(for: .mediaBox) ?? .zero
                heights.append(bounds.width > 0 ? width * bounds.height / bounds.width : 0)
            }
        }
        let totalHeight = heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * 12
        var y = max(10, (size.height - totalHeight) / 2)
        pagesView.pageRects = heights.map { height in
            defer { y += height + 12 }
            return NSRect(x: (size.width - width) / 2, y: y, width: width, height: height)
        }
        pagesView.frame = NSRect(x: 0, y: 0, width: size.width, height: max(size.height, totalHeight + 20))
        let desired = resetScroll ? NSPoint.zero : oldOrigin
        let clip = scrollView.contentView
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: desired, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
        pagesView.needsDisplay = true
    }
}

struct PDFPreview: NSViewRepresentable {
    let data: Data?
    let revision: PDFPreviewRevision?
    let onFollowLink: (CardLinkTarget) -> Void
    init(data: Data?, revision: PDFPreviewRevision? = nil, onFollowLink: @escaping (CardLinkTarget) -> Void) {
        self.data = data; self.revision = revision; self.onFollowLink = onFollowLink
    }
    func makeNSView(context: Context) -> StablePDFPreviewView { StablePDFPreviewView() }
    func updateNSView(_ view: StablePDFPreviewView, context: Context) {
        view.setLinkHandler(onFollowLink)
        view.update(data: data, revision: revision)
    }
    static func dismantleNSView(_ view: StablePDFPreviewView, coordinator: ()) { view.cancelPending() }
}

struct ZoteroCreator: Decodable {
    let firstName: String?
    let lastName: String?
    let name: String?
    var display: String { [firstName, lastName].compactMap { $0 }.joined(separator: " ").isEmpty ? (name ?? "") : [firstName, lastName].compactMap { $0 }.joined(separator: " ") }
}
struct ZoteroData: Decodable {
    let title: String?
    let date: String?
    let creators: [ZoteroCreator]?
}
struct ZoteroItem: Decodable, Identifiable {
    let key: String
    let data: ZoteroData
    var id: String { key }
    static func clean(_ value: String) -> String { value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
    var title: String { let t = Self.clean(data.title ?? ""); return t.isEmpty ? "Untitled" : t }
    var authors: String { (data.creators ?? []).map { Self.clean($0.display) }.filter { !$0.isEmpty }.joined(separator: ", ") }
    var description: String { [authors, title, Self.clean(data.date ?? "")].filter { !$0.isEmpty }.joined(separator: ", ") }
    func markdown(location: String) -> String {
        let loc = Self.clean(location)
        let suffix = loc.isEmpty ? "" : ", " + loc
        return "Source: " + description + suffix + "\nZotero: [Open source](zotero://select/library/items/" + key + ")"
    }
}

struct ResearchClip: Identifiable {
    let id = UUID()
    var header: String = ""
    var note: String = ""
    var source: String = ""
    static func from(_ url: URL) -> ResearchClip? {
        guard url.scheme == "cardifyresearch", url.host == "clip", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func field(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
        let source = field("source")
        guard let pageURL = URL(string: source), ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""), pageURL.host != nil else { return nil }
        return ResearchClip(header: field("title"), note: field("text"), source: source)
    }
    var markdown: String {
        let title = header.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return "# " + (title.isEmpty ? "Research note" : title) + "\n\n" + note + "\n\nSource: " + source + "\n"
    }
}
struct ResearchEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var clip: ResearchClip
    let onUse: (String, Bool) -> Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Research card").font(.title2.bold())
            TextField("Header", text: $clip.header)
            Text("Note").fontWeight(.medium)
            TextEditor(text: $clip.note).font(.system(size: 13)).border(Color.secondary.opacity(0.3)).frame(minHeight: 160)
            TextField("Source URL or citation", text: $clip.source)
            Text("Review the clip before adding it. Replacing the draft discards its current unsaved text.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Append to Draft") { if onUse(clip.markdown, true) { dismiss() } }
                Button("Replace Draft") { if onUse(clip.markdown, false) { dismiss() } }.buttonStyle(.borderedProminent).modifier(CharcoalPrimaryTint())
            }
        }.padding(22).frame(width: 560, height: 390)
    }
}

private struct EditorHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ContentView: View {
    @AppStorage("draft") private var text = "# Example Title\n\nMain content area for notes.\n- Keep it concise, or continue onto another card.\n- Use Markdown for Obsidian.\n\nSource: Book Title, p. 42\n\nTags: #quicknote #important"
    @AppStorage("portrait") private var portrait = false
    @AppStorage("fontSize") private var fontSize = 9.0
    @AppStorage("dotGrid") private var dotGrid = false
    @AppStorage("cardMode") private var cardMode = "markdown"
    @AppStorage("habitDraft") private var habitDraft = ""
    @AppStorage("todoDraft") private var todoDraft = ""
    @AppStorage("outlineDraft") private var outlineDraft = ""
    @State private var tracker = HabitTracker()
    @State private var todo = TodoList()
    @State private var outline = OutlineDocument()
    @AppStorage("saveFolder") private var saveFolder = ""
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("autoTimestampID") private var autoTimestampID = false
    @AppStorage("idMode") private var storedIDMode = ""
    @AppStorage("timestampDateStyle") private var timestampDateStyle = TimestampDateStyle.sortable.rawValue
    @AppStorage("timestampIncludeTime") private var timestampIncludeTime = true
    @AppStorage("newCardWorkflow") private var newCardWorkflow = WorkflowPreference.configured.rawValue
    @AppStorage("cardifyAppearance") private var storedAppearance = AppearancePreference.system.rawValue
    @AppStorage("workspaceArrangement") private var storedWorkspaceArrangement = WorkspaceArrangement.editorLeft.rawValue
    @AppStorage("showNotesSidebar") private var showNotesSidebar = true
    @StateObject private var editor = EditorState()
    @StateObject private var graphWindow = GraphWindowManager()
    @State private var fileURLs: [String: URL] = [:]
    @State private var savedMarkdownSnapshot: String?
    @State private var savedHabitSnapshot: String?
    @State private var savedTodoSnapshot: String?
    @State private var savedOutlineSnapshot: String?
    // Exact bytes-as-text read from disk, independent of a structured editor's canonical Markdown.
    @State private var diskSnapshots: [String: Data] = [:]
    @State private var newDraftBaselines: [String: Data] = [:]
    @State private var autosaveTask: Task<Void, Never>?
    @State private var history = CardHistory()
    @State private var traversingHistory = false
    @State private var suppressHistorySave = false
    @State private var branchSaveFolders: [String: URL] = [:]
    @State private var showZotero = false
    @State private var showNotes = false
    @State private var showOutlineNotes = false
    @State private var outlineLinkCompletion: ((String) -> Void)?
    @State private var showLibrary = false
    @State private var showDebate = false
    @State private var showDebateBrowser = false
    @State private var showSettings = false
    @State private var linkRequestID = UUID()
    @State private var research: ResearchClip?
    @State private var status = "Draft saved on this Mac."
    @State private var sidebarRefreshToken = UUID()
    @State private var editorHeaderHeight: CGFloat = 100
    var fileURL: URL? {
        get { fileURLs[cardMode] }
        nonmutating set {
            fileURLs[cardMode] = newValue
            if newValue == nil { diskSnapshots.removeValue(forKey: cardMode); newDraftBaselines.removeValue(forKey: cardMode) }
        }
    }
    var branchSaveFolder: URL? {
        get { branchSaveFolders[cardMode] }
        nonmutating set { branchSaveFolders[cardMode] = newValue }
    }
    var card: CardDocument { CardDocument(text: text, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid) }
    var idMode: IDMode { IDMode(rawValue: storedIDMode) ?? (autoTimestampID ? .timestamp : .titleOnly) }
    var outlineCard: CardDocument? {
        let source = outline.markdown
        let metadata = CardMetadata.parse(source)
        guard metadata.id != nil || !CardMetadata.hasNonemptyID(source) else { return nil }
        return CardDocument(text: outline.printMarkdown(cardID: metadata.id), portrait: portrait, fontSize: fontSize, dotGrid: dotGrid)
    }
    var activePDF: Data? {
        if cardMode == "habits" { return tracker.pdf(portrait: portrait, dotGrid: dotGrid, fontSize: fontSize) }
        if cardMode == "todos" { return CardDocument(text: todo.printMarkdown, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid).pdf() }
        if cardMode == "outline" { return outlineCard?.pdf() }
        return card.pdf()
    }
    var previewPDF: Data? {
        if cardMode == "markdown" { return card.pdf(includeLinks: true) }
        if cardMode == "outline" { return outlineCard?.pdf(includeLinks: true) }
        return activePDF
    }
    var previewRevision: PDFPreviewRevision {
        PDFPreviewRevision(mode: cardMode, content: cardMode == "habits" ? tracker.markdown : cardMode == "todos" ? todo.printMarkdown : cardMode == "outline" ? outline.markdown : text, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid, filePath: fileURL?.standardizedFileURL.path)
    }
    var currentCardTitle: String {
        let title = cardMode == "habits" ? tracker.title : cardMode == "todos" ? todo.title : cardMode == "outline" ? outline.title : NoteEditing.title(in: text)
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled card") : title
    }
    var titlePlaceholder: String {
        guard showDebate else { return "Title" }
        switch DebateNotes.parse(text).role {
        case .project: return "Resolution question"
        case .aff: return "AFF point title"
        case .def: return "DEF point title"
        case .evidence: return "Evidence title"
        case .objection: return "Objection title"
        case .argument: return "Argument title"
        case .reply: return "Reply title"
        case nil: return "Title"
        }
    }
    func setTracker(_ value: HabitTracker) {
        tracker = value
        if let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) { habitDraft = encoded }
    }
    func setTodo(_ value: TodoList) {
        todo = value
        if let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) { todoDraft = encoded }
    }
    func setOutline(_ value: OutlineDocument) {
        outline = value
        if let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) { outlineDraft = encoded }
    }
    func switchMode(to mode: String) {
        guard mode != cardMode else { return }
        var discarded: [String] = []
        guard confirmReplaceDrafts([cardMode], discarded: &discarded) else { return }
        for discardedMode in discarded { clearDiscardedDraft(discardedMode) }
        cardMode = mode
        if let fileURL { history.visit(fileURL) } else { history.detach() }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button { showNotesSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(showNotesSidebar ? "Hide notes sidebar" : "Show notes sidebar")
                    .accessibilityLabel(showNotesSidebar ? "Hide notes sidebar" : "Show notes sidebar")
                Text("Cardify").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppearancePreference.foreground(for: storedAppearance))
                Button { navigateHistory(back: true) } label: { Image(systemName: "chevron.left") }
                    .help("Back to the previous card").keyboardShortcut("[", modifiers: .command).disabled(history.backTarget == nil)
                Button { navigateHistory(back: false) } label: { Image(systemName: "chevron.right") }
                    .help("Forward to the next visited card").keyboardShortcut("]", modifiers: .command).disabled(history.forwardTarget == nil)
                Divider().frame(height: 16)
                Button("Library") { showLibrary = true }.fixedSize()
                Button("Graph") { showGraph() }.fixedSize().help("Explore card connections in a separate window")
                Spacer(minLength: 8)
                Menu("Layout") {
                    ForEach(WorkspaceArrangement.allCases) { choice in
                        Button {
                            storedWorkspaceArrangement = choice.rawValue
                        } label: {
                            if WorkspaceArrangement.stored(storedWorkspaceArrangement) == choice {
                                Label(choice.title, systemImage: "checkmark")
                            } else {
                                Text(choice.title)
                            }
                        }
                    }
                    Divider()
                    Toggle("Show notes sidebar", isOn: $showNotesSidebar)
                }
                Menu("File") {
                    Button("New Card", action: newCard)
                    Button("Open Markdown…", action: openFile)
                    Button("Save As…") { _ = saveMarkdown(saveAs: true) }
                    Divider()
                    Button("Export PDF…", action: exportPDF)
                    Divider()
                    Button("Choose Save Folder…", action: chooseFolder)
                    Button("Choose Notes Folder…", action: chooseNotesFolder)
                    Divider()
                    Button("Settings…") { showSettings = true }
                }
                Button("Save") { _ = saveMarkdown() }.fixedSize().keyboardShortcut("s")
                Button("Print", action: printCards).fixedSize().keyboardShortcut("p")
                if storedAppearance == AppearancePreference.charcoal.rawValue {
                    Button("Save & Print") { if saveMarkdown() { printCards() } }.fixedSize().buttonStyle(CharcoalPrimaryButtonStyle())
                } else if storedAppearance == AppearancePreference.slate.rawValue {
                    Button("Save & Print") { if saveMarkdown() { printCards() } }.fixedSize().buttonStyle(SlatePrimaryButtonStyle())
                } else {
                    Button("Save & Print") { if saveMarkdown() { printCards() } }.fixedSize().buttonStyle(.borderedProminent)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                if showNotesSidebar {
                    CardSidebar(currentURL: fileURL, openURLs: Array(fileURLs.values), draftTitle: currentCardTitle, draftID: cardMode == "markdown" ? CardMetadata.parse(text).id : cardMode == "outline" ? CardMetadata.parse(outline.markdown).id : nil,
                                notesFolder: notesFolder, saveFolder: saveFolder,
                                refreshToken: sidebarRefreshToken, onOpen: { url in
                                    let folder = notesFolder.isEmpty ? saveFolder : notesFolder
                                    guard !folder.isEmpty else { status = "Choose a notes folder before opening a sidebar note."; return false }
                                    let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                                    return loadFile(url, validating: { CardGraph.canOpen(url, in: root) })
                                }, onReveal: revealSidebarNote, onDuplicate: duplicateSidebarNote,
                                onRename: renameSidebarNote, onTrash: trashSidebarNote,
                                onCopyPath: copySidebarPath, onNew: newCard, onChooseFolder: chooseNotesFolder)
                        .frame(width: 205)
                    Divider().padding(.trailing, 10)
                }
                WorkspaceSplitView(arrangement: WorkspaceArrangement.stored(storedWorkspaceArrangement), editor: {
                GeometryReader { editorGeometry in
                VStack(alignment: .leading) {
                    ScrollView(.vertical) {
                    VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Picker("Card type", selection: Binding(get: { cardMode == "markdown" && showDebate ? "debate" : cardMode }, set: { mode in
                            if mode == "debate" {
                                switchMode(to: "markdown")
                                if cardMode == "markdown" { showDebate = true }
                            } else {
                                switchMode(to: mode)
                                if mode == "markdown" && cardMode == "markdown" { showDebate = false }
                            }
                        })) {
                            Text("Research").tag("markdown"); Text("Habit").tag("habits"); Text("To Do").tag("todos"); Text("Outline").tag("outline"); Text("Debate").tag("debate")
                        }.pickerStyle(.menu).labelsHidden().fixedSize().help("Choose Research, Habit, To Do, Outline, or Debate")
                        Spacer(minLength: 4)
                        Menu("Templates") {
                            if showDebate && cardMode == "markdown" {
                                Button("AFF prompts") { editor.insert(DebateTemplates.body(for: .aff)) }
                                Button("DEF prompts") { editor.insert(DebateTemplates.body(for: .def)) }
                                Button("Evidence prompts") { editor.insert(DebateTemplates.body(for: .evidence)) }
                                Button("Objection prompts") { editor.insert(DebateTemplates.body(for: .objection)) }
                                Button("Argument prompts") { editor.insert(DebateTemplates.body(for: .argument)) }
                                Button("Reply prompts") { editor.insert(DebateTemplates.body(for: .reply)) }
                            } else if cardMode == "habits" {
                                Button("Weekly Habit Tracker") { newCard() }
                            } else if cardMode == "todos" {
                                Button("New To Do List") { newCard() }
                            } else if cardMode == "outline" {
                                Button("New Outline") { newCard() }
                            } else {
                                Button("Idea Card") { insertTemplate(.idea) }
                                Button("Reading Card") { insertTemplate(.reading) }
                                Button("Index Card") { insertTemplate(.index) }
                                Button("Mark Current Card as Index") { markIndexCard() }.disabled(cardMode != "markdown")
                                Divider()
                                Button("New Idea from This Card…") { ideaFromCurrent() }.disabled(cardMode != "markdown")
                                Divider()
                                Button("Research Card…") { research = ResearchClip() }
                            }
                        }
                    }
                    if cardMode == "markdown" && showDebate {
                        DebatePanel(text: $text, showBrowser: $showDebateBrowser, currentURL: fileURL, onOpen: { url in loadFile(url) }, onNew: { draft, parent in
                            guard confirmReplaceDraft() else { return false }
                            let info = DebateNotes.parse(draft)
                            var prepared = draft
                            if let parent = parent {
                                guard CardGraph.canOpen(parent.url, in: parent.root),
                                      let latest = try? String(contentsOf: parent.url, encoding: .utf8),
                                      DebateNotes.parse(latest).valid,
                                      DebateNotes.parse(latest).role == parent.expectedRole,
                                      (!CardMetadata.hasNonemptyID(latest) || CardMetadata.parse(latest).id != nil),
                                      DebateIDs.parentID(in: latest, at: parent.url) == parent.expectedID else {
                                    status = "This parent changed. Refresh the argument map and try again."
                                    let alert = NSAlert(); alert.messageText = "Can't create this card"; alert.informativeText = status; alert.runModal()
                                    return false
                                }
                                if info.role != .aff && info.role != .def, let parentID = parent.expectedID {
                                    do {
                                        var roots = scanRoots(for: fileURL)
                                        if !roots.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == parent.root }) { roots.append(parent.root) }
                                        let existing = try DebateIDs.existing(in: roots)
                                        guard let result = DebateIDs.prepareChild(draft, parentID: parentID, existing: existing) else {
                                            status = "Could not prepare the connected card's ID. Check its metadata."
                                            let alert = NSAlert(); alert.messageText = "Can't create this card"; alert.informativeText = status; alert.runModal()
                                            return false
                                        }
                                        prepared = result
                                    } catch {
                                        status = "Could not check debate IDs: \(error.localizedDescription)"
                                        let alert = NSAlert(); alert.messageText = "Can't create this card"; alert.informativeText = status; alert.runModal()
                                        return false
                                    }
                                }
                            }
                            if info.role == .aff || info.role == .def {
                                do {
                                    var roots = scanRoots(for: fileURL)
                                    if let root = parent?.root, !roots.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == root }) { roots.append(root) }
                                    let existing = try DebateIDs.existing(in: roots)
                                    guard let result = DebateIDs.prepare(draft, existing: existing) else {
                                        status = "Could not prepare an AFF/DEF ID. Check the card metadata."
                                        let alert = NSAlert(); alert.messageText = "Can't create this point"; alert.informativeText = status; alert.runModal()
                                        return false
                                    }
                                    prepared = result
                                } catch {
                                    status = "Could not check debate IDs: \(error.localizedDescription)"
                                    let alert = NSAlert(); alert.messageText = "Can't create this point"; alert.informativeText = status; alert.runModal()
                                    return false
                                }
                            }
                            let folderPath = notesFolder.isEmpty ? saveFolder : notesFolder
                            let folder = folderPath.isEmpty ? fileURL?.deletingLastPathComponent() : URL(fileURLWithPath: folderPath, isDirectory: true)
                            editor.discardUndoHistory()
                            text = prepared; fileURL = nil; branchSaveFolder = folder; savedMarkdownSnapshot = nil; history.detach()
                            if idMode != .titleOnly && !ensureID() { return true }
                            status = info.role == .project ? "Enter the resolution in the title, then save." : "New debate card. Save it when ready."
                            return true
                        }, onFollowLink: followLink)
                    }
                    if cardMode == "markdown" {
                    HStack {
                        TextField(titlePlaceholder, text: Binding(get: { NoteEditing.title(in: text) }, set: { text = NoteEditing.setTitle($0, in: text) }))
                            .textFieldStyle(.plain).font(.system(size: 17, weight: .semibold)).padding(.vertical, 6)
                        Picker("ID", selection: Binding(get: { idMode }, set: { mode in
                            selectIDMode(mode)
                        })) {
                            ForEach(IDMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }.labelsHidden().frame(width: 110).accessibilityLabel("ID style").help(showDebate ? "AFF and DEF points use their own IDs; connected cards inherit their parent’s ID. Existing IDs are kept." : "Choose how IDs are suggested for new notes. Existing IDs are kept.")
                    }
                    HStack {
                        Text("Write").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if showDebate || idMode != .titleOnly || CardMetadata.parse(text).id != nil {
                            TextField("Card ID", text: Binding(get: { CardMetadata.parse(text).id ?? "" }, set: { id in
                                if let updated = NoteEditing.setID(id, in: text) { text = updated }
                                else { status = "Could not edit card ID in the existing metadata." }
                            })).frame(width: 145).help("Edit the card ID; existing files are not automatically renamed.")
                        }
                        Spacer()
                        Text("⌘-click links to open").font(.caption).foregroundStyle(.secondary)
                    }
                    if idMode != .titleOnly {
                        HStack {
                            if idMode == .luhmann {
                                Button("Continue sequence") { relatedFromCurrent(continuation: true) }.fixedSize().help("Create the next card in this sequence")
                            }
                            Button("Branch from card") { relatedFromCurrent(continuation: false) }.fixedSize().help("Create a linked branch from the current card")
                        }
                    }
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: EditorHeaderHeightKey.self, value: proxy.size.height)
                    })
                    }
                    .frame(height: min(editorHeaderHeight, max(0, editorGeometry.size.height - 130)))
                    .overlay(alignment: .bottomTrailing) {
                        if editorHeaderHeight > max(0, editorGeometry.size.height - 130) {
                            Text("Scroll for more controls ↓").font(.caption2).padding(4)
                                .background(.regularMaterial).allowsHitTesting(false)
                        }
                    }
                    .onPreferenceChange(EditorHeaderHeightKey.self) { editorHeaderHeight = $0 }
                    if cardMode == "habits" {
                        HabitTrackerEditor(tracker: Binding(get: { tracker }, set: { setTracker($0) }))
                    } else if cardMode == "todos" {
                        TodoListEditor(list: Binding(get: { todo }, set: { setTodo($0) }))
                    } else if cardMode == "outline" {
                        OutlineEditor(outline: Binding(get: { outline }, set: { setOutline($0) }), onRequestLink: { completion in
                            outlineLinkCompletion = completion; showOutlineNotes = true
                        })
                    } else {
                    VStack(spacing: 0) {
                        AdaptiveFormattingToolbar(editor: editor, onLinkNote: { showNotes = true }, onZotero: { showZotero = true })
                        Divider()
                        MarkdownEditor(text: $text, editor: editor, onFollowLink: followLink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.16)))
                    }
                }
                }.frame(minWidth: 280)
                }, preview: {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Preview").fontWeight(.semibold)
                        Spacer()
                        let count = pageCount
                        Text("\(count) \(count == 1 ? "card" : "cards")").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Picker("Orientation", selection: $portrait) {
                            Text("Landscape · 5 × 3").tag(false)
                            Text("Portrait · 3 × 5").tag(true)
                        }.labelsHidden().frame(maxWidth: 190)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text("Text size").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $fontSize, in: 7...18, step: 1).help("Text size")
                        Text("\(Int(fontSize)) pt").font(.caption).monospacedDigit().frame(width: 38, alignment: .trailing)
                    }
                    let previewData = previewPDF
                    PDFPreview(data: previewData, revision: previewRevision, onFollowLink: followLink)
                        .border(Color.secondary.opacity(0.2)).help("Click an underlined link to open it.")
                        .allowsHitTesting(previewData != nil)
                        .overlay(alignment: .top) {
                            if previewData == nil {
                                Text("Preview unavailable; the last valid card may be shown. Check the card before printing.")
                                    .font(.caption).padding(8).frame(maxWidth: .infinity)
                                    .background(.regularMaterial).allowsHitTesting(false)
                            }
                        }
                    Text("3 × 5 in · ⅜ in inset · Print at 100% scale")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 230)
                })
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(status).font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 18).frame(minWidth: 850, minHeight: 600)
        .background(AppearancePreference.background(for: storedAppearance))
        .accentColor(AppearancePreference.accent(for: storedAppearance))
        .tint(AppearancePreference.tint(for: storedAppearance))
        .preferredColorScheme(AppearancePreference.colorScheme(for: storedAppearance))
        .onAppear {
            if storedIDMode.isEmpty { storedIDMode = (autoTimestampID ? IDMode.timestamp : IDMode.titleOnly).rawValue }
            if let data = habitDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(HabitTracker.self, from: data) { tracker = saved }
            if let data = todoDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(TodoList.self, from: data) { todo = saved }
            if let data = outlineDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(OutlineDocument.self, from: data) { outline = saved }
        }
        .onChange(of: text) { _ in if cardMode == "markdown" { scheduleAutosave() } }
        .onChange(of: habitDraft) { _ in if cardMode == "habits" { scheduleAutosave() } }
        .onChange(of: todoDraft) { _ in if cardMode == "todos" { scheduleAutosave() } }
        .onChange(of: outlineDraft) { _ in if cardMode == "outline" { scheduleAutosave() } }
        .onDisappear { _ = flushExistingDraft(automatic: true); graphWindow.close() }
        .onReceive(EditorWindowCoordinator.shared.$pendingURL) { incomingURL in
            guard let url = incomingURL else { return }
            if let clip = ResearchClip.from(url) { research = clip }
            else { status = "Could not open that clip." }
            // Published values are delivered before assignment completes.
            DispatchQueue.main.async {
                if EditorWindowCoordinator.shared.pendingURL == url {
                    EditorWindowCoordinator.shared.pendingURL = nil
                }
            }
        }
        .sheet(item: $research) { clip in
            ResearchEditor(clip: clip) { content, append in
                useResearch(content, append: append)
            }
        }
        .sheet(isPresented: $showNotes) {
            NotePicker { link in editor.insert(link); status = "Note link inserted." }
        }
        .sheet(isPresented: $showOutlineNotes, onDismiss: { outlineLinkCompletion = nil }) {
            NotePicker { link in let completion = outlineLinkCompletion; outlineLinkCompletion = nil; completion?(link); status = "Note link inserted." }
        }
        .sheet(isPresented: $showLibrary) {
            CardLibrary(currentURL: fileURL, allowInsert: cardMode == "markdown", onOpen: { url in loadFile(url) }, onInsert: { link in editor.insert(link); status = "Note link inserted." })
        }
        .sheet(isPresented: $showSettings) { WorkflowSettings() }
        .sheet(isPresented: $showZotero) {
            ZoteroPicker { source in
                let separator = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                text += separator + source + "\n"
                status = "Zotero source added."
            }
        }
    }
    func chooseNotesFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { notesFolder = url.path; status = "ID and notes folder: \(url.path)" }
    }
    func showGraph() {
        let editorWindow = NSApplication.shared.keyWindow
        graphWindow.show(currentURL: fileURL) { [weak editorWindow] url in
            guard let editorWindow else { return }
            guard research == nil && !showNotes && !showOutlineNotes && !showLibrary && !showDebateBrowser && !showSettings && !showZotero else {
                graphError("Finish the open dialog before opening a card from the graph.")
                return
            }
            let folderPath = notesFolder.isEmpty ? saveFolder : notesFolder
            guard !folderPath.isEmpty, CardGraph.canOpen(url, in: URL(fileURLWithPath: folderPath, isDirectory: true)) else {
                graphError("This card is no longer available in the selected notes folder. Refresh the graph.")
                return
            }
            if loadFile(url) { editorWindow.makeKeyAndOrderFront(nil) }
        }
    }
    func graphError(_ message: String) {
        status = message
        let alert = NSAlert(); alert.messageText = "Can't open card"; alert.informativeText = message; alert.addButton(withTitle: "OK"); alert.runModal()
    }
    func followLink(_ target: CardLinkTarget) {
        let configuredFolder = notesFolder.isEmpty ? saveFolder : notesFolder
        let folderPath = configuredFolder.isEmpty && showDebate ? (fileURL?.deletingLastPathComponent().path ?? "") : configuredFolder
        let folder = folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath, isDirectory: true)
        let sourceFile = fileURL
        let sourceMode = cardMode
        guard sourceMode == "markdown" || sourceMode == "outline" else { return }
        let sourceText = currentDraftContents()
        let requestID = UUID(); linkRequestID = requestID
        status = "Opening link…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CardLinkNavigation.resolve(target, folder: folder, currentFile: sourceFile)
            DispatchQueue.main.async {
                let currentFolder = notesFolder.isEmpty ? saveFolder : notesFolder
                let activeFolder = currentFolder.isEmpty && showDebate ? (fileURL?.deletingLastPathComponent().path ?? "") : currentFolder
                guard requestID == linkRequestID, cardMode == sourceMode, !showDebateBrowser, fileURL == sourceFile,
                      activeFolder == folderPath else { return }
                guard Data(currentDraftContents().utf8) == Data(sourceText.utf8) else { status = "Link not opened because the card changed."; return }
                switch result {
                case .failure(let message): linkError(message)
                case .external(let url):
                    if NSWorkspace.shared.open(url) { status = "Opened link." }
                    else { linkError("Could not open this link.") }
                case .current(let fragment):
                    guard cardMode == "markdown" else { linkError("Heading links are not available in the outline editor."); return }
                    showHeading(fragment)
                case .note(let url, let fragment):
                    if sourceFile?.standardizedFileURL != url.standardizedFileURL {
                        editor.clearPendingSelection()
                        guard loadFile(url) else { return }
                    }
                    if let fragment {
                        guard cardMode == "markdown" else { linkError("Heading links are available in Research notes."); return }
                        showHeading(fragment)
                    }
                    else { status = "Opened \(url.lastPathComponent)." }
                }
            }
        }
    }
    func showHeading(_ fragment: String) {
        guard let range = CardLinkNavigation.headingRange(fragment, in: text) else { linkError("The linked heading was not found."); return }
        editor.selectWhenReady(range: range, text: text)
        status = "Opened heading: \(fragment)."
    }
    func linkError(_ message: String) {
        status = message
        let alert = NSAlert(); alert.messageText = "Can't open link"; alert.informativeText = message; alert.addButton(withTitle: "OK"); alert.runModal()
    }
    func scanRoots(for file: URL? = nil) -> [URL] {
        var roots: [URL] = []
        if !notesFolder.isEmpty { roots.append(URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL) }
        let fallback = file?.deletingLastPathComponent() ?? (!saveFolder.isEmpty ? URL(fileURLWithPath: saveFolder, isDirectory: true) : nil)
        if let folder = fallback?.standardizedFileURL,
           !roots.contains(where: { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") }) { roots.append(folder) }
        return roots
    }
    func selectIDMode(_ mode: IDMode) {
        guard mode != idMode else { return }
        let currentID = CardMetadata.parse(text).id
        let debate = DebateNotes.parse(text)
        let isDebateCard = showDebate || debate.role != nil || debate.primary != nil || !debate.projects.isEmpty || !debate.related.isEmpty
        if mode == .luhmann && cardMode == "markdown" && !isDebateCard && fileURL == nil {
            guard currentID != nil || !CardMetadata.hasNonemptyID(text) else {
                status = "Fix existing card_id metadata before changing ID style."
                return
            }
            let roots = scanRoots(for: fileURL)
            guard currentID == nil || !roots.isEmpty else {
                status = "Choose a notes or save folder before changing the card ID."
                let alert = NSAlert(); alert.messageText = "Can't check card IDs"; alert.informativeText = status; alert.runModal()
                return
            }
            do {
                let existing = try BranchIDs.existing(in: roots)
                guard let proposedID = CardIDs.newID(mode: .luhmann, existing: existing),
                      let updated = NoteEditing.setID(proposedID, in: text),
                      CardMetadata.parse(updated).id == proposedID else {
                    status = "Could not prepare a Luhmann ID. Check the card metadata."
                    return
                }
                if let currentID, proposedID != currentID {
                    let alert = NSAlert()
                    alert.messageText = "Replace the current card ID?"
                    alert.informativeText = "Current ID: \(currentID)\nSuggested Luhmann ID: \(proposedID)\n\nThis changes only the current unsaved draft."
                    alert.addButton(withTitle: "Replace ID")
                    alert.addButton(withTitle: "Keep Current ID")
                    guard alert.runModal() == .alertFirstButtonReturn else {
                        status = "Kept the current card ID and ID style."
                        return
                    }
                }
                text = updated; storedIDMode = mode.rawValue
                status = "Luhmann ID added: \(proposedID)."
            } catch {
                status = "Could not check card IDs: \(error.localizedDescription)"
                let alert = NSAlert(); alert.messageText = "Can't check card IDs"; alert.informativeText = status; alert.runModal()
            }
            return
        }
        let previousStoredMode = storedIDMode
        storedIDMode = mode.rawValue
        if mode != .titleOnly && currentID == nil {
            if !ensureID() { storedIDMode = previousStoredMode }
        }
        else if mode == .luhmann && isDebateCard && currentID != nil { status = "Debate cards keep their existing IDs." }
        else if mode == .luhmann && fileURL != nil && currentID != nil { status = "Luhmann style selected; the saved card ID was kept." }
    }
    @discardableResult func ensureID() -> Bool {
        if idMode == .titleOnly { return true }
        if CardMetadata.parse(text).id != nil { return true }
        if CardMetadata.hasNonemptyID(text) { status = "Fix existing card_id metadata before adding an ID."; return false }
        if let file = fileURL, let existingID = (BranchIDs.filenameID(for: file) ?? (idMode == .luhmann ? BranchIDs.luhmannFilenameID(for: file) : nil)) {
            guard let updated = NoteEditing.addID(existingID, to: text) else { status = "Could not add ID to the existing metadata."; return false }
            text = updated; status = "Kept the existing filename ID: \(existingID)."; return true
        }
        do {
            let existing = try BranchIDs.existing(in: scanRoots(for: fileURL))
            guard let id = CardIDs.newID(mode: idMode, existing: existing, timestampStyle: TimestampDateStyle(rawValue: timestampDateStyle) ?? .sortable, timestampIncludeTime: timestampIncludeTime) else { return true }
            guard let updated = NoteEditing.addID(id, to: text) else { status = "Could not add ID to the existing metadata."; return false }
            text = updated; status = "Card ID added: \(id)."; return true
        } catch { status = "Could not check existing IDs: \(error.localizedDescription)"; return false }
    }
    func insertTemplate(_ template: InlineTemplate) {
        switchMode(to: "markdown")
        let originalLength = (text as NSString).length
        let originalOffset = editor.view?.selectedRange().location ?? originalLength
        if template == .index {
            guard let marked = IndexCardMetadata.marking(text) else { status = "Could not mark this card as an index. Check its frontmatter."; return }
            text = marked
        }
        if idMode != .titleOnly && !ensureID() { return }
        let offset = max(0, originalOffset + (text as NSString).length - originalLength)
        let result = template.inserting(in: text, at: offset)
        text = result.text; status = "\(template.rawValue) template inserted."
        DispatchQueue.main.async {
            guard let view = editor.view else { return }
            view.setSelectedRange(NSRange(location: min(result.cursor, (view.string as NSString).length), length: 0))
            view.window?.makeFirstResponder(view)
        }
    }
    func markIndexCard() {
        guard let marked = IndexCardMetadata.marking(text) else { status = "Could not mark this card as an index. Check its frontmatter."; return }
        text = marked
        status = "Marked as an index card. Save to update the library."
    }
    func ideaFromCurrent() {
        if fileURL == nil {
            let alert = NSAlert(); alert.messageText = "Save this card before creating an idea?"
            alert.informativeText = "The new idea links to the saved card."
            alert.addButton(withTitle: "Save…"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn, saveMarkdown() else { return }
        } else if !flushExistingDraft() { return }
        guard let parentURL = fileURL else { return }
        let root = notesFolder.isEmpty ? nil : URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL.path
        let path = parentURL.deletingPathExtension().standardizedFileURL.path
        let link = root != nil && path.hasPrefix(root! + "/") ? String(path.dropFirst(root!.count + 1)) : parentURL.deletingPathExtension().lastPathComponent
        guard CardifyNote(path: link).canLink else { status = "The saved card's filename cannot be used in an Obsidian link."; return }
        do {
            let newID: String?
            if idMode == .titleOnly { newID = nil }
            else { newID = CardIDs.newID(mode: idMode, existing: try BranchIDs.existing(in: scanRoots(for: parentURL)), timestampStyle: TimestampDateStyle(rawValue: timestampDateStyle) ?? .sortable, timestampIncludeTime: timestampIncludeTime) }
            editor.discardUndoHistory()
            text = CardMetadata.frontmatter(newID ?? "") + "# Idea\n\n\n\n## Related cards\n\n- [[\(link)]] — develops this card.\n"
            branchSaveFolder = parentURL.deletingLastPathComponent(); fileURL = nil; savedMarkdownSnapshot = nil; history.detach()
            status = "New idea created. Save it when ready."
        } catch { status = "Could not create an idea: \(error.localizedDescription)" }
    }
    func relatedFromCurrent(continuation: Bool) {
        if CardMetadata.parse(text).id == nil && idMode != .titleOnly && !ensureID() { return }
        guard let parentID = CardMetadata.parse(text).id ?? fileURL.flatMap({ BranchIDs.filenameID(for: $0) }) else {
            status = "Add a card ID before branching."; return
        }
        if fileURL == nil {
            let alert = NSAlert(); alert.messageText = "Save this card before branching?"
            alert.informativeText = "The new card links to the saved parent, so save your current changes first."
            alert.addButton(withTitle: "Save…"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn, saveMarkdown() else { return }
        } else if !flushExistingDraft() { return }
        guard let parentURL = fileURL else { return }
        do {
            let existing = try BranchIDs.existing(in: scanRoots(for: parentURL))
            let childID = try (continuation ? CardIDs.continuation(from: parentID, existing: existing) : CardIDs.branch(from: parentID, existing: existing))
            let root = notesFolder.isEmpty ? nil : URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL.path
            let path = parentURL.deletingPathExtension().standardizedFileURL.path
            let link = root != nil && path.hasPrefix(root! + "/") ? String(path.dropFirst(root!.count + 1)) : parentURL.deletingPathExtension().lastPathComponent
            guard !link.contains(where: { "[]|#^\n\r".contains($0) }) else { status = "The parent filename cannot be used in an Obsidian link."; return }
            let relation = continuation ? "continues this card" : "branches from this card"
            editor.discardUndoHistory()
            text = CardMetadata.frontmatter(childID) + "# \n\nRelated: [[\(link)]] — \(relation).\n"
            branchSaveFolder = parentURL.deletingLastPathComponent(); fileURL = nil; savedMarkdownSnapshot = nil; history.detach()
            status = "\(continuation ? "Continuation" : "Branch") \(childID) created. The parent is unchanged."
        } catch { status = "Could not create branch: \(error.localizedDescription)" }
    }
    var pageCount: Int { activePDF.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0 }
    // Check the active draft before any action that replaces it.
    func confirmReplaceDraft(hidden: Bool = false) -> Bool {
        var discarded: [String] = []
        return confirmReplaceDrafts([cardMode], hidden: hidden, discarded: &discarded)
    }
    func currentDraftContents() -> String {
        cardMode == "habits" ? tracker.markdown : cardMode == "todos" ? todo.markdown : cardMode == "outline" ? outline.markdown : text
    }
    func currentDraftSnapshot() -> String? {
        cardMode == "habits" ? savedHabitSnapshot : cardMode == "todos" ? savedTodoSnapshot : cardMode == "outline" ? savedOutlineSnapshot : savedMarkdownSnapshot
    }
    func currentDraftInitial() -> String {
        cardMode == "habits" ? HabitTracker().markdown : cardMode == "todos" ? TodoList().markdown : cardMode == "outline" ? OutlineDocument().markdown : ""
    }
    func flushExistingDraft(automatic: Bool = false) -> Bool {
        guard fileURL != nil else { return true }
        guard Data(currentDraftContents().utf8) != Data((currentDraftSnapshot() ?? currentDraftInitial()).utf8) else { return true }
        return automatic ? saveMarkdown(automatic: true) : saveMarkdown()
    }
    // When opening a different card type, both drafts can be unsaved. Ask
    // once and apply the same Save/Discard/Cancel choice to both.
    func confirmReplaceDrafts(_ modes: [String], hidden: Bool = false, discarded: inout [String]) -> Bool {
        discarded = []
        let originalMode = cardMode
        defer { cardMode = originalMode }
        var unique: [String] = []
        for mode in modes where !unique.contains(mode) { unique.append(mode) }
        var unsaved: [String] = []
        for mode in unique {
            cardMode = mode
            let baseline = currentDraftSnapshot().map { Data($0.utf8) } ?? newDraftBaselines[mode] ?? Data(currentDraftInitial().utf8)
            guard Data(currentDraftContents().utf8) != baseline else { continue }
            if fileURL != nil {
                let wasSuppressed = suppressHistorySave
                if mode != originalMode { suppressHistorySave = true }
                let ok = saveMarkdown()
                suppressHistorySave = wasSuppressed
                guard ok else { return false }
            } else { unsaved.append(mode) }
        }
        guard !unsaved.isEmpty else { return true }
        let alert = NSAlert()
        if unsaved.count == 1 {
            let kind = unsaved[0] == "habits" ? "habit" : unsaved[0] == "todos" ? "to-do" : unsaved[0] == "outline" ? "outline" : "research"
            alert.messageText = "Save changes to your \(kind) draft?"
            alert.informativeText = hidden ? "The existing \(kind) draft will be replaced." : "Your current draft will be replaced or left behind."
        } else {
            alert.messageText = "Save changes to your drafts?"
            alert.informativeText = "There are \(unsaved.count) unsaved drafts involved. Save or discard them before opening this card."
        }
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for mode in unsaved {
                cardMode = mode
                let wasSuppressed = suppressHistorySave
                if mode != originalMode || hidden { suppressHistorySave = true }
                let ok = saveMarkdown()
                suppressHistorySave = wasSuppressed
                guard ok else { return false }
            }
            return true
        case .alertSecondButtonReturn: discarded = unsaved; return true
        default: return false
        }
    }
    func clearDiscardedDraft(_ mode: String) {
        let previousMode = cardMode
        cardMode = mode
        if mode == "habits" { setTracker(HabitTracker()); savedHabitSnapshot = nil }
        else if mode == "todos" { setTodo(TodoList()); savedTodoSnapshot = nil }
        else if mode == "outline" { setOutline(OutlineDocument()); savedOutlineSnapshot = nil }
        else { editor.discardUndoHistory(); text = ""; savedMarkdownSnapshot = nil }
        fileURL = nil; branchSaveFolder = nil
        cardMode = previousMode
    }
    func useResearch(_ content: String, append: Bool) -> Bool {
        let originalMode = cardMode
        let changingMode = originalMode != "markdown"
        var discarded: [String] = []
        if changingMode {
            let modes = append ? [originalMode] : [originalMode, "markdown"]
            guard confirmReplaceDrafts(modes, discarded: &discarded) else { return false }
        } else if !append {
            guard confirmReplaceDrafts(["markdown"], discarded: &discarded) else { return false }
        }
        for mode in discarded where mode != "markdown" { clearDiscardedDraft(mode) }
        cardMode = "markdown"
        if append { text += (text.isEmpty ? "" : "\n\n") + content }
        else { editor.discardUndoHistory(); text = content; fileURL = nil; branchSaveFolder = nil; savedMarkdownSnapshot = nil }
        if !append { history.detach() }
        else if changingMode { if let fileURL { history.visit(fileURL) } else { history.detach() } }
        status = "Research card ready."
        return true
    }
    func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { loadFile(url) }
    }
    func navigateHistory(back: Bool) {
        guard let target = back ? history.backTarget : history.forwardTarget else { return }
        traversingHistory = true
        let opened = loadFile(target)
        traversingHistory = false
        guard opened else { return }
        let committed = back ? history.commitBack(to: target) : history.commitForward(to: target)
        if !committed { history.visit(target) }
    }
    @discardableResult
    func loadFile(_ url: URL, validating validate: (() -> Bool)? = nil) -> Bool {
        func targetIsSafe() -> Bool {
            guard validate?() ?? true else {
                status = "This note is no longer safely available. Refresh the sidebar and try again."
                return false
            }
            return true
        }
        let originalMode = cardMode
        do {
            guard targetIsSafe() else { return false }
            let initial = try decodeMarkdown(Data(contentsOf: url))
            let initialOutline = OutlineDocument.fromMarkdown(initial)
            let initialHabit = initialOutline == nil ? HabitTracker.fromMarkdown(initial) : nil
            let initialTodo = initialOutline == nil && initialHabit == nil ? TodoList.fromMarkdown(initial) : nil
            let targetMode = initialOutline != nil ? "outline" : initialHabit != nil ? "habits" : initialTodo != nil ? "todos" : "markdown"
            var discarded: [String] = []
            let modes = targetMode == originalMode ? [originalMode] : [originalMode, targetMode]
            guard confirmReplaceDrafts(modes, discarded: &discarded) else { return false }
            guard targetIsSafe() else { return false }
            let diskData = try Data(contentsOf: url)
            let contents = try decodeMarkdown(diskData)
            let savedOutline = OutlineDocument.fromMarkdown(contents)
            let savedHabit = savedOutline == nil ? HabitTracker.fromMarkdown(contents) : nil
            let savedTodo = savedOutline == nil && savedHabit == nil ? TodoList.fromMarkdown(contents) : nil
            let finalMode = savedOutline != nil ? "outline" : savedHabit != nil ? "habits" : savedTodo != nil ? "todos" : "markdown"
            guard finalMode == targetMode else { status = "The card changed while opening. Try again."; return false }
            for mode in discarded where mode != finalMode { clearDiscardedDraft(mode) }
            cardMode = finalMode
            if let savedOutline {
                setOutline(savedOutline); savedOutlineSnapshot = savedOutline.markdown
            } else if let savedHabit {
                setTracker(savedHabit); savedHabitSnapshot = savedHabit.markdown
            } else if let savedTodo {
                setTodo(savedTodo); savedTodoSnapshot = savedTodo.markdown
            } else { editor.discardUndoHistory(); text = contents; savedMarkdownSnapshot = contents }
            fileURL = url; diskSnapshots[finalMode] = diskData; newDraftBaselines.removeValue(forKey: finalMode)
            branchSaveFolder = nil; status = "Opened \(url.lastPathComponent)."
            if !traversingHistory { history.visit(url) }
            return true
        } catch { cardMode = originalMode; status = "Could not open file: \(error.localizedDescription)"; return false }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path; status = "Default save folder: \(url.path)" }
    }
    func newCard() {
        guard confirmReplaceDraft() else { return }
        fileURL = nil; branchSaveFolder = nil; history.detach()
        if cardMode == "habits" { savedHabitSnapshot = nil; setTracker(HabitTracker()); status = "New draft." }
        else if cardMode == "todos" { savedTodoSnapshot = nil; setTodo(TodoList()); status = "New draft." }
        else if cardMode == "outline" { savedOutlineSnapshot = nil; setOutline(OutlineDocument()); status = "New draft." }
        else {
            editor.discardUndoHistory()
            savedMarkdownSnapshot = nil
            if let defaults = WorkflowPreference.defaults(for: newCardWorkflow) {
                storedIDMode = defaults.idMode.rawValue
                text = defaults.template?.markdown ?? ""
            } else { text = "" }
            if idMode != .titleOnly { _ = ensureID() } else { status = "New draft." }
        }
        newDraftBaselines[cardMode] = Data(currentDraftContents().utf8)
    }
    // A normal Save updates the note already open; Save As is the only path
    // that presents a destination panel for an existing note.
    func saveMarkdown(saveAs: Bool = false, automatic: Bool = false) -> Bool {
        autosaveTask?.cancel()
        if cardMode == "markdown" && fileURL == nil && idMode != .titleOnly && !ensureID() { return false }
        let content = cardMode == "habits" ? tracker.markdown : cardMode == "todos" ? todo.markdown : cardMode == "outline" ? outline.markdown : text
        let currentURL = fileURL
        var target: URL
        if !saveAs, let currentURL {
            target = currentURL
        } else {
            guard !automatic else { return false }
            let panel = NSSavePanel()
            if let currentURL { panel.directoryURL = currentURL.deletingLastPathComponent() }
            else if let folder = branchSaveFolder { panel.directoryURL = folder }
            else if !saveFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: saveFolder, isDirectory: true) }
            panel.allowedContentTypes = [.init(filenameExtension: "md")!]
            let debate = cardMode == "markdown" ? DebateNotes.parse(text) : nil
            let useIDInFilename = idMode != .titleOnly || debate?.role == .aff || debate?.role == .def || debate?.primary != nil
            panel.nameFieldStringValue = currentURL?.lastPathComponent ?? (cardMode == "markdown" ? NoteEditing.filename(id: useIDInFilename ? CardMetadata.parse(text).id : nil, title: NoteEditing.title(in: text)) : cardMode == "todos" ? NoteEditing.filename(id: nil, title: todo.title) : cardMode == "outline" ? NoteEditing.filename(id: CardMetadata.parse(outline.markdown).id, title: outline.title) : "Weekly Habits.md")
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }
            target = chosen
        }
        target = target.standardizedFileURL
        let sameFile = currentURL.map { $0.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL } ?? false
        func fail(_ message: String) -> Bool {
            status = automatic ? "Autosave paused: " + message : message
            if !automatic {
                let alert = NSAlert(); alert.messageText = "Could not save card"; alert.informativeText = message; alert.runModal()
            }
            return false
        }
        do {
            let before = try diskContents(at: target)
            if sameFile {
                guard let expected = diskSnapshots[cardMode] else { return fail("The saved version could not be verified. Use Save As to preserve this draft.") }
                guard before == expected else { return fail("This file changed or was removed outside Cardify. Your draft is still open. Use Save As to keep a copy; if it has an ID, change the copy's ID to avoid a duplicate.") }
            }
            if CardMetadata.parse(content).id == nil && CardMetadata.hasNonemptyID(content) {
                return fail("Could not read card_id metadata. Check its formatting before saving.")
            }
            if let id = CardMetadata.parse(content).id {
                guard !id.contains(where: { $0.isNewline || ($0.isASCII && $0.isWhitespace && $0 != " ") }) else { return fail("Card IDs must be a single line.") }
                var roots = [target.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL]
                if !notesFolder.isEmpty {
                    let folder = URL(fileURLWithPath: notesFolder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                    if roots[0].path == folder.path || roots[0].path.hasPrefix(folder.path + "/") { roots = [folder] }
                    else { roots.append(folder) }
                }
                for root in roots {
                    if let duplicate = try CardIDIndex.ids(in: root, excluding: target.resolvingSymlinksInPath().standardizedFileURL).first(where: { $0.0.caseInsensitiveCompare(id) == .orderedSame }) {
                        return fail("Card ID \(id) is already used by \(duplicate.1.lastPathComponent). Change the ID before saving.")
                    }
                }
            }
            guard try diskContents(at: target) == before else { return fail("The destination changed while saving. Your draft is still open; try Save As.") }
            // Structured habit/to-do editors serialize canonical LF. Preserve an
            // imported file's existing newline style when updating its rows.
            var output = content
            if sameFile, let before, cardMode == "habits" || cardMode == "todos" {
                let original = try decodeMarkdown(before)
                let withoutCRLF = original.replacingOccurrences(of: "\r\n", with: "")
                if original.contains("\r\n") && !withoutCRLF.contains("\n") && !withoutCRLF.contains("\r") {
                    output = content.replacingOccurrences(of: "\n", with: "\r\n")
                } else if original.contains("\r") && !original.contains("\n") {
                    output = content.replacingOccurrences(of: "\n", with: "\r")
                }
            }
            let outputData = Data(output.utf8)
            if sameFile, let saved = currentDraftSnapshot(), Data(saved.utf8) == Data(content.utf8), let before {
                // No edit: don't normalize an imported file's formatting.
                fileURL = target; diskSnapshots[cardMode] = before
                status = automatic ? "Changes saved." : "Saved \(target.lastPathComponent)."
                return true
            }
            if before == nil {
                // Link a fully written temporary file into place. linkItem refuses
                // an existing destination, including one created after the panel.
                let temporary = target.deletingLastPathComponent().appendingPathComponent(".cardify-\(UUID().uuidString).tmp")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try outputData.write(to: temporary, options: .withoutOverwriting)
                try FileManager.default.linkItem(at: temporary, to: target)
            } else {
                try outputData.write(to: target, options: .atomic)
            }
            fileURL = target; diskSnapshots[cardMode] = outputData; newDraftBaselines.removeValue(forKey: cardMode)
            if cardMode == "habits" { savedHabitSnapshot = content }
            else if cardMode == "todos" { savedTodoSnapshot = content }
            else if cardMode == "outline" { savedOutlineSnapshot = content }
            else { savedMarkdownSnapshot = content }
            if !suppressHistorySave { history.saveCurrent(target) }
            branchSaveFolder = nil; sidebarRefreshToken = UUID()
            status = automatic ? "Changes saved." : "Saved \(target.lastPathComponent)."
            return true
        } catch { return fail("Could not verify or write the destination: \(error.localizedDescription)") }
    }

    // An inaccessible file is an error, not an absent destination. Never
    // follow a file symlink when deciding what may be overwritten.
    func diskContents(at url: URL) throws -> Data? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInvalidFileNameError, userInfo: [NSLocalizedDescriptionKey: "The destination is not a regular file."])
        }
        return try Data(contentsOf: url)
    }
    func decodeMarkdown(_ data: Data) throws -> String {
        let decoded = String(decoding: data, as: UTF8.self)
        guard Data(decoded.utf8) == data else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                          userInfo: [NSLocalizedDescriptionKey: "This file is not valid UTF-8 Markdown."])
        }
        return decoded
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        let mode = cardMode
        guard let target = fileURL else { return }
        let current = mode == "habits" ? tracker.markdown : mode == "todos" ? todo.markdown : mode == "outline" ? outline.markdown : text
        let saved = mode == "habits" ? savedHabitSnapshot : mode == "todos" ? savedTodoSnapshot : mode == "outline" ? savedOutlineSnapshot : savedMarkdownSnapshot
        guard let saved, Data(current.utf8) != Data(saved.utf8) else { return }
        autosaveTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
            guard !Task.isCancelled, cardMode == mode, fileURL == target else { return }
            let latest = mode == "habits" ? tracker.markdown : mode == "todos" ? todo.markdown : mode == "outline" ? outline.markdown : text
            guard Data(latest.utf8) == Data(current.utf8) else { return }
            _ = saveMarkdown(automatic: true)
        }
    }
    func exportPDF() {
        guard let data = activePDF else { status = cardMode == "habits" ? "Shorten the heading to create a PDF." : "Could not create PDF."; return }
        let panel = NSSavePanel(); if !saveFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: saveFolder, isDirectory: true) }; panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Index Card") + ".pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic); status = "Exported \(url.lastPathComponent)." }
            catch { status = "Could not export: \(error.localizedDescription)" }
        }
    }
    func printCards() {
        guard let data = activePDF, let pdf = PDFDocument(data: data) else { status = cardMode == "habits" ? "Shorten the heading to print." : "Could not prepare cards."; return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 216, height: 360)
        info.orientation = portrait ? .portrait : .landscape
        info.leftMargin = 0; info.rightMargin = 0; info.topMargin = 0; info.bottomMargin = 0
        info.horizontalPagination = .clip; info.verticalPagination = .clip
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
            status = "Could not prepare the print job."
            return
        }
        operation.run()
    }

    private var sidebarRoot: URL? {
        let folder = notesFolder.isEmpty ? saveFolder : notesFolder
        return folder.isEmpty ? nil : URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    }

    private func sidebarError(_ error: Error) {
        status = error.localizedDescription
        let alert = NSAlert(); alert.messageText = "Could not change note"; alert.informativeText = status; alert.runModal()
    }

    private func sidebarSnapshot(_ url: URL) throws -> SidebarFileActions.Snapshot {
        guard let root = sidebarRoot else { throw SidebarFileActions.ActionError.unavailable }
        return try SidebarFileActions.capture(url, root: root)
    }

    // A modal confirmation can run the event loop. Remember the exact active
    // draft and file association, and recheck both after it returns.
    private struct SidebarMutation {
        let snapshot: SidebarFileActions.Snapshot
        let activeMode: String?
        let activeDraft: Data?
    }

    private func prepareSidebarMutation(_ url: URL) throws -> SidebarMutation? {
        let active = fileURL?.standardizedFileURL == url.standardizedFileURL
        let mode = cardMode
        let otherURLs = fileURLs.filter { !active || $0.key != mode }.map(\.value)
        let before = try sidebarSnapshot(url)
        if active {
            try SidebarFileActions.validateActive(before, activeURL: fileURL, activeDiskSnapshot: diskSnapshots[mode], otherOpenURLs: otherURLs)
            guard flushExistingDraft() else { return nil }
        } else {
            try SidebarFileActions.validate(before, openURLs: otherURLs)
        }
        let snapshot = try sidebarSnapshot(url)
        if active {
            try SidebarFileActions.validateActive(snapshot, activeURL: fileURL, activeDiskSnapshot: diskSnapshots[mode], otherOpenURLs: otherURLs)
            guard let saved = currentDraftSnapshot(), Data(saved.utf8) == Data(currentDraftContents().utf8) else {
                throw SidebarFileActions.ActionError.changed
            }
        } else {
            try SidebarFileActions.validate(snapshot, openURLs: otherURLs)
        }
        return SidebarMutation(snapshot: snapshot, activeMode: active ? mode : nil,
                               activeDraft: active ? Data(currentDraftContents().utf8) : nil)
    }

    private func validateSidebarMutation(_ mutation: SidebarMutation) throws -> [URL] {
        let snapshot = mutation.snapshot
        guard sidebarRoot == snapshot.root else { throw SidebarFileActions.ActionError.unavailable }
        if let mode = mutation.activeMode {
            guard cardMode == mode, fileURL?.standardizedFileURL == snapshot.url,
                  Data(currentDraftContents().utf8) == mutation.activeDraft,
                  let saved = currentDraftSnapshot(), Data(saved.utf8) == mutation.activeDraft else {
                throw SidebarFileActions.ActionError.changed
            }
            let otherURLs = fileURLs.filter { $0.key != mode }.map(\.value)
            try SidebarFileActions.validateActive(snapshot, activeURL: fileURL, activeDiskSnapshot: diskSnapshots[mode], otherOpenURLs: otherURLs)
            return otherURLs
        }
        let openURLs = Array(fileURLs.values)
        try SidebarFileActions.validate(snapshot, openURLs: openURLs)
        return openURLs
    }

    private func revealSidebarNote(_ url: URL) {
        guard let root = sidebarRoot, CardGraph.canOpen(url, in: root) else { status = "This note is no longer available. Refresh and try again."; return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copySidebarPath(_ url: URL) {
        guard let root = sidebarRoot, CardGraph.canOpen(url, in: root) else { status = "This note is no longer available. Refresh and try again."; return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(url.path, forType: .string) { status = "Copied note path." }
        else { status = "Could not copy the note path." }
    }

    private func duplicateSidebarNote(_ url: URL) {
        do {
            guard let mutation = try prepareSidebarMutation(url) else { return }
            let snapshot = mutation.snapshot
            if snapshot.cardID != nil || BranchIDs.filenameID(for: url) != nil || BranchIDs.luhmannFilenameID(for: url) != nil || BranchIDs.debateFilenameID(for: url) != nil {
                let alert = NSAlert(); alert.messageText = "Duplicate without the card ID?"
                alert.informativeText = "The copy will not keep this note's ID, so the two cards do not have the same identifier. The original stays unchanged."
                alert.addButton(withTitle: "Duplicate"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            let otherOpenURLs = try validateSidebarMutation(mutation)
            let copy = try SidebarFileActions.duplicate(snapshot, openURLs: otherOpenURLs)
            sidebarRefreshToken = UUID(); status = "Created \(copy.lastPathComponent)."
        } catch { sidebarError(error) }
    }

    private func renameSidebarNote(_ url: URL) {
        do {
            guard let mutation = try prepareSidebarMutation(url) else { return }
            let field = NSTextField(string: url.lastPathComponent); field.frame.size.width = 320
            let alert = NSAlert(); alert.messageText = "Rename file"
            alert.informativeText = "This changes the filename, not the note heading. Links to the old filename may need to be updated."
            alert.accessoryView = field; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let otherURLs = try validateSidebarMutation(mutation)
            if mutation.activeMode != nil { autosaveTask?.cancel() }
            let renamed = try SidebarFileActions.rename(mutation.snapshot, filename: field.stringValue, openURLs: otherURLs)
            if mutation.activeMode != nil { fileURL = renamed; linkRequestID = UUID() }
            history.rename(url, to: renamed); sidebarRefreshToken = UUID(); status = "Renamed to \(renamed.lastPathComponent)."
        } catch { scheduleAutosave(); sidebarError(error) }
    }

    private func trashSidebarNote(_ url: URL) {
        do {
            guard let mutation = try prepareSidebarMutation(url) else { return }
            let alert = NSAlert(); alert.messageText = "Move this note to Trash?"
            alert.informativeText = "\(url.lastPathComponent) will move to the macOS Trash. Links to this note may no longer work." + (mutation.activeMode == nil ? "" : " The open note will close.")
            alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            _ = try validateSidebarMutation(mutation)
            if mutation.activeMode != nil { autosaveTask?.cancel() }
            try FileManager.default.trashItem(at: mutation.snapshot.url, resultingItemURL: nil)
            if let mode = mutation.activeMode { clearDiscardedDraft(mode); history.detach(); linkRequestID = UUID() }
            history.remove(url); sidebarRefreshToken = UUID(); status = "Moved \(url.lastPathComponent) to Trash."
        } catch { scheduleAutosave(); sidebarError(error) }
    }
}

// WindowGroup preserves macOS URL routing and reopening behavior, but the editor's
// persisted draft is shared. Only mount one editor so its file destination cannot
// diverge from a second window displaying the same draft.
@MainActor final class EditorWindowCoordinator: ObservableObject {
    static let shared = EditorWindowCoordinator()
    @Published var pendingURL: URL?
    private(set) weak var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func claim(_ candidate: NSWindow) -> Bool {
        if let window { return window === candidate }
        window = candidate
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: candidate, queue: .main) { [weak self, weak candidate] _ in
            MainActor.assumeIsolated {
                guard let self, self.window === candidate else { return }
                self.window = nil
                if let observer = self.closeObserver { NotificationCenter.default.removeObserver(observer) }
                self.closeObserver = nil
            }
        }
        return true
    }

    func showExistingWindow() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct EditorWindowProbe: NSViewRepresentable {
    var onClaim: () -> Void
    func makeNSView(context: Context) -> Probe { Probe(onClaim: onClaim) }
    func updateNSView(_ view: Probe, context: Context) { view.onClaim = onClaim }

    final class Probe: NSView {
        var onClaim: () -> Void
        init(onClaim: @escaping () -> Void) { self.onClaim = onClaim; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let coordinator = EditorWindowCoordinator.shared
            if coordinator.claim(window) {
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.window === window, coordinator.window === window else { return }
                    self.onClaim()
                }
            } else {
                DispatchQueue.main.async { [weak window] in
                    window?.close()
                    coordinator.showExistingWindow()
                }
            }
        }
    }
}

private struct EditorWindowRoot: View {
    @State private var isEditor = false
    var body: some View {
        ZStack {
            if isEditor { ContentView() }
            EditorWindowProbe { isEditor = true }.frame(width: 0, height: 0)
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            EditorWindowCoordinator.shared.pendingURL = url
            EditorWindowCoordinator.shared.showExistingWindow()
        }
    }
}

@main struct CardifyApp: App {
    var body: some Scene {
        WindowGroup { EditorWindowRoot() }
            .windowStyle(.titleBar)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
