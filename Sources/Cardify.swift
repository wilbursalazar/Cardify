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

/// The card preview: scrolling moves through the cards; ⌘+scroll zooms around the pointer.
final class PreviewZoomScrollView: NSScrollView {
    var onWheel: ((NSEvent) -> Void)?

    static func zooms(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.scrollingDeltaY != 0 && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
    }

    override func scrollWheel(with event: NSEvent) {
        guard Self.zooms(event), let onWheel else {
            super.scrollWheel(with: event)
            return
        }
        onWheel(event)
    }
}

final class StablePDFPreviewView: NSView {
    let scrollView = PreviewZoomScrollView()
    let pagesView = PreviewPagesView()
    private var displayedRevision: PDFPreviewRevision?
    private var displayedData: Data?
    private var zoom: CGFloat = 1
    /// Documents fill the pane's width and scroll; cards fit the whole page in view.
    var fitWidth = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = pagesView
        scrollView.onWheel = { [weak self] event in self?.zoom(with: event) }
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
        if !sameCard { zoom = 1 }
        pagesView.linksEnabled = false
        pagesView.document = document
        displayedData = data; displayedRevision = revision
        layoutPages(resetScroll: !sameCard)
        pagesView.needsDisplay = true
        pagesView.linksEnabled = true
    }
    func cancelPending() { pagesView.linksEnabled = false; pagesView.linkHandler = nil }

    private func zoom(with event: NSEvent) {
        guard !pagesView.pageRects.isEmpty else { return }
        let delta = max(-25, min(25, event.scrollingDeltaY))
        let factor = pow(event.hasPreciseScrollingDeltas ? 1.012 : 1.18, delta)
        let next = min(4, max(0.5, zoom * factor))
        guard next != zoom else { return }
        let clip = scrollView.contentView
        let origin = clip.bounds.origin
        let point = pagesView.convert(event.locationInWindow, from: nil)
        let offset = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let page = pagesView.pageRects.firstIndex(where: { $0.contains(point) })
        let position = page.map { index in
            let rect = pagesView.pageRects[index]
            return NSPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
        }
        zoom = next
        layoutPages()
        if let page, let position, pagesView.pageRects.indices.contains(page) {
            let rect = pagesView.pageRects[page]
            let desired = NSPoint(x: rect.minX + position.x * rect.width - offset.x,
                                  y: rect.minY + position.y * rect.height - offset.y)
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: desired, size: clip.bounds.size)).origin)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    private func layoutPages(resetScroll: Bool = false) {
        let size = scrollView.contentSize
        guard size.width > 0, size.height > 0 else { return }
        let oldOrigin = scrollView.contentView.bounds.origin
        var width = max(1, size.width - 20)
        if !fitWidth, let document = pagesView.document, document.pageCount == 1,
           let page = document.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            if bounds.height > 0 { width = min(width, max(1, size.height - 20) * bounds.width / bounds.height) }
        }
        width *= zoom
        var heights: [CGFloat] = []
        if let document = pagesView.document {
            for index in 0..<document.pageCount {
                let bounds = document.page(at: index)?.bounds(for: .mediaBox) ?? .zero
                heights.append(bounds.width > 0 ? width * bounds.height / bounds.width : 0)
            }
        }
        let totalHeight = heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * 12
        let documentWidth = max(size.width, width + 20)
        var y = fitWidth ? 10 : max(10, (size.height - totalHeight) / 2)
        pagesView.pageRects = heights.map { height in
            defer { y += height + 12 }
            return NSRect(x: (documentWidth - width) / 2, y: y, width: width, height: height)
        }
        pagesView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: max(size.height, totalHeight + 20))
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
    var fitWidth = false
    init(data: Data?, revision: PDFPreviewRevision? = nil, fitWidth: Bool = false, onFollowLink: @escaping (CardLinkTarget) -> Void) {
        self.data = data; self.revision = revision; self.fitWidth = fitWidth; self.onFollowLink = onFollowLink
    }
    func makeNSView(context: Context) -> StablePDFPreviewView { let view = StablePDFPreviewView(); view.fitWidth = fitWidth; return view }
    func updateNSView(_ view: StablePDFPreviewView, context: Context) {
        view.fitWidth = fitWidth
        view.setLinkHandler(onFollowLink)
        view.update(data: data, revision: revision)
    }
    static func dismantleNSView(_ view: StablePDFPreviewView, coordinator: ()) { view.cancelPending() }
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

