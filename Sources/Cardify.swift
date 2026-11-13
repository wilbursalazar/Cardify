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
        let attributed = MarkdownRendering.render(text, fontSize: CGFloat(fontSize))
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
            let path = CGPath(rect: body, transform: nil)
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
    @StateObject private var editor = EditorState()
    @State private var fileURL: URL?
    @State private var showZotero = false
    @State private var showNotes = false
    @State private var research: ResearchClip?
    @State private var status = "Draft saved on this Mac."
    var card: CardDocument { CardDocument(text: text, portrait: portrait, fontSize: fontSize, dotGrid: dotGrid) }
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
                    Button("Research Card…") { research = ResearchClip() }
                    Button("Weekly Habit Tracker") { fileURL = nil; cardMode = "habits" }
                }
                Button("Add Source…") { showZotero = true }.disabled(cardMode == "habits")
                Button("Save Folder…", action: chooseFolder)
                Button("New Card") { if cardMode == "habits" { setTracker(HabitTracker()) } else { text = "" }; fileURL = nil; status = "New draft." }
            }
            HSplitView {
                VStack(alignment: .leading) {
                    Picker("Card type", selection: Binding(get: { cardMode }, set: { cardMode = $0; fileURL = nil })) {
                        Text("Markdown").tag("markdown"); Text("Habits").tag("habits")
                    }.pickerStyle(.segmented)
                    if cardMode == "habits" {
                        HabitTrackerEditor(tracker: Binding(get: { tracker }, set: { setTracker($0) }))
                    } else {
                    HStack { Text("Write").fontWeight(.semibold); Spacer(); Text("Markdown · use - [ ] for tasks").foregroundStyle(.secondary) }
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
    var pageCount: Int { activePDF.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0 }
    func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                if let saved = HabitTracker.fromMarkdown(contents) { setTracker(saved); cardMode = "habits" }
                else { text = contents; cardMode = "markdown" }
                fileURL = url; status = "Opened \(url.lastPathComponent)."
            }
            catch { status = "Could not open file: \(error.localizedDescription)" }
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path; status = "Default save folder: \(url.path)" }
    }
    func saveMarkdown() -> Bool {
        let panel = NSSavePanel(); if !saveFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: saveFolder, isDirectory: true) }; panel.allowedContentTypes = [.init(filenameExtension: "md")!]; panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Index Card.md"
        if panel.runModal() == .OK, let url = panel.url {
            do { try (cardMode == "habits" ? tracker.markdown : text).write(to: url, atomically: true, encoding: .utf8); fileURL = url; status = "Saved \(url.lastPathComponent)."; return true }
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
