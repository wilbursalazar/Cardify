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
                Button("Replace Draft") { if onUse(clip.markdown, false) { dismiss() } }.buttonStyle(.borderedProminent)
            }
        }.padding(22).frame(width: 560, height: 390)
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
    @State private var tracker = HabitTracker()
    @State private var todo = TodoList()
    @AppStorage("saveFolder") private var saveFolder = ""
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("autoTimestampID") private var autoTimestampID = false
    @AppStorage("idMode") private var storedIDMode = ""
    @AppStorage("newCardWorkflow") private var newCardWorkflow = WorkflowPreference.configured.rawValue
    @AppStorage("cardifyAppearance") private var storedAppearance = AppearancePreference.system.rawValue
    @StateObject private var editor = EditorState()
    @StateObject private var graphWindow = GraphWindowManager()
    @State private var fileURLs: [String: URL] = [:]
    @State private var savedMarkdownSnapshot: String?
    @State private var savedHabitSnapshot: String?
    @State private var savedTodoSnapshot: String?
    @State private var history = CardHistory()
    @State private var traversingHistory = false
    @State private var suppressHistorySave = false
    @State private var branchSaveFolders: [String: URL] = [:]
    @State private var showZotero = false
    @State private var showNotes = false
    @State private var showLibrary = false
    @State private var showDebate = false
    @State private var showDebateBrowser = false
    @State private var showSettings = false
    @State private var linkRequestID = UUID()
    @State private var research: ResearchClip?
    @State private var status = "Draft saved on this Mac."
    var fileURL: URL? {
        get { fileURLs[cardMode] }
        nonmutating set { fileURLs[cardMode] = newValue }
    }
    var branchSaveFolder: URL? {
        get { branchSaveFolders[cardMode] }
        nonmutating set { branchSaveFolders[cardMode] = newValue }
    }
    var card: CardDocument { CardDocument(text: text, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid) }
    var idMode: IDMode { IDMode(rawValue: storedIDMode) ?? (autoTimestampID ? .timestamp : .titleOnly) }
    var activePDF: Data? {
        if cardMode == "habits" { return tracker.pdf(portrait: portrait, dotGrid: dotGrid, fontSize: fontSize) }
        if cardMode == "todos" { return CardDocument(text: todo.printMarkdown, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid).pdf() }
        return card.pdf()
    }
    var previewPDF: Data? { cardMode == "markdown" ? card.pdf(includeLinks: true) : activePDF }
    var previewRevision: PDFPreviewRevision {
        PDFPreviewRevision(mode: cardMode, content: cardMode == "habits" ? tracker.markdown : cardMode == "todos" ? todo.printMarkdown : text, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid, filePath: fileURL?.standardizedFileURL.path)
    }
    var currentCardTitle: String {
        let title = cardMode == "habits" ? tracker.title : cardMode == "todos" ? todo.title : NoteEditing.title(in: text)
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled card") : title
    }
    func setTracker(_ value: HabitTracker) {
        tracker = value
        if let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) { habitDraft = encoded }
    }
    func setTodo(_ value: TodoList) {
        todo = value
        if let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) { todoDraft = encoded }
    }
    func switchMode(to mode: String) {
        guard mode != cardMode else { return }
        cardMode = mode
        if let fileURL { history.visit(fileURL) } else { history.detach() }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cardify").font(.system(size: 25, weight: .bold))
                    Text("Write, connect, and print your notes.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Menu("File") {
                    Button("New Card") {
                        guard confirmReplaceDraft() else { return }
                        fileURL = nil; branchSaveFolder = nil; history.detach()
                        if cardMode == "habits" { savedHabitSnapshot = nil; setTracker(HabitTracker()); status = "New draft." }
                        else if cardMode == "todos" { savedTodoSnapshot = nil; setTodo(TodoList()); status = "New draft." }
                        else {
                            savedMarkdownSnapshot = nil
                            if let defaults = WorkflowPreference.defaults(for: newCardWorkflow) {
                                storedIDMode = defaults.idMode.rawValue
                                text = defaults.template?.markdown ?? ""
                            } else { text = "" }
                            if idMode != .titleOnly { _ = ensureID() } else { status = "New draft." }
                        }
                    }
                    Button("Open Markdown…", action: openFile)
                    Divider()
                    Button("Export PDF…", action: exportPDF)
                    Divider()
                    Button("Choose Save Folder…", action: chooseFolder)
                    Button("Choose Notes Folder…", action: chooseNotesFolder)
                    Divider()
                    Button("Settings…") { showSettings = true }
                }
                Button("Save…") { _ = saveMarkdown() }.keyboardShortcut("s")
                Button("Print…", action: printCards).keyboardShortcut("p")
                Button("Save & Print…") { if saveMarkdown() { printCards() } }.buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                Button { navigateHistory(back: true) } label: { Image(systemName: "chevron.left") }
                    .help("Back to the previous card").keyboardShortcut("[", modifiers: .command).disabled(history.backTarget == nil)
                Button { navigateHistory(back: false) } label: { Image(systemName: "chevron.right") }
                    .help("Forward to the next visited card").keyboardShortcut("]", modifiers: .command).disabled(history.forwardTarget == nil)
                Button("Library…") { showLibrary = true }
                Button("Graph…") { showGraph() }.help("Explore card connections in a separate window")
                Divider().frame(height: 16)
                Text(currentCardTitle).lineLimit(1).truncationMode(.middle)
                if cardMode == "markdown", let id = CardMetadata.parse(text).id {
                    Text(id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 125, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            Divider()
            HSplitView {
                VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Picker("Card type", selection: Binding(get: { cardMode == "markdown" && showDebate ? "debate" : cardMode }, set: { mode in
                            if mode == "debate" { showDebate = true; switchMode(to: "markdown") }
                            else { if mode == "markdown" { showDebate = false }; switchMode(to: mode) }
                        })) {
                            Text("Research").tag("markdown"); Text("Habit").tag("habits"); Text("To Do").tag("todos"); Text("Debate").tag("debate")
                        }.pickerStyle(.segmented).labelsHidden().frame(minWidth: 240, maxWidth: 250)
                        Spacer(minLength: 4)
                        Menu("Templates") {
                            Button("Idea Card") { insertTemplate(.idea) }
                            Button("Reading Card") { insertTemplate(.reading) }
                            Button("Index Card") { insertTemplate(.index) }
                            Button("Mark Current Card as Index") { markIndexCard() }.disabled(cardMode != "markdown")
                            Divider()
                            Button("New Idea from This Card…") { ideaFromCurrent() }.disabled(cardMode != "markdown")
                            Divider()
                            Button("Research Card…") { research = ResearchClip() }
                            Button("Weekly Habit Tracker") { switchMode(to: "habits") }
                        }
                    }
                    if cardMode == "markdown" && showDebate {
                        DebatePanel(text: $text, showBrowser: $showDebateBrowser, currentURL: fileURL, onOpen: { url in loadFile(url) }, onNew: { draft in
                            guard confirmReplaceDraft() else { return false }
                            let folderPath = notesFolder.isEmpty ? saveFolder : notesFolder
                            let folder = folderPath.isEmpty ? fileURL?.deletingLastPathComponent() : URL(fileURLWithPath: folderPath, isDirectory: true)
                            text = draft; fileURL = nil; branchSaveFolder = folder; savedMarkdownSnapshot = nil; history.detach()
                            if idMode != .titleOnly && !ensureID() { return true }
                            status = "New debate card. Save it when ready."
                            return true
                        }, onFollowLink: followLink)
                    }
                    if cardMode == "habits" {
                        HabitTrackerEditor(tracker: Binding(get: { tracker }, set: { setTracker($0) }))
                    } else if cardMode == "todos" {
                        TodoListEditor(list: Binding(get: { todo }, set: { setTodo($0) }))
                    } else {
                    HStack {
                        TextField("Title", text: Binding(get: { NoteEditing.title(in: text) }, set: { text = NoteEditing.setTitle($0, in: text) }))
                        Picker("ID style", selection: Binding(get: { idMode }, set: { mode in
                            storedIDMode = mode.rawValue
                            if mode != .titleOnly && CardMetadata.parse(text).id == nil { _ = ensureID() }
                        })) {
                            ForEach(IDMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }.frame(width: 190).help("Choose how IDs are suggested for new notes. Existing IDs are kept.")
                    }
                    HStack {
                        Text("Write").fontWeight(.semibold)
                        if idMode != .titleOnly || CardMetadata.parse(text).id != nil {
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
                                Button("Continue sequence…") { relatedFromCurrent(continuation: true) }.help("Create the next card in this sequence")
                            }
                            Button("Branch from card…") { relatedFromCurrent(continuation: false) }.help("Create a linked branch from the current card")
                        }
                    }
                    HStack(spacing: 5) {
                        Button("B") { editor.wrap("**") }.help("Bold")
                        Button("I") { editor.wrap("*") }.help("Italic")
                        Button("H1") { editor.prefix("# ") }.help("Heading")
                        Button("H2") { editor.prefix("## ") }.help("Subheading")
                        Button("• List") { editor.prefix("- ") }.help("Bullet list")
                        Button("☐ Task") { editor.prefix("- [ ] ") }.help("Task")
                        Spacer(minLength: 0)
                    }.buttonStyle(.bordered)
                    HStack(spacing: 8) {
                        Button("Link Note…") { showNotes = true }.help("Search your notes folder")
                        Button("Add Zotero Source…") { showZotero = true }.help("Find a source in Zotero")
                        Spacer(minLength: 0)
                    }
                    MarkdownEditor(text: $text, editor: editor, onFollowLink: followLink).border(Color.secondary.opacity(0.2))
                    }
                }.frame(minWidth: 340)
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
                        Menu("Design") { Toggle("Dot grid", isOn: $dotGrid) }
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
                }.padding(.leading, 12).frame(minWidth: 332)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 850, minHeight: 600)
        .preferredColorScheme(AppearancePreference.colorScheme(for: storedAppearance))
        .onAppear {
            if storedIDMode.isEmpty { storedIDMode = (autoTimestampID ? IDMode.timestamp : IDMode.titleOnly).rawValue }
            if let data = habitDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(HabitTracker.self, from: data) { tracker = saved }
            if let data = todoDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(TodoList.self, from: data) { todo = saved }
        }
        .onDisappear { graphWindow.close() }
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
            guard research == nil && !showNotes && !showLibrary && !showDebateBrowser && !showSettings && !showZotero else {
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
        let folderPath = notesFolder.isEmpty ? saveFolder : notesFolder
        let folder = folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath, isDirectory: true)
        let sourceFile = fileURL
        let sourceText = text
        let requestID = UUID(); linkRequestID = requestID
        status = "Opening link…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CardLinkNavigation.resolve(target, folder: folder, currentFile: sourceFile)
            DispatchQueue.main.async {
                guard requestID == linkRequestID, cardMode == "markdown", !showDebateBrowser, fileURL == sourceFile,
                      (notesFolder.isEmpty ? saveFolder : notesFolder) == folderPath else { return }
                guard text == sourceText else { status = "Link not opened because the card changed."; return }
                switch result {
                case .failure(let message): linkError(message)
                case .external(let url):
                    if NSWorkspace.shared.open(url) { status = "Opened link." }
                    else { linkError("Could not open this link.") }
                case .current(let fragment): showHeading(fragment)
                case .note(let url, let fragment):
                    if sourceFile?.standardizedFileURL != url.standardizedFileURL {
                        editor.clearPendingSelection()
                        guard loadFile(url) else { return }
                    }
                    if let fragment {
                        guard cardMode == "markdown" else { linkError("Heading links are not available in habit cards."); return }
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
            guard let id = CardIDs.newID(mode: idMode, existing: existing) else { return true }
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
        if fileURL == nil || savedMarkdownSnapshot != text || !(fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) {
            let alert = NSAlert(); alert.messageText = "Save this card before creating an idea?"
            alert.informativeText = "The new idea links to the saved card."
            alert.addButton(withTitle: "Save…"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn, saveMarkdown() else { return }
        }
        guard let parentURL = fileURL else { return }
        let root = notesFolder.isEmpty ? nil : URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL.path
        let path = parentURL.deletingPathExtension().standardizedFileURL.path
        let link = root != nil && path.hasPrefix(root! + "/") ? String(path.dropFirst(root!.count + 1)) : parentURL.deletingPathExtension().lastPathComponent
        guard CardifyNote(path: link).canLink else { status = "The saved card's filename cannot be used in an Obsidian link."; return }
        do {
            let newID: String?
            if idMode == .titleOnly { newID = nil }
            else { newID = CardIDs.newID(mode: idMode, existing: try BranchIDs.existing(in: scanRoots(for: parentURL))) }
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
        if fileURL == nil || savedMarkdownSnapshot != text || !(fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) {
            let alert = NSAlert(); alert.messageText = "Save this card before branching?"
            alert.informativeText = "The new card links to the saved parent, so save your current changes first."
            alert.addButton(withTitle: "Save…"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn, saveMarkdown() else { return }
        }
        guard let parentURL = fileURL else { return }
        do {
            let existing = try BranchIDs.existing(in: scanRoots(for: parentURL))
            let childID = try (continuation ? CardIDs.continuation(from: parentID, existing: existing) : CardIDs.branch(from: parentID, existing: existing))
            let root = notesFolder.isEmpty ? nil : URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL.path
            let path = parentURL.deletingPathExtension().standardizedFileURL.path
            let link = root != nil && path.hasPrefix(root! + "/") ? String(path.dropFirst(root!.count + 1)) : parentURL.deletingPathExtension().lastPathComponent
            guard !link.contains(where: { "[]|#^\n\r".contains($0) }) else { status = "The parent filename cannot be used in an Obsidian link."; return }
            let relation = continuation ? "continues this card" : "branches from this card"
            text = CardMetadata.frontmatter(childID) + "# \n\nRelated: [[\(link)]] — \(relation).\n"
            branchSaveFolder = parentURL.deletingLastPathComponent(); fileURL = nil; savedMarkdownSnapshot = nil; history.detach()
            status = "\(continuation ? "Continuation" : "Branch") \(childID) created. The parent is unchanged."
        } catch { status = "Could not create branch: \(error.localizedDescription)" }
    }
    var pageCount: Int { activePDF.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0 }
    // Check the active draft before any action that replaces it.
    func confirmReplaceDraft(hidden: Bool = false) -> Bool {
        let current = cardMode == "habits" ? tracker.markdown : cardMode == "todos" ? todo.markdown : text
        let snapshot = cardMode == "habits" ? savedHabitSnapshot : cardMode == "todos" ? savedTodoSnapshot : savedMarkdownSnapshot
        let initial = cardMode == "habits" ? HabitTracker().markdown : cardMode == "todos" ? TodoList().markdown : ""
        guard current != (snapshot ?? initial) else { return true }
        let kind = cardMode == "habits" ? "habit" : cardMode == "todos" ? "to-do" : "research"
        let alert = NSAlert()
        alert.messageText = "Save changes to your \(kind) draft?"
        alert.informativeText = hidden ? "The existing \(kind) draft will be replaced." : "Your current draft will be replaced or left behind."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if hidden {
                let wasSuppressed = suppressHistorySave; suppressHistorySave = true
                defer { suppressHistorySave = wasSuppressed }
                return saveMarkdown()
            }
            return saveMarkdown()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
    func useResearch(_ content: String, append: Bool) -> Bool {
        let changingMode = cardMode != "markdown"
        if cardMode == "markdown" {
            if !append && !confirmReplaceDraft() { return false }
        } else {
            guard confirmReplaceDraft() else { return false }
            let previousMode = cardMode, previousURL = fileURL, previousBranch = branchSaveFolder
            cardMode = "markdown"
            if !append && !confirmReplaceDraft(hidden: true) {
                cardMode = previousMode; fileURL = previousURL; branchSaveFolder = previousBranch
                return false
            }
        }
        if append { text += (text.isEmpty ? "" : "\n\n") + content }
        else { text = content; fileURL = nil; branchSaveFolder = nil; savedMarkdownSnapshot = nil }
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
    func loadFile(_ url: URL) -> Bool {
        var previousMode = cardMode, previousURL = fileURL, previousBranch = branchSaveFolder
        var loaded = false
        defer {
            if !loaded { cardMode = previousMode; fileURL = previousURL; branchSaveFolder = previousBranch }
        }
        do {
            // Check readability before prompting. Read again after each save so the
            // selected file cannot be replaced with stale pre-save contents.
            _ = try String(contentsOf: url, encoding: .utf8)
            guard confirmReplaceDraft() else { return false }
            previousMode = cardMode; previousURL = fileURL; previousBranch = branchSaveFolder
            var contents = try String(contentsOf: url, encoding: .utf8)
            var savedHabit = HabitTracker.fromMarkdown(contents)
            var savedTodo = savedHabit == nil ? TodoList.fromMarkdown(contents) : nil
            let targetMode = savedHabit != nil ? "habits" : savedTodo != nil ? "todos" : "markdown"
            if targetMode != previousMode {
                cardMode = targetMode
                guard confirmReplaceDraft(hidden: true) else { return false }
                cardMode = previousMode; fileURL = previousURL; branchSaveFolder = previousBranch
                contents = try String(contentsOf: url, encoding: .utf8)
                savedHabit = HabitTracker.fromMarkdown(contents)
                savedTodo = savedHabit == nil ? TodoList.fromMarkdown(contents) : nil
            }
            let finalMode = savedHabit != nil ? "habits" : savedTodo != nil ? "todos" : "markdown"
            guard finalMode == targetMode else { status = "The card changed while opening. Try again."; return false }
            cardMode = finalMode
            if let savedHabit {
                setTracker(savedHabit); savedHabitSnapshot = savedHabit.markdown
            } else if let savedTodo {
                setTodo(savedTodo); savedTodoSnapshot = savedTodo.markdown
            } else { text = contents; savedMarkdownSnapshot = contents }
            fileURL = url; branchSaveFolder = nil; status = "Opened \(url.lastPathComponent)."
            if !traversingHistory { history.visit(url) }
            loaded = true
            return true
        } catch { status = "Could not open file: \(error.localizedDescription)"; return false }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path; status = "Default save folder: \(url.path)" }
    }
    func saveMarkdown() -> Bool {
        if cardMode == "markdown" && idMode != .titleOnly && !ensureID() { return false }
        let panel = NSSavePanel()
        if let folder = branchSaveFolder { panel.directoryURL = folder }
        else if !saveFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: saveFolder, isDirectory: true) }
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? (cardMode == "markdown" ? NoteEditing.filename(id: idMode == .titleOnly ? nil : CardMetadata.parse(text).id, title: NoteEditing.title(in: text)) : cardMode == "todos" ? NoteEditing.filename(id: nil, title: todo.title) : "Weekly Habits.md")
        if panel.runModal() == .OK, let url = panel.url {
            let content = cardMode == "habits" ? tracker.markdown : cardMode == "todos" ? todo.markdown : text
            if CardMetadata.parse(content).id == nil && CardMetadata.hasNonemptyID(content) {
                status = "Could not read card_id metadata. Check its formatting before saving."; return false
            }
            if let id = CardMetadata.parse(content).id {
                guard !id.contains(where: { $0.isNewline || ($0.isASCII && $0.isWhitespace && $0 != " ") }) else { status = "Card IDs must be a single line."; return false }
                var roots = [url.deletingLastPathComponent().standardizedFileURL]
                if !notesFolder.isEmpty {
                    let folder = URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL
                    if roots[0].path == folder.path || roots[0].path.hasPrefix(folder.path + "/") { roots = [folder] }
                    else { roots.append(folder) }
                }
                do {
                    for root in roots {
                        if let duplicate = try CardIDIndex.ids(in: root, excluding: url).first(where: { $0.0.caseInsensitiveCompare(id) == .orderedSame }) {
                            let alert = NSAlert(); alert.messageText = "This card ID is already in use"; alert.informativeText = "\(id) is used by \(duplicate.1.lastPathComponent). Change the ID before saving."; alert.runModal()
                            status = "Duplicate card ID: \(id)."; return false
                        }
                    }
                } catch { status = "Could not verify card IDs: \(error.localizedDescription)"; return false }
            }
            do { try content.write(to: url, atomically: true, encoding: .utf8); fileURL = url; if cardMode == "habits" { savedHabitSnapshot = content } else if cardMode == "todos" { savedTodoSnapshot = content } else { savedMarkdownSnapshot = content }; if !suppressHistorySave { history.saveCurrent(url) }; branchSaveFolder = nil; status = "Saved \(url.lastPathComponent)."; return true }
            catch { status = "Could not save: \(error.localizedDescription)" }
        }
        return false
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