struct LinkedCardTab: Identifiable {
    let id = UUID()
    var url: URL
    var content: String
    var savedContent: String = ""
    var title: String {
        let heading = NoteEditing.title(in: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? url.deletingPathExtension().lastPathComponent : heading
    }
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
    @AppStorage("showNotesSidebar") private var showNotesSidebar = true      // the card list
    @AppStorage("kasterShowLibraryPane") private var showLibraryPane = true  // smart lists, tags, folders
    @StateObject private var editor = EditorState()
    @StateObject private var library = LibraryStore()
    @StateObject private var typeset = TypesetPreview()
    @AppStorage("kasterTypesetEngine") private var typesetEngine = TypesetEngine.typst.rawValue
    @AppStorage("kasterPreviewStyle") private var previewStyle = PreviewStyle.document.rawValue
    @AppStorage("kasterLastPrint") private var lastPrintTime = 0.0
    @AppStorage("kasterLastMode") private var lastMode = KasterMode.zettel.rawValue
    @AppStorage("kasterPrintMode") private var printMode = PrintColor.black.rawValue
    @AppStorage("kasterThemes") private var themesEnabled = false
    @AppStorage(AppearancePreference.accentKey) private var accentHex = ""
    @AppStorage("kasterArtifactFolder.habits") private var habitsFolder = ""
    @AppStorage("kasterArtifactFolder.todos") private var todosFolder = ""
    @AppStorage("kasterArtifactFolder.debates") private var debatesFolder = ""
    @State private var kasterMode: KasterMode = .zettel
    @State private var renameTask: Task<Void, Never>?
    @State private var showMigration = false
    @State private var newCardFolder: URL?
    // Which file each editor mode had open, so a relaunch reconnects instead of treating
    // the restored draft as a brand-new card (which then collides with its own Card ID).
    @AppStorage("kasterOpenFiles") private var openFilesStore = ""
    @AppStorage("kasterEditorMode") private var editorMode = KasterEditorMode.live.rawValue
    @State private var openTabs: [URL] = []
    @AppStorage("kasterLayoutMigrated") private var kasterLayoutMigrated = false
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
    @State private var showRegister = false
    @State private var showBibliography = false
    @State private var showNotes = false
    @State private var showOutlineNotes = false
    @State private var outlineLinkCompletion: ((String) -> Void)?
    @State private var showLibrary = false
    @State private var showDebate = false
    @State private var showDebateBrowser = false
    @State private var showSettings = false
    @State private var linkRequestID = UUID()
    @State private var linkedTabs: [LinkedCardTab] = []
    @State private var selectedLinkedTab: UUID?
    @State private var sideTab: UUID?
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
    var activeLinkedTab: LinkedCardTab? { linkedTabs.first(where: { $0.id == selectedLinkedTab }) }
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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { showLibraryPane.toggle() } label: { Image(systemName: "sidebar.left") }
                    .keyboardShortcut("1", modifiers: [.control, .command])
                    .help(showLibraryPane ? "Hide the Library: lists, tags and folders (⌃⌘1)" : "Show the Library: lists, tags and folders (⌃⌘1)")
                    .accessibilityLabel(showLibraryPane ? "Hide Library" : "Show Library")
                Button { showNotesSidebar.toggle() } label: { Image(systemName: "list.bullet.rectangle") }
                    .keyboardShortcut("2", modifiers: [.control, .command])
                    .help(showNotesSidebar ? "Hide the card list (⌃⌘2)" : "Show the card list (⌃⌘2)")
                    .accessibilityLabel(showNotesSidebar ? "Hide card list" : "Show card list")
                Button(action: newCard) { EmptyView() }.keyboardShortcut("n").frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                Text("Kaster").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppearancePreference.foreground(for: storedAppearance))
                HStack(spacing: 4) {
                    Button { navigateHistory(back: true) } label: { Image(systemName: "chevron.left") }
                        .help("Back to the previous card").keyboardShortcut("[", modifiers: .command).disabled(history.backTarget == nil)
                    Button { navigateHistory(back: false) } label: { Image(systemName: "chevron.right") }
                        .help("Forward to the next visited card").keyboardShortcut("]", modifiers: .command).disabled(history.forwardTarget == nil)
                }
                Spacer(minLength: 8)
                Button { showLibrary = true } label: { Image(systemName: "magnifyingglass") }
                    .help("Library: search every card and insert links")
                Menu {
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
                    Toggle("Show Library (⌃⌘1)", isOn: $showLibraryPane)
                    Toggle("Show Card List (⌃⌘2)", isOn: $showNotesSidebar)
                } label: { Image(systemName: "rectangle.split.3x1") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Layout")
                Menu {
                    Button("New Card", action: newCard)
                    Button("Open Markdown…", action: openFile)
                    Button("Research Clipper…") { research = ResearchClip() }
                    Button("Mark as Index Card") { markIndexCard() }.disabled(cardMode != "markdown")
                    Button("Keyword Register…") { showRegister = true }.disabled(vaultRoot == nil)
                    Button("Add This Card to Register…") { if let url = fileURL { addToRegister(url) } }.disabled(fileURL == nil || cardMode != "markdown")
                    Button("New Linked Idea from Current…") { ideaFromCurrent() }.disabled(cardMode != "markdown")
                    Button("Save As…") { _ = saveMarkdown(saveAs: true) }
                    Divider()
                    Button("Export PDF…", action: exportPDF)
                    Button("Print Cards Changed Since Last Print…") { printBatch(unprintedCardURLs(), label: "changed since your last print") }
                        .disabled(notesFolder.isEmpty && saveFolder.isEmpty)
                    Divider()
                    Button("Choose Save Folder…", action: chooseFolder)
                    Button("Choose Notes Folder…", action: chooseNotesFolder)
                    Button("Organize Vault into Kaster Folders…") { if flushExistingDraft() { showMigration = true } }.disabled(vaultRoot == nil)
                    Divider()
                    Button("Settings…") { showSettings = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("File")
                Button { _ = saveMarkdown() } label: { EmptyView() }.keyboardShortcut("s").frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                Picker("Print colors", selection: $printMode) {
                    ForEach(PrintColor.allCases) { mode in
                        Label(mode.title, systemImage: mode == .black ? "circle.lefthalf.filled" : "paintpalette").tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                .help("Black only: pure black ink for everything, images in grayscale. Color: black text, purple links, color images. The preview shows what will print.")
                Button(action: savePDFBesideCard) { Label("Save PDF", systemImage: "doc.richtext").labelStyle(.titleAndIcon) }
                    .fixedSize().help("Save a PDF of this card next to its Markdown file")
                printButton
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14))
            .padding(.leading, 84).padding(.trailing, 16).frame(height: 40)
            Divider().overlay(alignment: .bottom) {
                if let focus = AppearancePreference.focusAccent(for: storedAppearance, mode: showDebate && cardMode == "markdown" ? "debate" : cardMode) {
                    Rectangle().fill(focus.opacity(0.75)).frame(height: 2)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                if showNotesSidebar || showLibraryPane {
                    CardSidebar(store: library, currentURL: fileURL, openURLs: Array(fileURLs.values), draftTitle: currentCardTitle, draftID: cardMode == "markdown" ? CardMetadata.parse(text).id : cardMode == "outline" ? CardMetadata.parse(outline.markdown).id : nil,
                                notesFolder: notesFolder, saveFolder: saveFolder,
                                refreshToken: sidebarRefreshToken, onOpen: { url in
                                    let folder = notesFolder.isEmpty ? saveFolder : notesFolder
                                    guard !folder.isEmpty else { status = "Choose a notes folder before opening a sidebar note."; return false }
                                    let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                                    return loadFile(url, validating: { CardGraph.canOpen(url, in: root) })
                                }, onOpenParallel: { url in openLinkedTab(url) }, onReveal: revealSidebarNote, onDuplicate: duplicateSidebarNote,
                                onRename: renameSidebarNote, onTrash: trashSidebarNote,
                                onCopyPath: copySidebarPath, onMove: { url, destination in moveSidebarItem(url, to: destination) }, onNew: newCard, onChooseFolder: chooseNotesFolder,
                                onSettings: { showSettings = true },
                                onPrint: { urls, label in printBatch(urls, label: label) },
                                lastPrint: Date(timeIntervalSince1970: lastPrintTime),
                                onNewFolder: createFolder, onRenameFolder: renameFolder,
                                onNewCardIn: newCardHere, onNewFolderInFinder: makeFolderInFinder, onReorder: saveManualOrder,
                                onOpenRegister: { showRegister = true }, onOpenBibliography: { showBibliography = true },
                                onAddToRegister: { url in addToRegister(url) },
                                showLibrary: showLibraryPane, showList: showNotesSidebar)
                }
                WorkspaceSplitView(arrangement: WorkspaceArrangement.stored(storedWorkspaceArrangement), editor: {
                HStack(spacing: 0) {
                VStack(spacing: 0) {
                EditorTabBar(tabs: editorTabs, currentID: fileURL.map(KasterPathList.key) ?? "draft",
                             onSelect: { tab in if let url = tab.url { _ = loadFile(url) } },
                             onClose: closeTab, onNew: newCard)
                Divider()
                if cardMode == "markdown" {
                    KasterFormatBar(editor: editor, mode: $editorMode, onLinkNote: { showNotes = true }, onZotero: { showZotero = true })
                    Divider()
                }
                GeometryReader { editorGeometry in
                VStack(alignment: .leading) {
                    ScrollView(.vertical) {
                    VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        cardTypeControls
                    }
                    .controlSize(.small)
                    sourceChips
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
                    if showDebate {
                    HStack {
                        TextField(titlePlaceholder, text: Binding(get: { NoteEditing.title(in: text) }, set: { text = NoteEditing.setTitle($0, in: text) }))
                            .textFieldStyle(.plain).font(.system(size: 17, weight: .semibold)).padding(.vertical, 6)
                        Picker("ID", selection: Binding(get: { idMode }, set: { mode in
                            selectIDMode(mode)
                        })) {
                            ForEach(IDMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }.labelsHidden().frame(width: 110).accessibilityLabel("ID style").help("AFF and DEF points use their own IDs; connected cards inherit their parent’s ID.")
                    }
                    }
                    if showDebate {
                    HStack {
                        Text("ID").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if showDebate || idMode != .titleOnly || CardMetadata.parse(text).id != nil {
                            TextField("Card ID", text: Binding(get: { CardMetadata.parse(text).id ?? "" }, set: { id in
                                if let updated = NoteEditing.setID(id, in: text) { text = updated }
                                else { status = "Could not edit card ID in the existing metadata." }
                            })).frame(width: 145).help("Edit the card ID; existing files are not automatically renamed.")
                        }
                        Spacer()
                        if idMode != .titleOnly {
                            if idMode == .luhmann {
                                Button("Continue sequence") { relatedFromCurrent(continuation: true) }.fixedSize().help("Create the next card in this sequence")
                            }
                            Button("Branch from card") { relatedFromCurrent(continuation: false) }.fixedSize().help("Create a linked branch from the current card")
                        }
                    }
                    }
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
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
                        HabitTrackerEditor(tracker: Binding(get: { tracker }, set: { setTracker($0) })).padding(.horizontal, 14)
                    } else if cardMode == "todos" {
                        TodoListEditor(list: Binding(get: { todo }, set: { setTodo($0) })).padding(.horizontal, 14)
                    } else if cardMode == "outline" {
                        OutlineEditor(outline: Binding(get: { outline }, set: { setOutline($0) }), onRequestLink: { completion in
                            outlineLinkCompletion = completion; showOutlineNotes = true
                        }).padding(.horizontal, 14)
                    } else {
                    MarkdownEditor(text: $text, editor: editor, onFollowLink: followLink, live: (KasterEditorMode(rawValue: editorMode) ?? .live) == .live,
                                   onZotero: { showZotero = true }, onEdit: { refreshTypeset() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.top, 8)
                }
                }
                .background(paneBackground)
                .clipped()
                .frame(minWidth: 320)
                if let side = linkedTabs.first(where: { $0.id == sideTab }) {
                    Divider()
                    // Bound by id, not array position: the pane saves once more as it closes,
                    // after its tab may already be gone from the list.
                    SideEditorPane(tab: sideBinding(side), tabs: linkedTabs,
                                   onSelect: { sideTab = $0 },
                                   onClose: { closeLinkedTab(side.id) },
                                   onMakeMain: { closeLinkedTab(side.id); _ = loadFile(side.url) },
                                   onFollowLink: { target in followLinkFromTab(target, source: linkedTabs.first(where: { $0.id == side.id }) ?? side) },
                                   onSaved: { library.refresh(files: linkedTabs.map(\.url), folder: libraryFolder) })
                        .frame(minWidth: 260)
                }
                }
                }, preview: {
                VStack(alignment: .leading, spacing: 0) {
                    if !linkedTabs.isEmpty {
                        // Which card the preview shows: the main card or one open beside it.
                        Picker("Preview card", selection: $selectedLinkedTab) {
                            Text("Current card: \(currentCardTitle)").tag(UUID?.none)
                            ForEach(linkedTabs) { tab in Text("Beside: \(tab.title)").tag(Optional(tab.id)) }
                        }
                        .pickerStyle(.menu).labelsHidden().padding(.horizontal, 12).padding(.vertical, 6)
                        Divider()
                    }
                    KasterInspector(store: library, markdown: activeLinkedTab?.content ?? currentDraftContents(),
                                    isMarkdownMode: cardMode == "markdown" || cardMode == "outline" || activeLinkedTab != nil,
                                    currentURL: activeLinkedTab?.url ?? fileURL, cardType: currentCardTypeName,
                                    onFollowLink: { target in
                                        if let linked = activeLinkedTab { followLinkFromTab(target, source: linked) } else { followLink(target) }
                                    },
                                    onOpen: { url in _ = loadFile(url) },
                                    documentPDF: typesetSource != nil ? typeset.documentPDF : nil,
                                    documentRevision: PDFPreviewRevision(mode: "document", content: "\(typeset.generation)", portrait: false, fontSize: 11, dotGrid: false, filePath: fileURL?.path),
                                    typesetError: typesetSource != nil ? typeset.error : nil,
                                    onPrintCard: printCards) {
                    VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("Orientation", selection: $portrait) {
                            Text("Landscape · 5 × 3").tag(false)
                            Text("Portrait · 3 × 5").tag(true)
                        }.labelsHidden().frame(maxWidth: 190)
                        Picker("Text size", selection: $fontSize) {
                            ForEach([7.0, 8, 9, 10, 11, 12, 14, 16, 18], id: \.self) { size in Text("\(Int(size)) pt").tag(size) }
                        }
                        .labelsHidden().fixedSize().help("Text size on the card")
                        Spacer(minLength: 0)
                        let count = pageCount
                        Text("\(count) \(count == 1 ? "card" : "cards")").font(.caption).foregroundStyle(.secondary)
                    }
                    let linked = activeLinkedTab
                    let previewData = currentPreviewData
                    let revision = currentPreviewRevision
                    PDFPreview(data: previewData, revision: revision, onFollowLink: { target in
                        if let linked { followLinkFromTab(target, source: linked) }
                        else { followLink(target) }
                    })
                        .border(Color.secondary.opacity(0.2)).help("Click an underlined link to open it.")
                        .allowsHitTesting(previewData != nil)
                        .overlay(alignment: .top) {
                            if typesetSource != nil, let problem = typeset.error {
                                Label(problem, systemImage: "exclamationmark.triangle")
                                    .font(.caption).lineLimit(3).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial).allowsHitTesting(false)
                            } else if previewData == nil {
                                Text("Preview unavailable; the last valid card may be shown. Check the card before printing.")
                                    .font(.caption).padding(8).frame(maxWidth: .infinity)
                                    .background(.regularMaterial).allowsHitTesting(false)
                            }
                        }
                    }
                    }
                }
                .background(paneBackground)
                .frame(minWidth: 250)
                })
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            KasterStatusBar(location: statusLocation, words: KasterText.wordCount(currentDraftContents()), status: status, autosaved: isAutosaved,
                            onOpenVault: vaultRoot.map { root in { _ = NSWorkspace.shared.open(root) } })
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1080, minHeight: 620)
        .background(AppearancePreference.backdrop(for: storedAppearance))
        .accentColor(AppearancePreference.focusAccent(for: storedAppearance, mode: showDebate && cardMode == "markdown" ? "debate" : cardMode) ?? AppearancePreference.accent(for: storedAppearance))
        .tint(AppearancePreference.focusAccent(for: storedAppearance, mode: showDebate && cardMode == "markdown" ? "debate" : cardMode) ?? AppearancePreference.tint(for: storedAppearance))
        .preferredColorScheme(AppearancePreference.colorScheme(for: storedAppearance))
        .onAppear {
            if storedIDMode.isEmpty { storedIDMode = (autoTimestampID ? IDMode.timestamp : IDMode.titleOnly).rawValue }
            ensureDefaultVault()
            reattachOpenFiles()
            rememberTab(fileURL)
            refreshTypeset()
            kasterMode = fileURL == nil ? KasterMode.stored(lastMode) : KasterMode.infer(url: fileURL, root: vaultRoot, text: text)
            if !kasterLayoutMigrated { storedWorkspaceArrangement = WorkspaceArrangement.editorLeft.rawValue; showNotesSidebar = true; kasterLayoutMigrated = true }
            if let data = habitDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(HabitTracker.self, from: data) { tracker = saved }
            if let data = todoDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(TodoList.self, from: data) { todo = saved }
            runTypingBenchmarkIfRequested()
            if let data = outlineDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(OutlineDocument.self, from: data) { outline = saved }
        }
        .onChange(of: text) { _ in if cardMode == "markdown" { scheduleAutosave() } }
        // Files changed outside Kaster: show the new text in any open card you haven't edited.
        .onChange(of: library.externalChange?.id) { _ in if let files = library.externalChange?.files { reloadOpenCards(files) } }
        .onChange(of: fileURL) { url in
            rememberOpenFile(url)
            rememberTab(url)
            if url != nil { newCardFolder = nil }
            if let url, cardMode == "markdown" {
                kasterMode = KasterMode.infer(url: url, root: vaultRoot, text: text)
                storedIDMode = kasterMode.idMode.rawValue
            }
            renameTask?.cancel()
        }
        .onChange(of: typesetRequest) { _ in refreshTypeset() }
        .onChange(of: habitDraft) { _ in if cardMode == "habits" { scheduleAutosave() } }
        .onChange(of: todoDraft) { _ in if cardMode == "todos" { scheduleAutosave() } }
        .onChange(of: outlineDraft) { _ in if cardMode == "outline" { scheduleAutosave() } }
        .onDisappear { _ = flushExistingDraft(automatic: true) }
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
        .sheet(isPresented: $showMigration) {
            if let root = vaultRoot {
                MigrationSheet(root: root, artifactFolders: artifactFoldersForMigration(root: root)) { moved in
                    clearAfterMigration(moved)
                }
            }
        }
        .sheet(isPresented: $showRegister) {
            KeywordRegisterView(entries: registerEntries, indexCardsToImport: indexCardsNotInRegister.count,
                                resolve: { library.index.resolve(link: $0)?.url },
                                onOpen: { url in _ = loadFile(url) },
                                onRemove: { link, keyword in updateRegister { KeywordRegister.removing(link, from: keyword, in: $0) } },
                                onImportIndexCards: importIndexCardsToRegister,
                                onPrint: printRegister,
                                onOpenFile: { if let root = vaultRoot { ensureRegisterFile(root); _ = loadFile(KeywordRegister.url(in: root)) } })
        }
        .sheet(isPresented: $showZotero) {
            ZoteroPicker { pick in insertFootnoteCitation(pick) }
        }
        .sheet(isPresented: $showBibliography) {
            BibliographyView(cards: library.index.cards, onOpen: { url in _ = loadFile(url) }, onPrint: printBibliography)
        }
    }
    // Luhmann-style card identity, kept on one compact row above the writing area.
    var researchIDControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { researchIDRow(labels: true) }
            HStack(spacing: 6) { researchIDRow(labels: false) }
        }
    }
    @ViewBuilder func researchIDRow(labels: Bool) -> some View {
        if kasterMode == .zettel || CardMetadata.parse(text).id != nil {
            TextField("Card ID", text: Binding(get: { CardMetadata.parse(text).id ?? "" }, set: { id in
                if let updated = NoteEditing.setID(id, in: text) { text = updated }
                else { status = "Could not edit card ID in the existing metadata." }
            })).frame(width: labels ? 120 : 80).help("Edit the card ID; existing files are not automatically renamed.")
                .accessibilityLabel("Card ID")
        }
        if kasterMode == .zettel {
            Button { relatedFromCurrent(continuation: true) } label: { if labels { Label("Continue", systemImage: "arrow.down.to.line") } else { Image(systemName: "arrow.down.to.line") } }
                .fixedSize().help("Continue: the next card at the same level (21 → 22, 21/1 → 21/2)")
        }
        if kasterMode == .zettel {
            Button { relatedFromCurrent(continuation: false) } label: { if labels { Label("Branch", systemImage: "arrow.triangle.branch") } else { Image(systemName: "arrow.triangle.branch") } }
                .fixedSize().help("Branch: one level deeper (21 → 21/1, 21/1 → 21/1a)")
        }
    }
    // MARK: Card types and the vault

    var vaultRoot: URL? {
        let folder = notesFolder.isEmpty ? saveFolder : notesFolder
        return folder.isEmpty ? nil : URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    }

    func placeCursorAfterTitleMarker() {
        let ns = text as NSString
        let marker = ns.range(of: "# ")
        guard marker.location != NSNotFound else { return }
        editor.selectWhenReady(range: NSRange(location: NSMaxRange(marker), length: 0), text: text)
    }

    /// ⌘N: a fresh card of the given type. Zettels get the next top-level Luhmann number.
    func newKasterCard(_ mode: KasterMode) {
        var discarded: [String] = []
        let modes = cardMode == "markdown" ? ["markdown"] : [cardMode, "markdown"]
        guard confirmReplaceDrafts(modes, discarded: &discarded) else { return }
        for discardedMode in discarded { clearDiscardedDraft(discardedMode) }
        cardMode = "markdown"; showDebate = false
        fileURL = nil; branchSaveFolder = nil; history.detach()
        editor.discardUndoHistory(); savedMarkdownSnapshot = nil
        kasterMode = mode; lastMode = mode.rawValue
        storedIDMode = mode.idMode.rawValue
        newCardFolder = nil
        var draft = KasterFrontmatter.ensuringUID(in: mode.template)
        if mode == .zettel {
            let existing = knownIDs(for: nil)
            let id = LuhmannIDs.nextTopLevel(existing: existing)
            if let updated = NoteEditing.addID(id, to: draft) { draft = updated }
            text = draft
            status = "New Zettel \(id). Type a title; it saves itself."
        } else {
            text = draft
            status = "New \(mode.title) card. Type a title; it saves itself."
        }
        newDraftBaselines["markdown"] = Data(text.utf8)
        placeCursorAfterTitleMarker()
    }

    /// Picking a type for the current card. Drafts just switch; saved cards move (with confirmation).
    func changeMode(_ mode: KasterMode) {
        guard mode != kasterMode else { return }
        if fileURL == nil {
            let untouched = newDraftBaselines["markdown"].map { $0 == Data(text.utf8) } ?? false
            if untouched {
                let title = NoteEditing.title(in: text)
                newKasterCard(mode)
                if !title.isEmpty { text = NoteEditing.setTitle(title, in: text) }
                return
            }
            kasterMode = mode; lastMode = mode.rawValue; storedIDMode = mode.idMode.rawValue
            if mode == .zettel, CardMetadata.parse(text).id == nil {
                let existing = knownIDs(for: nil)
                if let updated = NoteEditing.addID(LuhmannIDs.nextTopLevel(existing: existing), to: text) { text = updated }
            }
            return
        }
        relocateCurrentCard(to: mode, parentID: nil)
    }

    /// Moves the open, saved card into another type's folder (Promote), giving a Zettel its ID,
    /// renaming the file to match and updating every link to it.
    func relocateCurrentCard(to mode: KasterMode, parentID: String?, confirm: Bool = true) {
        guard cardMode == "markdown", let root = vaultRoot, let oldURL = fileURL else { return }
        guard flushExistingDraft() else { return }
        var newText = KasterFrontmatter.ensuringUID(in: text)
        var id = CardMetadata.parse(text).id
        do {
            if mode == .zettel && id == nil {
                let existing = try BranchIDs.existing(in: scanRoots(for: oldURL))
                let assigned = try parentID.map { try LuhmannIDs.branch(of: $0, existing: existing) } ?? LuhmannIDs.nextTopLevel(existing: existing)
                guard let updated = NoteEditing.addID(assigned, to: newText) else { relocationFailed("Kaster could not add an ID to this card's metadata."); return }
                newText = updated; id = assigned
            }
            // Quick cards often have their title only in the filename; carry it into a heading.
            var title = NoteEditing.title(in: newText).trimmingCharacters(in: .whitespaces)
            if title.isEmpty {
                title = KasterVault.displayTitle(for: oldURL, text: newText)
                if !title.isEmpty { newText = NoteEditing.setTitle(title, in: newText) }
            }
            guard let name = KasterVault.filename(mode: mode, id: id, title: title) else { relocationFailed("Give the card a title first: start it with a line like “# My idea”."); return }
            let folder = root.appendingPathComponent(mode.folder, isDirectory: true)
            let target = KasterVault.uniqueURL(in: folder, filename: name, excluding: oldURL)
            if confirm {
                let alert = NSAlert()
                alert.messageText = "Make this a \(mode.title) card?"
                alert.informativeText = "It moves to \(mode.folder)/\(target.lastPathComponent)" + (mode == .zettel && CardMetadata.parse(text).id == nil ? " with ID \(id ?? "")" : "") + ". Links to it are updated."
                alert.addButton(withTitle: "Move"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            try KasterVault.ensureFolder(folder)
            autosaveTask?.cancel(); renameTask?.cancel()
            if newText != text { try Data(newText.utf8).write(to: oldURL, options: .atomic) }
            if target.standardizedFileURL.path != oldURL.standardizedFileURL.path { try FileManager.default.moveItem(at: oldURL, to: target) }
            let updatedFiles = try KasterVault.updateLinks(root: root, oldURL: oldURL, newURL: target, skip: [target.resolvingSymlinksInPath().standardizedFileURL.path])
            adoptMovedCurrentCard(from: oldURL, to: target, content: newText)
            reloadOpenCards(updatedFiles)
            kasterMode = mode; storedIDMode = mode.idMode.rawValue; lastMode = mode.rawValue
            status = "Now a \(mode.title) card: \(target.lastPathComponent)" + (updatedFiles.isEmpty ? "." : "; updated links in \(updatedFiles.count) card\(updatedFiles.count == 1 ? "" : "s").")
        } catch {
            relocationFailed(error.localizedDescription)
        }
    }

    func relocationFailed(_ reason: String) {
        status = "Could not move the card: \(reason)"
        let alert = NSAlert(); alert.messageText = "Could not move the card"; alert.informativeText = reason; alert.runModal()
    }

    func createCardFromLink(_ raw: String) {
        guard let root = vaultRoot else { linkError("Choose a notes folder so Kaster knows where to create this card."); return }
        let target = String(raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let withoutFragment = String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let title = (withoutFragment as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let name = KasterVault.filename(mode: .quick, id: nil, title: title) else { linkError("This link has no card name."); return }
        do {
            let folder = root.appendingPathComponent(KasterMode.quick.folder, isDirectory: true)
            try KasterVault.ensureFolder(folder)
            let url = folder.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: url.path) else { _ = loadFile(url); return }
            guard flushExistingDraft() else { return }
            try Data(KasterFrontmatter.ensuringUID(in: "# \(title)\n\n").utf8).write(to: url, options: .withoutOverwriting)
            sidebarRefreshToken = UUID()
            if loadFile(url) { status = "Created Quick card \(name) from the link." }
        } catch { linkError("Could not create the card: \(error.localizedDescription)") }
    }

    // MARK: Folders

    func rememberOpenFile(_ url: URL?) {
        var map = (try? JSONSerialization.jsonObject(with: Data(openFilesStore.utf8))) as? [String: String] ?? [:]
        map[cardMode] = url?.path
        if let data = try? JSONSerialization.data(withJSONObject: map), let json = String(data: data, encoding: .utf8) { openFilesStore = json }
    }

    /// At launch, reconnect each restored draft to the file it came from. Unsaved edits are
    /// kept (and autosaved into that same file); a file that vanished leaves a plain draft.
    func reattachOpenFiles() {
        guard let map = (try? JSONSerialization.jsonObject(with: Data(openFilesStore.utf8))) as? [String: String] else { return }
        for (mode, path) in map where fileURLs[mode] == nil {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url), let disk = try? decodeMarkdown(data) else { continue }
            fileURLs[mode] = url
            diskSnapshots[mode] = data
            newDraftBaselines.removeValue(forKey: mode)
            switch mode {
            case "markdown": savedMarkdownSnapshot = disk
            case "outline": savedOutlineSnapshot = OutlineDocument.fromMarkdown(disk)?.markdown ?? disk
            case "habits": savedHabitSnapshot = HabitTracker.fromMarkdown(disk)?.markdown ?? disk
            case "todos": savedTodoSnapshot = TodoList.fromMarkdown(disk)?.markdown ?? disk
            default: break
            }
        }
        if fileURL != nil {
            history.visit(fileURL!)
            if Data(currentDraftContents().utf8) != Data((currentDraftSnapshot() ?? "").utf8) {
                status = "Reopened \(fileURL!.lastPathComponent) with your unsaved changes."
                scheduleAutosave()
            } else {
                status = "Reopened \(fileURL!.lastPathComponent)."
            }
        }
    }

    /// If no notes folder is set (or it no longer exists), create ~/Documents/Kaster with a
    /// folder for each card type and use it.
    func ensureDefaultVault() {
        var isDirectory = ObjCBool(false)
        let configured = notesFolder.isEmpty ? saveFolder : notesFolder
        if !configured.isEmpty, FileManager.default.fileExists(atPath: configured, isDirectory: &isDirectory), isDirectory.boolValue { return }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let vault = documents.appendingPathComponent("Kaster", isDirectory: true)
        do {
            for mode in KasterMode.creatable { try KasterVault.ensureFolder(vault.appendingPathComponent(mode.folder, isDirectory: true)) }
            notesFolder = vault.path
            if !saveFolder.isEmpty && !FileManager.default.fileExists(atPath: saveFolder) { saveFolder = vault.path }
            sidebarRefreshToken = UUID()
            status = configured.isEmpty ? "Created your slip box at ~/Documents/Kaster." : "Your notes folder was missing; Kaster now uses ~/Documents/Kaster."
        } catch {
            status = "Could not create ~/Documents/Kaster: \(error.localizedDescription)"
        }
    }

    /// Right-click "New Card Here": a card of the last-used type that saves into that folder.
    func newCardHere(_ path: String) {
        guard let root = vaultRoot else { return }
        newKasterCard(KasterMode.stored(lastMode))
        guard cardMode == "markdown", fileURL == nil else { return }
        newCardFolder = path.isEmpty ? root : root.appendingPathComponent(path, isDirectory: true)
        status = "New \(kasterMode.title) card in \(path.isEmpty ? "your notes folder" : path). Type a title; it saves itself."
    }

    /// Saves a dragged order as `order:` 10, 20, 30… in each card's frontmatter.
    func saveManualOrder(_ urls: [URL]) {
        var changed = 0
        for (index, url) in urls.enumerated() {
            let value = String((index + 1) * 10)
            if let current = fileURL, KasterPathList.key(current) == KasterPathList.key(url), cardMode == "markdown" {
                guard KasterFrontmatter.value("order", in: text) != value, let updated = KasterFrontmatter.setting("order", to: value, in: text) else { continue }
                text = updated
                _ = saveMarkdown(automatic: true)
                changed += 1
                continue
            }
            guard let content = try? String(contentsOf: url, encoding: .utf8), KasterFrontmatter.value("order", in: content) != value,
                  let updated = KasterFrontmatter.setting("order", to: value, in: content) else { continue }
            if (try? Data(updated.utf8).write(to: url, options: .atomic)) != nil { changed += 1 }
        }
        sidebarRefreshToken = UUID()
        status = changed == 0 ? "Order unchanged." : "Saved the new card order."
    }

    func askForName(_ title: String, message: String, initial: String) -> String? {
        let field = NSTextField(string: initial); field.frame.size.width = 300
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.accessoryView = field; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = KasterVault.cleanTitle(field.stringValue)
        return name.isEmpty ? nil : name
    }

    func createFolder(inside parentPath: String) {
        guard let root = vaultRoot else { return }
        guard let name = askForName("New Folder", message: parentPath.isEmpty ? "Create a folder in your notes folder." : "Create a folder inside \(parentPath).", initial: "") else { return }
        let url = root.appendingPathComponent(parentPath, isDirectory: true).appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { status = "A folder named \(name) already exists there."; return }
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); sidebarRefreshToken = UUID(); status = "Created folder \(name)." }
        catch { status = "Could not create the folder: \(error.localizedDescription)" }
    }

    /// Opens a Finder panel inside the vault (or the selected folder) where "New Folder"
    /// works as in Finder; the folder you make or pick appears in the sidebar.
    func makeFolderInFinder(inside path: String) {
        guard let root = vaultRoot else { return }
        let start = path.isEmpty ? root : root.appendingPathComponent(path, isDirectory: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        panel.prompt = "Done"
        panel.message = "Make a folder with New Folder (⇧⌘N), or pick one. Folders inside your notes folder appear in the sidebar."
        let response = panel.runModal()
        sidebarRefreshToken = UUID()
        guard response == .OK, let url = panel.url else { return }
        if let relative = KasterVault.relativePath(of: url, in: root) {
            status = relative.isEmpty ? "Notes folder selected." : "Folder ready: \(relative)."
        } else {
            status = "\(url.lastPathComponent) is outside your notes folder, so it won't appear in the sidebar."
        }
    }

    func renameFolder(_ path: String) {
        guard let root = vaultRoot else { return }
        let old = root.appendingPathComponent(path, isDirectory: true)
        guard let name = askForName("Rename Folder", message: "Cards inside keep their names; links that use the folder path are updated.", initial: old.lastPathComponent) else { return }
        relocateFolder(from: old, to: old.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true))
    }

    /// Drops in the sidebar: cards use the guarded card move; folders move with their contents.
    func moveSidebarItem(_ url: URL, to destination: URL) {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue { relocateFolder(from: url, to: destination.appendingPathComponent(url.lastPathComponent, isDirectory: true)) }
        else { moveSidebarNote(url, to: destination) }
    }

    func relocateFolder(from old: URL, to new: URL) {
        guard let root = vaultRoot else { return }
        let oldPath = old.resolvingSymlinksInPath().standardizedFileURL.path
        let newPath = new.standardizedFileURL.path
        guard oldPath != newPath else { return }
        guard !(newPath + "/").hasPrefix(oldPath + "/") else { status = "A folder can't move inside itself."; return }
        guard KasterVault.relativePath(of: old, in: root) != nil, KasterVault.relativePath(of: new, in: root) != nil else { status = "Folders can only move within your notes folder."; return }
        guard !FileManager.default.fileExists(atPath: newPath) else { status = "\(new.lastPathComponent) already exists there."; return }
        guard flushExistingDraft() else { return }
        let cards = KasterVault.markdownFiles(in: old)
        do {
            autosaveTask?.cancel(); renameTask?.cancel()
            try FileManager.default.moveItem(at: old, to: new)
            func moved(_ url: URL) -> URL? {
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard path.hasPrefix(oldPath + "/") else { return nil }
                return URL(fileURLWithPath: newPath + path.dropFirst(oldPath.count))
            }
            for card in cards { if let destination = moved(card) { try KasterVault.updateLinks(root: root, oldURL: card, newURL: destination) } }
            if let current = fileURL, let destination = moved(current) { adoptMovedCurrentCard(from: current, to: destination, content: text) }
            openTabs = openTabs.map { moved($0) ?? $0 }
            for index in linkedTabs.indices { if let destination = moved(linkedTabs[index].url) { linkedTabs[index].url = destination } }
            sidebarRefreshToken = UUID()
            status = "Moved folder to \(KasterVault.relativePath(of: new, in: root) ?? new.lastPathComponent)."
        } catch { status = "Could not move the folder: \(error.localizedDescription)" }
    }

    // MARK: Keyword register

    var registerEntries: [KeywordRegister.Entry] {
        guard let root = vaultRoot else { return [] }
        let text = (try? String(contentsOf: KeywordRegister.url(in: root), encoding: .utf8)) ?? ""
        return KeywordRegister.entries(in: text)
    }

    /// Cards marked as index cards that no keyword points to yet.
    var indexCardsNotInRegister: [LibraryCard] {
        let linked = Set(registerEntries.flatMap(\.links).compactMap { library.index.resolve(link: $0)?.path })
        return library.snapshot.cards.filter { IndexCardMetadata.isIndex($0.content) && !linked.contains($0.path) }
    }

    func ensureRegisterFile(_ root: URL) {
        let url = KeywordRegister.url(in: root)
        if !FileManager.default.fileExists(atPath: url.path) { try? Data(KeywordRegister.template.utf8).write(to: url, options: .withoutOverwriting) }
    }

    /// Rewrites Register.md, refusing if it's open with unsaved edits.
    func updateRegister(_ change: (String) -> String) {
        guard let root = vaultRoot else { status = "Choose a notes folder first."; return }
        let url = KeywordRegister.url(in: root)
        if fileURL.map({ $0.standardizedFileURL == url.standardizedFileURL }) == true, savedMarkdownSnapshot != text {
            status = "Register.md has unsaved edits; it saves in a moment, then try again."; return
        }
        let before = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let after = change(before)
        guard after != before else { return }
        do {
            try Data(after.utf8).write(to: url, options: .atomic)
            library.refresh(files: [url], folder: libraryFolder)
            reloadOpenCards([url])
        } catch { status = "Could not update the register: \(error.localizedDescription)" }
    }

    func addToRegister(_ url: URL) {
        guard let card = library.card(for: url) else { status = "Save the card first, then add it to the register."; return }
        let field = NSTextField(string: KasterTypesetter.firstTag(in: card.content) ?? card.title); field.frame.size.width = 300
        let alert = NSAlert(); alert.messageText = "Add “\(card.title)” to the register"
        alert.informativeText = "Keyword for this entry card. A keyword usually points to 1–3 cards where a line of thought begins."
        alert.accessoryView = field; alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let keyword = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        let link = CardifyNote.shortestLink(for: card.path, among: library.snapshot.cards.map(\.path))
        updateRegister { KeywordRegister.adding(link, to: keyword, in: $0) }
        let count = registerEntries.first { $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame }?.links.count ?? 1
        status = "Added to “\(keyword)” in the register" + (count > KeywordRegister.suggestedLinks ? " (\(count) entries; consider a hub card)." : ".")
    }

    func importIndexCardsToRegister() {
        let cards = indexCardsNotInRegister
        let paths = library.snapshot.cards.map(\.path)
        updateRegister { text in
            cards.reduce(text) { KeywordRegister.adding(CardifyNote.shortestLink(for: $1.path, among: paths), to: $1.title, in: $0) }
        }
        status = "Added \(cards.count) index card\(cards.count == 1 ? "" : "s") to the register."
    }

    func printRegister() {
        let pages = KeywordRegister.printCards(registerEntries)
        guard !pages.isEmpty else { return }
        let cards = pages.map { KasterTypesetter.prepare($0, cardURL: nil, links: false) }
        let layout = TypesetLayout.card(portrait: portrait, fontSize: fontSize, dotGrid: dotGrid)
        guard KasterTypesetter.isAvailable(engine), case .success(let data) = KasterTypesetter.render(cards, layout: layout, engine: engine, color: PrintColor.stored(printMode)) else {
            status = "Could not typeset the register."; return
        }
        if runPrint(data) { status = "Sent \(pages.count) register card\(pages.count == 1 ? "" : "s") to the printer." }
    }

    /// After Kaster rewrote files on disk (e.g. link updates), shows the new text in any editor
    /// holding one of them without unsaved edits, so a later save doesn't see a conflict.
    func reloadOpenCards(_ files: [URL]) {
        let keys = Set(files.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        func changed(_ url: URL) -> String? {
            guard keys.contains(url.resolvingSymlinksInPath().standardizedFileURL.path),
                  let data = try? Data(contentsOf: url) else { return nil }
            let disk = String(decoding: data, as: UTF8.self)
            return Data(disk.utf8) == data ? disk : nil
        }
        if cardMode == "markdown", let current = fileURL, let saved = savedMarkdownSnapshot, saved == text,
           let disk = changed(current), disk != text {
            adoptMovedCurrentCard(from: current, to: current, content: disk)
        }
        for index in linkedTabs.indices where linkedTabs[index].content == linkedTabs[index].savedContent {
            if let disk = changed(linkedTabs[index].url), disk != linkedTabs[index].content {
                linkedTabs[index].savedContent = disk
                linkedTabs[index].content = disk
            }
        }
    }

    /// Keeps the editor, tabs and history pointed at a card whose file just moved.
    func adoptMovedCurrentCard(from oldURL: URL, to newURL: URL, content: String) {
        editor.clearPendingSelection()
        if content != text { text = content }
        savedMarkdownSnapshot = content
        diskSnapshots["markdown"] = Data(content.utf8)
        fileURL = newURL
        history.rename(oldURL, to: newURL)
        for index in linkedTabs.indices where linkedTabs[index].url.standardizedFileURL == oldURL.standardizedFileURL { linkedTabs[index].url = newURL }
        if let index = openTabs.firstIndex(where: { KasterPathList.key($0) == KasterPathList.key(oldURL) }) { openTabs[index] = newURL }
        sidebarRefreshToken = UUID()
    }

    /// Where a new card saves itself: its type's folder, named from its ID and title.
    /// Artifacts use the folder chosen for that artifact (asked once when `prompting`).
    func autoTarget(prompting: Bool) -> URL? {
        var folder: URL?
        var name: String?
        if cardMode == "markdown" && !showDebate {
            guard let root = vaultRoot else { return nil }
            if let uid = KasterFrontmatter.value("uid", in: text),
               let same = library.index.card(uid: uid) {
                return same.url
            }
            name = KasterVault.filename(mode: kasterMode, id: CardMetadata.parse(text).id, title: NoteEditing.title(in: text))
            folder = newCardFolder ?? root.appendingPathComponent(kasterMode.folder, isDirectory: true)
        } else if cardMode == "habits" || cardMode == "todos" {
            let artifact: KasterArtifact = cardMode == "habits" ? .habits : .todos
            folder = artifactFolder(artifact, prompting: prompting)
            let title = cardMode == "habits" ? tracker.title : todo.title
            name = KasterVault.filename(mode: .quick, id: nil, title: title)
        } else {
            return nil
        }
        guard let folder, let name else { return nil }
        do { try KasterVault.ensureFolder(folder) } catch { status = "Could not create \(folder.lastPathComponent): \(error.localizedDescription)"; return nil }
        return KasterVault.uniqueURL(in: folder, filename: name)
    }

    func artifactFolderPath(_ artifact: KasterArtifact) -> String {
        switch artifact {
        case .habits: return habitsFolder
        case .todos: return todosFolder
        case .debates: return debatesFolder
        }
    }

    /// Each artifact type asks once where its files live (suggesting a folder in the vault).
    func artifactFolder(_ artifact: KasterArtifact, prompting: Bool) -> URL? {
        let stored = artifactFolderPath(artifact)
        if !stored.isEmpty { return URL(fileURLWithPath: stored, isDirectory: true) }
        guard prompting else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose where \(artifact.title) files are kept. You can change this later in Settings."
        if let root = vaultRoot {
            let suggested = KasterArtifact.defaultFolder(artifact, in: root)
            try? KasterVault.ensureFolder(suggested)
            panel.directoryURL = suggested
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        switch artifact {
        case .habits: habitsFolder = url.path
        case .todos: todosFolder = url.path
        case .debates: debatesFolder = url.path
        }
        return url
    }

    func openArtifact(_ artifact: KasterArtifact) {
        switch artifact {
        case .habits: switchMode(to: "habits")
        case .todos: switchMode(to: "todos")
        case .debates:
            switchMode(to: "markdown")
            if cardMode == "markdown" { showDebate = true }
            if debatesFolder.isEmpty { _ = artifactFolder(.debates, prompting: true) }
        }
    }

    /// After a title change settles, rename the file to match and update links to it.
    func scheduleTitleRename() {
        renameTask?.cancel()
        guard cardMode == "markdown", !showDebate, let root = vaultRoot, let current = fileURL else { return }
        guard let relative = KasterVault.relativePath(of: current, in: root),
              let first = relative.split(separator: "/").first,
              let mode = KasterMode.allCases.first(where: { $0.folder.caseInsensitiveCompare(String(first)) == .orderedSame }) else { return }
        guard let expected = KasterVault.filename(mode: mode, id: CardMetadata.parse(text).id, title: NoteEditing.title(in: text)),
              expected != current.lastPathComponent else { return }
        renameTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard !Task.isCancelled, fileURL == current, let saved = savedMarkdownSnapshot, Data(saved.utf8) == Data(text.utf8) else { return }
            let target = KasterVault.uniqueURL(in: current.deletingLastPathComponent(), filename: expected, excluding: current)
            guard target.lastPathComponent != current.lastPathComponent else { return }
            do {
                try FileManager.default.moveItem(at: current, to: target)
                let updated = try KasterVault.updateLinks(root: root, oldURL: current, newURL: target, skip: [target.resolvingSymlinksInPath().standardizedFileURL.path])
                adoptMovedCurrentCard(from: current, to: target, content: text)
                reloadOpenCards(updated)
                status = "Renamed to \(target.lastPathComponent)" + (updated.isEmpty ? "." : "; updated links in \(updated.count) card\(updated.count == 1 ? "" : "s").")
            } catch {
                status = "Could not rename the file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Card-type controls

    @ViewBuilder var cardTypeControls: some View {
        if cardMode == "markdown" && !showDebate {
            // One row when it fits; the type's own controls wrap below only in a narrow window.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { modePicker(labels: true); modeSpecificControls(labels: true); Spacer(minLength: 4); artifactsMenu }
                HStack(spacing: 6) { modePicker(labels: true); modeSpecificControls(labels: false); Spacer(minLength: 4); artifactsMenu }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { modePicker(labels: true); Spacer(minLength: 4); artifactsMenu }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { modeSpecificControls(labels: true); Spacer(minLength: 0) }
                        HStack(spacing: 6) { modeSpecificControls(labels: false); Spacer(minLength: 0) }
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Label(cardMode == "habits" ? "Habit Tracker" : cardMode == "todos" ? "To-Do List" : cardMode == "outline" ? "Outline" : "Debate",
                      systemImage: cardMode == "habits" ? "checkmark.circle" : cardMode == "todos" ? "checklist" : cardMode == "outline" ? "list.bullet.indent" : "bubble.left.and.bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                Button { backToCards() } label: { Label("Back to Cards", systemImage: "chevron.left") }
                Spacer(minLength: 4)
                artifactsMenu
            }
        }
    }

    func backToCards() {
        if cardMode == "markdown" { showDebate = false } else { switchMode(to: "markdown"); if cardMode == "markdown" { showDebate = false } }
    }

    /// Card types with icons, so each kind is recognizable at a glance.
    func modePicker(labels: Bool) -> some View {
        let accent = AppearancePreference.accent(for: storedAppearance) ?? AppearancePreference.kasterPurple
        return HStack(spacing: 0) {
            ForEach(KasterMode.creatable) { mode in
                let selected = mode == kasterMode
                Button { changeMode(mode) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.systemImage).font(.system(size: 11, weight: .semibold))
                        if labels { Text(mode.title).font(.system(size: 12, weight: selected ? .semibold : .regular)) }
                    }
                    .foregroundColor(selected ? .white : .primary)
                    .padding(.horizontal, labels ? 9 : 7).padding(.vertical, 4)
                    .background(selected ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("\(mode.title): \(mode.summary)")
                .accessibilityLabel(mode.title).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }

    @ViewBuilder func modeSpecificControls(labels: Bool) -> some View {
        if themesEnabled {
            let theme = KasterTypesetter.firstTag(in: text)
            Text(theme.map { "#" + $0 } ?? "No theme")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme == nil ? .secondary : AppearancePreference.currentAccent)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background((theme == nil ? Color.secondary : AppearancePreference.currentAccent).opacity(0.12), in: Capsule())
                .help("Holiday–Greene theme: this card's first #tag")
        }
        switch kasterMode {
        case .zettel: researchIDRow(labels: labels)
        case .quick: promoteMenu
        case .research, .bibliography: EmptyView()   // Sources are in the row below.
        }
    }

    var promoteMenu: some View {
        Menu {
            Button { relocateCurrentCard(to: .zettel, parentID: nil) } label: { Label("Promote to Zettel (new top-level)", systemImage: "number") }
            let zettels = library.index.zettels
            if !zettels.isEmpty {
                Menu("Promote to Zettel, Branching From…") {
                    ForEach(zettels.prefix(200)) { card in
                        Button("\(card.cardID ?? "") \(card.title)") { relocateCurrentCard(to: .zettel, parentID: card.cardID) }
                    }
                }
            }
            Button { relocateCurrentCard(to: .research, parentID: nil) } label: { Label("Promote to Research", systemImage: "books.vertical") }
        } label: { Label("Promote", systemImage: "arrow.up.forward.circle") }
            .menuStyle(.borderlessButton).fixedSize().disabled(fileURL == nil)
            .help(fileURL == nil ? "Type a title first — the card saves itself, then it can be promoted" : "Turn this Quick card into a Zettel or Research card")
    }

    /// One chip per footnote source, under the card-type row: on Research cards always, and on
    /// any other card that cites Zotero.
    @ViewBuilder var sourceChips: some View {
        if cardMode == "markdown" && !showDebate {
            let sources = FootnoteSources.parse(text)
            let legacy = FootnoteSources.legacy(in: text)
            if kasterMode == .research || legacy != nil || sources.contains(where: { $0.zotero != nil }) {
                SourceChipsRow(sources: sources, alsoCited: { otherCardsCiting($0) }, onSetPage: setFootnotePage, onOpen: openFootnoteSource,
                               onJump: { editor.reveal($0.range) }, onRemove: removeFootnote, onOpenCard: { _ = loadFile($0) },
                               onAdd: { showZotero = true }, legacy: legacy,
                               onOpenLegacy: { if let legacy { openZoteroPage(legacy.source, page: legacy.page) } },
                               onConvertLegacy: convertLegacySource)
                    .controlSize(.small)
            }
        }
    }

    func otherCardsCiting(_ zotero: ZoteroSource) -> [LibraryCard] {
        let current = fileURL.flatMap { library.card(for: $0)?.path }
        return library.index.cards(citingZotero: zotero.key, library: zotero.library).filter { $0.path != current }
    }

    /// Applies footnote edits through the editor, so ⌘Z undoes them and the cursor stays put.
    func applyFootnoteEdits(_ edits: [FootnoteSources.Edit]) {
        guard !edits.isEmpty else { return }
        if !editor.replace(edits, expected: text) { text = FootnoteSources.apply(edits, to: text) }
    }

    /// A page typed in a chip: rewrites that footnote. A footnote without its PDF asks Zotero for
    /// it, so the page becomes a link that opens the PDF there.
    func setFootnotePage(_ source: FootnoteSource, _ page: String) {
        guard let edit = FootnoteSources.settingPage(page, label: source.label, in: text) else { return }
        applyFootnoteEdits([edit])
        status = page.isEmpty ? "Removed the page from footnote \(source.label)." : "Footnote \(source.label): page \(page)."
        guard let zotero = source.zotero, zotero.pdf == nil, ZoteroPageOpener.firstPage(page) != nil else { return }
        Task { @MainActor in
            guard let pdf = await zoteroAttachment(for: zotero),
                  let link = FootnoteSources.linkingPDF(pdf, label: source.label, key: zotero.key, in: text) else { return }
            applyFootnoteEdits([link])
        }
    }

    /// The book button: opens the cited page in Zotero's reader, or shows the item.
    func openFootnoteSource(_ source: FootnoteSource) {
        guard var zotero = source.zotero else { return }
        guard zotero.pdf == nil, let page = source.page, ZoteroPageOpener.firstPage(page) != nil else {
            openZoteroPage(zotero, page: source.page); return
        }
        Task { @MainActor in
            if let pdf = await zoteroAttachment(for: zotero) {
                zotero.pdf = pdf
                if let link = FootnoteSources.linkingPDF(pdf, label: source.label, key: zotero.key, in: text) { applyFootnoteEdits([link]) }
            }
            openZoteroPage(zotero, page: page)
        }
    }

    /// The item's PDF (or EPUB) attachment key, from the running Zotero.
    func zoteroAttachment(for zotero: ZoteroSource) async -> String? {
        var request = ZoteroSearchAPI.childrenRequest(library: zotero.zoteroLibrary, key: zotero.key)
        request.timeoutInterval = 4
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let children = try? JSONDecoder().decode([ZoteroChild].self, from: data) else { return nil }
        return ZoteroSearchAPI.readableAttachment(in: children)
    }

    /// An older Research card's Source line → a footnote on its quotation (one undoable edit).
    func convertLegacySource() {
        guard let converted = FootnoteSources.convertingLegacy(text) else { return }
        applyFootnoteEdits([(NSRange(location: 0, length: (text as NSString).length), converted.text)])
        if text == converted.text { editor.reveal(converted.marker) }
        status = "The source is now footnote \((converted.text as NSString).substring(with: converted.marker).dropFirst(2).dropLast())."
    }

    func removeFootnote(_ source: FootnoteSource) {
        applyFootnoteEdits(FootnoteSources.removing(label: source.label, in: text))
        status = "Removed footnote \(source.label)."
    }

    func printBibliography(_ entries: [String]) {
        let pages = FootnoteBibliography.printCards(entries)
        guard !pages.isEmpty else { return }
        let cards = pages.map { KasterTypesetter.prepare($0, cardURL: nil, links: false) }
        let layout = TypesetLayout.card(portrait: portrait, fontSize: fontSize, dotGrid: dotGrid)
        guard KasterTypesetter.isAvailable(engine), case .success(let data) = KasterTypesetter.render(cards, layout: layout, engine: engine, color: PrintColor.stored(printMode)) else {
            status = "Could not typeset the bibliography."; return
        }
        if runPrint(data) { status = "Sent \(pages.count) bibliography card\(pages.count == 1 ? "" : "s") to the printer." }
    }

    /// A Zotero source as a footnote: [^n] at the cursor, the citation at the bottom of the card.
    /// Both go through the text view, so one ⌘Z removes them.
    func insertFootnoteCitation(_ pick: ZoteroPick) {
        let label = ZoteroFootnote.nextLabel(in: text)
        let citation = ZoteroFootnote.citation(pick.source, page: pick.location)
        guard let view = editor.view, view.string == text else {
            text = ZoteroFootnote.inserting(pick.source, page: pick.location, into: text, at: (text as NSString).length).text
            status = "Footnote \(label) added."; return
        }
        view.undoManager?.beginUndoGrouping()
        let caret = view.selectedRange()
        view.insertText("[^\(label)]", replacementRange: NSRange(location: caret.location, length: caret.length))
        let afterMarker = view.selectedRange()
        let appendix = ZoteroFootnote.appendix(label: label, citation: citation, to: view.string)
        view.insertText(appendix, replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
        view.undoManager?.endUndoGrouping()
        view.setSelectedRange(afterMarker)
        view.scrollRangeToVisible(afterMarker)
        view.window?.makeFirstResponder(view)
        status = "Footnote \(label): " + pick.source.cite.replacingOccurrences(of: "*", with: "") + (pick.location.isEmpty ? "" : ", \(pick.location)")
    }

    func openZoteroPage(_ zotero: ZoteroSource, page: String?) {
        guard let url = ZoteroPageOpener.url(for: zotero, page: page, pdfFile: ZoteroPageOpener.localFile(for: zotero)) else { return }
        if !NSWorkspace.shared.open(url) { status = "Could not open Zotero." }
    }

    var artifactsMenu: some View {
        Menu {
            ForEach(KasterArtifact.allCases) { artifact in
                Button { openArtifact(artifact) } label: { Label(artifact.title, systemImage: artifact.systemImage) }
            }
        } label: { Label("Workspaces", systemImage: "square.grid.2x2") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Habit trackers, to-do lists and debates — kept apart from the slip box")
    }

    func artifactFoldersForMigration(root: URL) -> [KasterArtifact: URL] {
        var result: [KasterArtifact: URL] = [:]
        for artifact in KasterArtifact.allCases {
            let stored = artifactFolderPath(artifact)
            result[artifact] = stored.isEmpty ? KasterArtifact.defaultFolder(artifact, in: root) : URL(fileURLWithPath: stored, isDirectory: true)
        }
        return result
    }

    func clearAfterMigration(_ moved: [URL: URL]) {
        for artifact in KasterArtifact.allCases where artifactFolderPath(artifact).isEmpty {
            if let root = vaultRoot, let folder = artifactFoldersForMigration(root: root)[artifact], FileManager.default.fileExists(atPath: folder.path) {
                switch artifact {
                case .habits: habitsFolder = folder.path
                case .todos: todosFolder = folder.path
                case .debates: debatesFolder = folder.path
                }
            }
        }
        if let current = fileURL, let destination = moved[current.standardizedFileURL] {
            if let content = try? String(contentsOf: destination, encoding: .utf8) { adoptMovedCurrentCard(from: current, to: destination, content: content) }
        }
        openTabs = openTabs.map { moved[$0.standardizedFileURL] ?? $0 }
        sidebarRefreshToken = UUID()
        status = "Organized \(moved.count) cards into Kaster folders."
    }

    // MARK: Typesetting

    /// Markdown that Kaster typesets for the current card, or nil for artifacts (habits, to-dos).
    var typesetSource: String? {
        if let linked = activeLinkedTab { return linked.content }
        if cardMode == "markdown" { return text }
        if cardMode == "outline" { return outlineCard?.text }
        return nil
    }
    var engine: TypesetEngine { TypesetEngine.stored(typesetEngine) }
    var typesetRequest: TypesetPreview.Request? {
        guard let source = typesetSource, KasterTypesetter.isAvailable(engine) else { return nil }
        return .init(text: source, cardURL: activeLinkedTab?.url ?? fileURL, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid,
                     engine: engine, wantsDocument: previewStyle == PreviewStyle.document.rawValue, color: PrintColor.stored(printMode), themes: themesEnabled)
    }
    /// Diagnostics only: `KASTER_TYPING_BENCH=/path/card.md` opens that card, types into it like a
    /// person (one character every 120 ms) and prints keystroke→preview timings to stderr, then
    /// quits. Never runs in a normal launch.
    func runTypingBenchmarkIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["KASTER_TYPING_BENCH"] else { return }
        let typist = TypingBenchmark()
        // Measure as if the window were in front: no App Nap or timer coalescing.
        typist.activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Typing benchmark")
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            _ = loadFile(URL(fileURLWithPath: path))
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let view = editor.view { view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0)) }
            TypesetPreview.benchmark = TypesetPreview.Benchmark()
            for character in Array(" The quick brown fox jumps over the lazy dog and keeps on typing to test the preview.") {
                let start = Date(); let generation = typeset.generation
                TypesetPreview.benchmark?.keystroke = start
                editor.insert(String(character))
                typist.keys.append(Date().timeIntervalSince(start) * 1000)
                Task { @MainActor in
                    while typeset.generation == generation && Date().timeIntervalSince(start) < 3 { try? await Task.sleep(nanoseconds: 1_000_000) }
                    typist.previews.append(Date().timeIntervalSince(start) * 1000)
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            typist.report(TypesetPreview.benchmark)
            NSApp.terminate(nil)
        }
    }

    func refreshTypeset() { if let request = typesetRequest { typeset.request(request) } }
    var currentPreviewData: Data? {
        if typesetRequest != nil { return typeset.cardPDF }
        return previewPDF
    }
    var currentPreviewRevision: PDFPreviewRevision {
        guard typesetRequest != nil else { return previewRevision }
        return PDFPreviewRevision(mode: cardMode, content: "typeset-\(typeset.generation)", portrait: portrait, fontSize: fontSize, dotGrid: dotGrid, filePath: fileURL?.standardizedFileURL.path)
    }

    /// The PDF that prints or exports: typeset for cards, the artifact's own renderer otherwise.
    /// If typesetting fails, offer the basic renderer so printing is never blocked.
    func outputPDF() -> Data? {
        guard let source = typesetSource else { return activePDF }
        guard KasterTypesetter.isAvailable(engine) else { return activePDF }
        let card = KasterTypesetter.prepare(source, cardURL: fileURL, links: false)
        switch KasterTypesetter.render([card], layout: .card(portrait: portrait, fontSize: fontSize, dotGrid: dotGrid), engine: engine, color: PrintColor.stored(printMode)) {
        case .success(let data): return data
        case .failure(let failure):
            let alert = NSAlert()
            alert.messageText = "This card couldn't be typeset"
            alert.informativeText = "\(failure.localizedDescription)\n\nYou can fix the card, or print it now with the basic renderer (no math or table layout)."
            alert.addButton(withTitle: "Use Basic Renderer"); alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn ? activePDF : nil
        }
    }

    // MARK: Batch printing

    func unprintedCardURLs() -> [URL] {
        let since = Date(timeIntervalSince1970: lastPrintTime)
        return library.snapshot.cards.filter { (library.modified[$0.path] ?? .distantPast) > since }
            .sorted { ($0.cardID ?? "~" + $0.title).localizedStandardCompare($1.cardID ?? "~" + $1.title) == .orderedAscending }
            .map(\.url)
    }

    /// Typesets the cards as one job (one card per page) and opens a single print dialog.
    func printBatch(_ urls: [URL], label: String) {
        guard !urls.isEmpty else {
            let alert = NSAlert(); alert.messageText = "No cards to print"
            alert.informativeText = label == "changed since your last print" ? "Every card has been printed since it last changed." : "There are no cards here yet."
            alert.runModal(); return
        }
        guard flushExistingDraft() else { return }
        var cards: [TypesetCard] = []
        var unreadable: [String] = []
        for url in urls {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                cards.append(KasterTypesetter.prepare(content, cardURL: url, links: false))
            } else { unreadable.append(url.lastPathComponent) }
        }
        guard !cards.isEmpty else { status = "Could not read those cards."; return }
        status = "Typesetting \(cards.count) cards…"
        let layout = TypesetLayout.card(portrait: portrait, fontSize: fontSize, dotGrid: dotGrid)
        var data: Data?
        if KasterTypesetter.isAvailable(engine) {
            switch KasterTypesetter.render(cards, layout: layout, engine: engine, color: PrintColor.stored(printMode)) {
            case .success(let pdf): data = pdf
            case .failure(let failure):
                let alert = NSAlert()
                alert.messageText = "Some cards couldn't be typeset"
                alert.informativeText = "\(failure.localizedDescription)\n\nPrint the batch with the basic renderer instead?"
                alert.addButton(withTitle: "Use Basic Renderer"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { status = "Batch print cancelled."; return }
            }
        }
        if data == nil {
            let merged = PDFDocument()
            for url in urls {
                guard let content = try? String(contentsOf: url, encoding: .utf8),
                      let pdfData = CardDocument(text: content, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid).pdf(),
                      let doc = PDFDocument(data: pdfData) else { continue }
                for index in 0..<doc.pageCount { if let page = doc.page(at: index) { merged.insert(page, at: merged.pageCount) } }
            }
            data = merged.dataRepresentation()
        }
        guard let data else { status = "Could not prepare cards."; return }
        if runPrint(data) {
            status = "Printed \(cards.count) \(cards.count == 1 ? "card" : "cards")\(label.isEmpty ? "" : " " + label)." + (unreadable.isEmpty ? "" : " Skipped \(unreadable.count) unreadable file(s).")
        } else {
            status = "Batch print cancelled."
        }
    }

    // Printing is Kaster's core loop; cards autosave, so Print is the one prominent action.
    @ViewBuilder var printButton: some View {
        let label = Label("Print", systemImage: "printer.fill").labelStyle(.titleAndIcon)
        if storedAppearance == AppearancePreference.charcoal.rawValue {
            Button(action: printCards) { label }.fixedSize().buttonStyle(CharcoalPrimaryButtonStyle()).keyboardShortcut("p").help("Print this card (⌘P)")
        } else if storedAppearance == AppearancePreference.slate.rawValue || storedAppearance == AppearancePreference.midnight.rawValue {
            Button(action: printCards) { label }.fixedSize().buttonStyle(SlatePrimaryButtonStyle(midnight: storedAppearance == AppearancePreference.midnight.rawValue)).keyboardShortcut("p").help("Print this card (⌘P)")
        } else {
            Button(action: printCards) { label }.fixedSize().buttonStyle(.borderedProminent).controlSize(.regular).keyboardShortcut("p").help("Print this card (⌘P)")
        }
    }

    // White writing surfaces on the system themes; Charcoal and Slate keep their backdrop.
    var paneBackground: Color {
        AppearancePreference.foreground(for: storedAppearance) == nil ? Color(nsColor: .textBackgroundColor) : Color.clear
    }
    var currentCardTypeName: String {
        switch cardMode {
        case "habits": return "Habit"
        case "todos": return "To Do"
        case "outline": return "Outline"
        default: return showDebate ? "Debate" : "Research"
        }
    }
    var isAutosaved: Bool {
        fileURL != nil && Data(currentDraftContents().utf8) == Data((currentDraftSnapshot() ?? currentDraftInitial()).utf8)
    }
    var statusLocation: String {
        if let card = library.card(for: fileURL) {
            let folder = (card.path as NSString).deletingLastPathComponent
            return folder.isEmpty ? URL(fileURLWithPath: library.loadedFolder).lastPathComponent : folder.replacingOccurrences(of: "/", with: " › ")
        }
        if let fileURL { return fileURL.deletingLastPathComponent().lastPathComponent }
        return "Draft"
    }
    var editorTabs: [EditorTab] {
        var tabs = openTabs.filter { FileManager.default.fileExists(atPath: $0.path) }.map { url -> EditorTab in
            let isCurrent = fileURL.map(KasterPathList.key) == KasterPathList.key(url)
            return EditorTab(url: url, title: isCurrent ? currentCardTitle : (library.card(for: url)?.title ?? url.deletingPathExtension().lastPathComponent))
        }
        if fileURL == nil { tabs.append(EditorTab(url: nil, title: currentCardTitle)) }
        return tabs
    }
    func rememberTab(_ url: URL?) {
        guard let url else { return }
        let key = KasterPathList.key(url)
        if !openTabs.contains(where: { KasterPathList.key($0) == key }) { openTabs.append(url) }
    }
    func closeTab(_ tab: EditorTab) {
        guard let url = tab.url else { if let last = openTabs.last { _ = loadFile(last) }; return }
        let key = KasterPathList.key(url)
        let isCurrent = fileURL.map(KasterPathList.key) == key
        guard let index = openTabs.firstIndex(where: { KasterPathList.key($0) == key }) else { return }
        if isCurrent {
            let remaining = openTabs.enumerated().filter { $0.offset != index }.map(\.element)
            if let next = remaining.indices.contains(max(0, index - 1)) ? remaining[max(0, index - 1)] : remaining.first {
                guard loadFile(next) else { return }
            } else {
                guard flushExistingDraft() else { return }
                newCard()
                guard fileURL == nil else { return }
            }
        }
        openTabs.removeAll { KasterPathList.key($0) == key }
    }
    func chooseNotesFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { notesFolder = url.path; status = "ID and notes folder: \(url.path)" }
    }
    func followLink(_ target: CardLinkTarget) {
        // A Zotero source clicked in the preview: open the cited page (matched to the PDF's page labels).
        if case .url(let raw) = target, raw.lowercased().hasPrefix("zotero://") {
            // Footnote links: book page → PDF page via the PDF's own page labels.
            if let url = ZoteroPageOpener.resolve(raw), NSWorkspace.shared.open(url) { status = "Opened in Zotero."; return }
        }
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
                case .failure(let message):
                    // A link to a card that doesn't exist yet creates it (as a Quick card).
                    if case .wiki(let raw) = target, message == "The linked note was not found." { createCardFromLink(raw) }
                    else { linkError(message) }
                case .external(let url):
                    if NSWorkspace.shared.open(url) { status = "Opened link." }
                    else { linkError("Could not open this link.") }
                case .current(let fragment):
                    guard cardMode == "markdown" else { linkError("Heading links are not available in the outline editor."); return }
                    showHeading(fragment)
                case .note(let url, let fragment):
                    if sourceFile?.standardizedFileURL == url.standardizedFileURL, let fragment { showHeading(fragment) }
                    else { openLinkedTab(url, fragment: fragment) }
                }
            }
        }
    }
    func openLinkedTab(_ url: URL, fragment: String? = nil) {
        do {
            let folderPath = notesFolder.isEmpty ? saveFolder : notesFolder
            guard !folderPath.isEmpty,
                  CardGraph.canOpen(url, in: URL(fileURLWithPath: folderPath, isDirectory: true)) else {
                linkError("This linked note is no longer available in the selected notes folder.")
                return
            }
            let content = try decodeMarkdown(Data(contentsOf: url))
            if let fragment, CardLinkNavigation.headingRange(fragment, in: content) == nil {
                linkError("The linked heading was not found.")
                return
            }
            linkedTabs.removeAll(where: { $0.url.standardizedFileURL == url.standardizedFileURL })
            guard fileURL.map({ KasterPathList.key($0) }) != KasterPathList.key(url) else { status = "That card is already open in the main editor."; return }
            let tab = LinkedCardTab(url: url, content: content, savedContent: content)
            linkedTabs.append(tab); sideTab = tab.id
            status = "Opened \(tab.title) beside the current card."
        } catch { linkError("Could not open linked note: \(error.localizedDescription)") }
    }
    /// A binding to one side card that stays safe after the card is closed.
    func sideBinding(_ initial: LinkedCardTab) -> Binding<LinkedCardTab> {
        Binding(
            get: { linkedTabs.first(where: { $0.id == initial.id }) ?? initial },
            set: { updated in
                if let index = linkedTabs.firstIndex(where: { $0.id == updated.id }) { linkedTabs[index] = updated }
            })
    }
    func closeLinkedTab(_ id: UUID) {
        linkedTabs.removeAll(where: { $0.id == id })
        if selectedLinkedTab == id { selectedLinkedTab = nil }
        if sideTab == id { sideTab = linkedTabs.last?.id }
    }
    func followLinkFromTab(_ target: CardLinkTarget, source: LinkedCardTab) {
        let folderPath = notesFolder.isEmpty ? saveFolder : notesFolder
        let folder = folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath, isDirectory: true)
        let result = CardLinkNavigation.resolve(target, folder: folder, currentFile: source.url)
        switch result {
        case .failure(let message): linkError(message)
        case .external(let url):
            if !NSWorkspace.shared.open(url) { linkError("Could not open this link.") }
        case .current(let fragment):
            if CardLinkNavigation.headingRange(fragment, in: source.content) == nil { linkError("The linked heading was not found.") }
        case .note(let url, let fragment): openLinkedTab(url, fragment: fragment)
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
    /// IDs already in use, for suggesting a new one. Uses the library index when it covers every
    /// folder that would be scanned; saving still checks the disk before a new ID is written.
    func knownIDs(for file: URL?) -> Set<String> { (try? knownIDs(throwingFor: file)) ?? [] }
    func knownIDs(throwingFor file: URL?) throws -> Set<String> {
        let roots = scanRoots(for: file)
        if roots.count == 1, !library.loadedFolder.isEmpty,
           roots[0].resolvingSymlinksInPath().standardizedFileURL.path == library.loadedFolder {
            return library.index.ids
        }
        return try BranchIDs.existing(in: roots)
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
        if mode == .titleOnly { storedIDMode = mode.rawValue; return }
        if isDebateCard && currentID != nil {
            storedIDMode = mode.rawValue
            status = "Debate cards keep their existing IDs."
            return
        }
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
            let existing = try BranchIDs.existing(in: roots, excluding: fileURL)
            guard let proposedID = CardIDs.newID(mode: mode, existing: existing,
                                                 timestampStyle: TimestampDateStyle(rawValue: timestampDateStyle) ?? .sortable,
                                                 timestampIncludeTime: timestampIncludeTime),
                  let updated = NoteEditing.setID(proposedID, in: text),
                  CardMetadata.parse(updated).id == proposedID else {
                status = "Could not prepare a \(mode.rawValue) ID. Check the card metadata."
                return
            }
            if let currentID, proposedID != currentID {
                let alert = NSAlert()
                alert.messageText = "Replace the current card ID?"
                alert.informativeText = "Current ID: \(currentID)\nSuggested \(mode.rawValue) ID: \(proposedID)" +
                    (fileURL == nil ? "\n\nThis changes the unsaved draft." : "\n\nThe saved file will keep its filename. Links using the old ID may need updating.")
                alert.addButton(withTitle: "Replace ID")
                alert.addButton(withTitle: "Keep Current ID")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    status = "Kept the current card ID and ID style."
                    return
                }
            }
            text = updated; storedIDMode = mode.rawValue
            status = "\(mode.rawValue) ID added: \(proposedID)."
        } catch {
            status = "Could not check card IDs: \(error.localizedDescription)"
            let alert = NSAlert(); alert.messageText = "Can't check card IDs"; alert.informativeText = status; alert.runModal()
        }
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
        let fullLink = root != nil && path.hasPrefix(root! + "/") ? String(path.dropFirst(root!.count + 1)) : parentURL.deletingPathExtension().lastPathComponent
        let link = CardifyNote.shortestLink(for: fullLink, among: library.snapshot.cards.map(\.path))
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
            let existing = try knownIDs(throwingFor: parentURL)
            let childID = try (continuation ? LuhmannIDs.continuation(of: parentID, existing: existing) : LuhmannIDs.branch(of: parentID, existing: existing))
            let root = notesFolder.isEmpty ? nil : URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL.path
            let path = parentURL.deletingPathExtension().standardizedFileURL.path
            let fullLink = root != nil && path.hasPrefix(root! + "/") ? String(path.dropFirst(root!.count + 1)) : parentURL.deletingPathExtension().lastPathComponent
            let link = CardifyNote.shortestLink(for: fullLink, among: library.snapshot.cards.map(\.path))
            guard !link.contains(where: { "[]|#^\n\r".contains($0) }) else { status = "The parent filename cannot be used in an Obsidian link."; return }
            let relation = continuation ? "continues this card" : "branches from this card"
            editor.discardUndoHistory()
            text = KasterFrontmatter.ensuringUID(in: CardMetadata.frontmatter(childID) + "# \n\nRelated: [[\(link)]] — \(relation).\n")
            branchSaveFolder = parentURL.deletingLastPathComponent(); fileURL = nil; savedMarkdownSnapshot = nil; history.detach()
            kasterMode = .zettel; storedIDMode = IDMode.luhmann.rawValue
            newDraftBaselines["markdown"] = Data(text.utf8)
            placeCursorAfterTitleMarker()
            status = "\(continuation ? "Continuation" : "Branch") \(childID) created. The parent is unchanged."
        } catch { status = "Could not create branch: \(error.localizedDescription)" }
    }
    var pageCount: Int {
        if typesetSource != nil && typeset.cardPDF != nil { return typeset.pageCount }
        return activePDF.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0
    }
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
        if cardMode == "markdown" && !showDebate { newKasterCard(KasterMode.stored(lastMode)); return }
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
    func newResearchCard(template: InlineTemplate?, mode: IDMode) {
        var discarded: [String] = []
        let modes = cardMode == "markdown" ? ["markdown"] : [cardMode, "markdown"]
        guard confirmReplaceDrafts(modes, discarded: &discarded) else { return }
        for discardedMode in discarded { clearDiscardedDraft(discardedMode) }
        cardMode = "markdown"
        fileURL = nil; branchSaveFolder = nil; history.detach()
        editor.discardUndoHistory(); savedMarkdownSnapshot = nil
        storedIDMode = mode.rawValue
        text = template?.markdown ?? ""
        if mode != .titleOnly { _ = ensureID() } else { status = "New draft." }
        newDraftBaselines["markdown"] = Data(text.utf8)
    }
    // A normal Save updates the note already open; Save As is the only path
    // that presents a destination panel for an existing note.
    func saveMarkdown(saveAs: Bool = false, automatic: Bool = false) -> Bool {
        autosaveTask?.cancel()
        if !notesFolder.isEmpty && (idMode != .titleOnly || CardMetadata.parse(text).id != nil) {
            var isDirectory = ObjCBool(false)
            let available = FileManager.default.fileExists(atPath: notesFolder, isDirectory: &isDirectory) &&
                isDirectory.boolValue && FileManager.default.isReadableFile(atPath: notesFolder)
            if !available {
                let message = "The selected notes folder is unavailable: \(notesFolder). Choose its current location to check card IDs."
                status = automatic ? "Autosave paused: " + message : message
                guard !automatic else { return false }
                let alert = NSAlert(); alert.messageText = "Locate notes folder"; alert.informativeText = message
                alert.addButton(withTitle: "Choose Notes Folder…"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return false }
                chooseNotesFolder()
                guard !notesFolder.isEmpty, FileManager.default.isReadableFile(atPath: notesFolder) else { return false }
            }
        }
        if cardMode == "markdown" && fileURL == nil && idMode != .titleOnly && !ensureID() { return false }
        let content = cardMode == "habits" ? tracker.markdown : cardMode == "todos" ? todo.markdown : cardMode == "outline" ? outline.markdown : text
        let currentURL = fileURL
        var target: URL
        if !saveAs, let currentURL {
            target = currentURL
        } else if !saveAs, currentURL == nil, let automaticTarget = autoTarget(prompting: !automatic) {
            target = automaticTarget
        } else {
            guard !automatic else { return false }
            let panel = NSSavePanel()
            if let currentURL { panel.directoryURL = currentURL.deletingLastPathComponent() }
            else if let folderName: String = cardMode == "habits" ? "Habit" : cardMode == "todos" ? "To Do" : cardMode == "markdown" && showDebate ? "Debate" : nil,
                    !(notesFolder.isEmpty && saveFolder.isEmpty) {
                do {
                    let root = URL(fileURLWithPath: notesFolder.isEmpty ? saveFolder : notesFolder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                    let folder = root.appendingPathComponent(folderName, isDirectory: true)
                    let manager = FileManager.default
                    if manager.fileExists(atPath: folder.path) {
                        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
                    } else { try manager.createDirectory(at: folder, withIntermediateDirectories: false) }
                    panel.directoryURL = folder
                } catch {
                    status = "Could not prepare the \(folderName) folder: \(error.localizedDescription)"
                    let alert = NSAlert(); alert.messageText = "Could not save card"; alert.informativeText = status; alert.runModal()
                    return false
                }
            }
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
                guard before == expected else { return fail("This file changed or was removed outside Kaster. Your draft is still open. Use Save As to keep a copy; if it has an ID, change the copy's ID to avoid a duplicate.") }
            }
            if CardMetadata.parse(content).id == nil && CardMetadata.hasNonemptyID(content) {
                return fail("Could not read card_id metadata. Check its formatting before saving.")
            }
            if let id = CardMetadata.parse(content).id {
                guard !id.contains(where: { $0.isNewline || ($0.isASCII && $0.isWhitespace && $0 != " ") }) else { return fail("Card IDs must be a single line.") }
                // An ID this same file already had was checked when it was first saved; re-reading the
                // whole vault on every autosave made typing stall in large vaults.
                let previousID = sameFile ? before.flatMap { try? decodeMarkdown($0) }.flatMap { CardMetadata.parse($0).id } : nil
                let unchangedID = previousID?.caseInsensitiveCompare(id) == .orderedSame
                var roots = [target.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL]
                if !notesFolder.isEmpty {
                    let folder = URL(fileURLWithPath: notesFolder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                    if roots[0].path == folder.path || roots[0].path.hasPrefix(folder.path + "/") { roots = [folder] }
                    else { roots.append(folder) }
                }
                for root in roots where !unchangedID {
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
                scheduleTitleRename()
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
            branchSaveFolder = nil
            // Update just this card in the library instead of rescanning every file.
            // A brand-new card does a full scan so the sidebar can reveal it in its folder.
            if currentURL == nil { sidebarRefreshToken = UUID() } else { library.refresh(files: [target], folder: libraryFolder) }
            status = automatic ? (currentURL == nil ? "Saved as \(target.lastPathComponent)." : "Changes saved.") : "Saved \(target.lastPathComponent)."
            if currentURL == nil && cardMode == "markdown" { lastMode = kasterMode.rawValue }
            scheduleTitleRename()
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
        guard let target = fileURL else {
            // New cards save themselves into their folder as soon as they have a title.
            guard autoTarget(prompting: false) != nil else { return }
            let snapshot = currentDraftContents()
            autosaveTask = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 900_000_000) } catch { return }
                guard !Task.isCancelled, cardMode == mode, fileURL == nil, Data(currentDraftContents().utf8) == Data(snapshot.utf8) else { return }
                _ = saveMarkdown(automatic: true)
            }
            return
        }
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
    /// Writes Card.pdf next to Card.md (same folder, same name), typeset as it prints.
    func savePDFBesideCard() {
        guard let url = fileURL else {
            if saveMarkdown(), fileURL != nil { savePDFBesideCard() } else { exportPDF() }
            return
        }
        guard flushExistingDraft(), let data = outputPDF() else { status = "Could not create the PDF."; return }
        let pdf = url.deletingPathExtension().appendingPathExtension("pdf")
        do {
            try data.write(to: pdf, options: .atomic)
            status = "Saved \(pdf.lastPathComponent) next to the card."
        } catch { status = "Could not save the PDF: \(error.localizedDescription)" }
    }
    func exportPDF() {
        guard let data = outputPDF() else { status = cardMode == "habits" ? "Shorten the heading to create a PDF." : "Could not create PDF."; return }
        let panel = NSSavePanel(); if !saveFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: saveFolder, isDirectory: true) }; panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Index Card") + ".pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic); status = "Exported \(url.lastPathComponent)." }
            catch { status = "Could not export: \(error.localizedDescription)" }
        }
    }
    func printCards() {
        guard let data = outputPDF() else { status = cardMode == "habits" ? "Shorten the heading to print." : "Could not prepare cards."; return }
        if runPrint(data) { status = "Sent \(currentCardTitle) to the printer." }
    }

    @discardableResult
    func runPrint(_ data: Data) -> Bool {
        guard let pdf = PDFDocument(data: data) else { status = "Could not prepare cards."; return false }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 216, height: 360)
        info.orientation = portrait ? .portrait : .landscape
        info.leftMargin = 0; info.rightMargin = 0; info.topMargin = 0; info.bottomMargin = 0
        info.horizontalPagination = .clip; info.verticalPagination = .clip
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
            status = "Could not prepare the print job."
            return false
        }
        let printed = operation.run()
        if printed { lastPrintTime = Date().timeIntervalSince1970 }
        return printed
    }

    /// The folder the library (sidebar, backlinks, index) reads.
    var libraryFolder: String { notesFolder.isEmpty ? saveFolder : notesFolder }

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
            let original = String(decoding: mutation.snapshot.bytes, as: UTF8.self)
            guard Data(original.utf8) == mutation.snapshot.bytes else { throw SidebarFileActions.ActionError.invalidMarkdown }
            let field = NSTextField(string: KasterVault.displayTitle(for: url, text: original)); field.frame.size.width = 320
            let alert = NSAlert(); alert.messageText = "Rename card"
            alert.informativeText = "Changes the card's title and filename together and updates links to it. Links with their own label keep the label."
            alert.accessoryView = field; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let newTitle = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let root = mutation.snapshot.root
            guard let filename = KasterVault.retitledFilename(for: url, root: root, text: original, title: newTitle) else {
                throw SidebarFileActions.ActionError.invalidName
            }
            let newText = NoteEditing.setTitle(newTitle, in: original)
            let otherURLs = try validateSidebarMutation(mutation)
            if mutation.activeMode != nil { autosaveTask?.cancel(); renameTask?.cancel() }
            let folder = url.deletingLastPathComponent()
            let target = KasterVault.uniqueURL(in: folder, filename: filename, excluding: url)
            let renamed = try SidebarFileActions.retitle(mutation.snapshot, newText: newText, filename: target.lastPathComponent, openURLs: otherURLs)
            let updated = (try? KasterVault.updateLinks(root: root, oldURL: url, newURL: renamed, skip: [renamed.resolvingSymlinksInPath().standardizedFileURL.path])) ?? []
            if mutation.activeMode != nil {
                adoptMovedCurrentCard(from: url, to: renamed, content: newText)
                linkRequestID = UUID()
            } else {
                for index in linkedTabs.indices where linkedTabs[index].url.standardizedFileURL == url.standardizedFileURL { linkedTabs[index].url = renamed }
                let key = url.resolvingSymlinksInPath().standardizedFileURL
                if let index = openTabs.firstIndex(where: { $0.resolvingSymlinksInPath().standardizedFileURL == key }) { openTabs[index] = renamed }
                history.rename(url, to: renamed); sidebarRefreshToken = UUID()
            }
            reloadOpenCards(updated + [renamed])
            status = "Renamed to “\(newTitle)”" + (updated.isEmpty ? "." : "; updated links in \(updated.count) card\(updated.count == 1 ? "" : "s").")
        } catch { scheduleAutosave(); sidebarError(error) }
    }

    private func moveSidebarNote(_ url: URL, to folder: URL) {
        do {
            guard let mutation = try prepareSidebarMutation(url) else { return }
            let otherURLs = try validateSidebarMutation(mutation)
            if mutation.activeMode != nil { autosaveTask?.cancel() }
            let moved = try SidebarFileActions.move(mutation.snapshot, to: folder, openURLs: otherURLs)
            if mutation.activeMode != nil { fileURL = moved; linkRequestID = UUID() }
            for index in linkedTabs.indices where linkedTabs[index].url.standardizedFileURL == url.standardizedFileURL { linkedTabs[index].url = moved }
            history.rename(url, to: moved)
            sidebarRefreshToken = UUID()
            status = moved == url ? "This note is already in that folder." : "Moved \(url.lastPathComponent) to \(folder.lastPathComponent). Links using its old folder path may need updating."
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
            for tab in linkedTabs where tab.url.standardizedFileURL == url.standardizedFileURL { closeLinkedTab(tab.id) }
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
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                EditorTextSizeCommands()
            }
    }
}

