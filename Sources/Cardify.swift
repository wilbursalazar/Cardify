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

    func pdf() -> Data? {
        let size = pageSize
        let inset: CGFloat = 27 // 3/8 inch, in PDF points
        let body = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let metadata = CardMetadata.parse(text)
        var textBody = body
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
            textBody.size.height -= 12
        }
        let attributed = MarkdownRendering.render(metadata.body, fontSize: CGFloat(fontSize))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var media = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        var location = 0
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
            let path = CGPath(rect: textBody, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.restoreGState()
            context.endPDFPage()
            guard visible.length > 0 else { context.closePDF(); return nil }
            location += visible.length
        } while location < attributed.length
        context.closePDF()
        return data as Data
    }
}

struct PDFPreview: NSViewRepresentable {
    let data: Data?
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.backgroundColor = NSColor.windowBackgroundColor; return view }
    func updateNSView(_ view: PDFView, context: Context) { if let data { view.document = PDFDocument(data: data) } }
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
    let onUse: (String, Bool) -> Void
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
                Button("Append to Draft") { onUse(clip.markdown, true); dismiss() }
                Button("Replace Draft") { onUse(clip.markdown, false); dismiss() }.buttonStyle(.borderedProminent)
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
    @State private var tracker = HabitTracker()
    @AppStorage("saveFolder") private var saveFolder = ""
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("autoTimestampID") private var autoTimestampID = false
    @AppStorage("idMode") private var storedIDMode = ""
    @StateObject private var editor = EditorState()
    @State private var fileURL: URL?
    @State private var savedMarkdownSnapshot: String?
    @State private var branchSaveFolder: URL?
    @State private var showZotero = false
    @State private var showNotes = false
    @State private var research: ResearchClip?
    @State private var status = "Draft saved on this Mac."
    var card: CardDocument { CardDocument(text: text, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid) }
    var idMode: IDMode { IDMode(rawValue: storedIDMode) ?? (autoTimestampID ? .timestamp : .titleOnly) }
    var activePDF: Data? { cardMode == "habits" ? tracker.pdf(portrait: portrait, dotGrid: dotGrid, fontSize: fontSize) : card.pdf() }
    func setTracker(_ value: HabitTracker) {
        tracker = value
        if let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) { habitDraft = encoded }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) { Text("Cardify").font(.system(size: 28, weight: .bold)); Text("Cards for your paper and digital notes.").foregroundStyle(.secondary) }
                Spacer()
                Button("Open Markdown…", action: openFile)
                Button("Save…") { _ = saveMarkdown() }.keyboardShortcut("s")
                Button("Export PDF…", action: exportPDF)
                Button("Print…", action: printCards).keyboardShortcut("p")
                Button("Save & Print…") { if saveMarkdown() { printCards() } }.buttonStyle(.borderedProminent)
            }
            Divider()
            HStack {
                Picker("Layout", selection: $portrait) { Text("Landscape (5 × 3)").tag(false); Text("Portrait (3 × 5)").tag(true) }.frame(width: 240)
                Text("Text size")
                Slider(value: $fontSize, in: 7...18, step: 1).frame(width: 120).help("Text size")
                Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 45)
                Spacer()
                Menu("Design") { Toggle("Dot grid", isOn: $dotGrid) }
                Menu("Templates") {
                    Button("Idea Card") { insertTemplate(.idea) }
                    Button("Reading Card") { insertTemplate(.reading) }
                    Button("Index Card") { insertTemplate(.index) }
                    Divider()
                    Button("Choose ID / Notes Folder…", action: chooseNotesFolder)
                    Divider()
                    Button("Research Card…") { research = ResearchClip() }
                    Button("Weekly Habit Tracker") { fileURL = nil; cardMode = "habits" }
                }
                Button("Add Source…") { showZotero = true }.disabled(cardMode == "habits")
                Button("Save Folder…", action: chooseFolder)
                Button("New Card") {
                    fileURL = nil; savedMarkdownSnapshot = nil; branchSaveFolder = nil
                    if cardMode == "habits" { setTracker(HabitTracker()); status = "New draft." }
                    else { text = ""; if idMode != .titleOnly { _ = ensureID() } else { status = "New draft." } }
                }
            }
            HSplitView {
                VStack(alignment: .leading) {
                    Picker("Card type", selection: Binding(get: { cardMode }, set: { cardMode = $0; fileURL = nil })) {
                        Text("Markdown").tag("markdown"); Text("Habits").tag("habits")
                    }.pickerStyle(.segmented)
                    if cardMode == "habits" {
                        HabitTrackerEditor(tracker: Binding(get: { tracker }, set: { setTracker($0) }))
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
                        Spacer()
                        Button("Link Note…") { showNotes = true }.help("Search your notes folder")
                    }.buttonStyle(.bordered)
                    MarkdownEditor(text: $text, editor: editor).border(Color.secondary.opacity(0.2))
                    }
                }.frame(minWidth: 300)
                VStack(alignment: .leading) {
                    HStack { Text("Preview").fontWeight(.semibold); Spacer(); Text("\(pageCount) \(pageCount == 1 ? "card" : "cards")").foregroundStyle(.secondary) }
                    if let data = activePDF {
                        PDFPreview(data: data).border(Color.secondary.opacity(0.2))
                    } else {
                        Text(cardMode == "habits" ? "The heading is too long to fit. Shorten it to preview and print." : "Could not create the preview.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(minWidth: 320)
            }
            Text("3 × 5-inch stock · ⅜-inch inset · Long notes continue onto more cards. Select 100% scale and the matching paper size in the print dialog.")
                .font(.caption).foregroundStyle(.secondary)
            Text(status).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 850, minHeight: 600)
        .onAppear {
            if storedIDMode.isEmpty { storedIDMode = (autoTimestampID ? IDMode.timestamp : IDMode.titleOnly).rawValue }
            if let data = habitDraft.data(using: .utf8), let saved = try? JSONDecoder().decode(HabitTracker.self, from: data) { tracker = saved }
        }
        .onOpenURL { url in
            if let clip = ResearchClip.from(url) { research = clip }
            else { status = "Could not open that clip." }
        }
        .sheet(item: $research) { clip in
            ResearchEditor(clip: clip) { content, append in
                if cardMode != "markdown" { fileURL = nil }
                cardMode = "markdown"
                if append { text += (text.isEmpty ? "" : "\n\n") + content }
                else { text = content; fileURL = nil }
                status = "Research card ready."
            }
        }
        .sheet(isPresented: $showNotes) {
            NotePicker { link in editor.insert(link); status = "Note link inserted." }
        }
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
        cardMode = "markdown"
        if idMode != .titleOnly && !ensureID() { return }
        let offset = editor.view?.selectedRange().location ?? (text as NSString).length
        let result = template.inserting(in: text, at: offset)
        text = result.text; status = "\(template.rawValue) template inserted."
        DispatchQueue.main.async {
            guard let view = editor.view else { return }
            view.setSelectedRange(NSRange(location: min(result.cursor, (view.string as NSString).length), length: 0))
            view.window?.makeFirstResponder(view)
        }
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
            branchSaveFolder = parentURL.deletingLastPathComponent(); fileURL = nil; savedMarkdownSnapshot = nil
            status = "\(continuation ? "Continuation" : "Branch") \(childID) created. The parent is unchanged."
        } catch { status = "Could not create branch: \(error.localizedDescription)" }
    }
    var pageCount: Int { activePDF.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0 }
    func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                if let saved = HabitTracker.fromMarkdown(contents) { setTracker(saved); cardMode = "habits" }
                else { text = contents; cardMode = "markdown" }
                fileURL = url; branchSaveFolder = nil; savedMarkdownSnapshot = cardMode == "markdown" ? contents : nil; status = "Opened \(url.lastPathComponent)."
            }
            catch { status = "Could not open file: \(error.localizedDescription)" }
        }
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
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? (cardMode == "markdown" ? NoteEditing.filename(id: idMode == .titleOnly ? nil : CardMetadata.parse(text).id, title: NoteEditing.title(in: text)) : "Weekly Habits.md")
        if panel.runModal() == .OK, let url = panel.url {
            let content = cardMode == "habits" ? tracker.markdown : text
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
            do { try content.write(to: url, atomically: true, encoding: .utf8); fileURL = url; savedMarkdownSnapshot = cardMode == "markdown" ? content : nil; branchSaveFolder = nil; status = "Saved \(url.lastPathComponent)."; return true }
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

@main struct CardifyApp: App {
    var body: some Scene { WindowGroup { ContentView() }.windowStyle(.titleBar) }
}