/// View ▸ Bigger / Smaller / Actual Size: the editor's on-screen text size only.
struct EditorTextSizeCommands: Commands {
    @AppStorage(EditorTextScale.key) private var editorScale = 1.0
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Bigger Editor Text") { editorScale = EditorTextScale.bigger(editorScale) }
                .keyboardShortcut("=", modifiers: .command).disabled(editorScale >= EditorTextScale.steps.last!)
            Button("Smaller Editor Text") { editorScale = EditorTextScale.smaller(editorScale) }
                .keyboardShortcut("-", modifiers: .command).disabled(editorScale <= EditorTextScale.steps.first!)
            Button("Normal Editor Text") { editorScale = 1 }
                .keyboardShortcut("0", modifiers: .command).disabled(editorScale == 1)
        }
    }
}

final class TypingBenchmark {
    var keys: [Double] = []
    var previews: [Double] = []
    var activity: NSObjectProtocol?
    func report(_ typeset: TypesetPreview.Benchmark?) {
        func summary(_ values: [Double]) -> String {
            let sorted = values.sorted(); guard !sorted.isEmpty else { return "none" }
            return String(format: "median %.0f ms, p90 %.0f ms, max %.0f ms (n=%d)", sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.9)], sorted.last!, sorted.count)
        }
        let lines = ["keystroke handling: " + summary(keys),
                     "keystroke→render starts: " + summary(typeset?.requested ?? []),
                     "render (Typst): " + summary(typeset?.rendered ?? []),
                     "keystroke→preview updated: " + summary(previews)]
        FileHandle.standardError.write(Data(lines.map { "KASTER_BENCH " + $0 + "\n" }.joined().utf8))
    }
}
