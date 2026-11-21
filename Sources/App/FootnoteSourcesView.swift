import SwiftUI
import AppKit

/// Lays chips out left to right, wrapping onto new lines as needed.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in arrange(width: bounds.width, subviews).frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        var frames: [CGRect] = [], row: [Int] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        func finishRow() {
            for index in row { frames[index].origin.y = y + (rowHeight - frames[index].height) / 2 }
            y += rowHeight + lineSpacing; x = 0; rowHeight = 0; row = []
        }
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width { finishRow() }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            row.append(frames.count - 1)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        if !row.isEmpty { finishRow() }
        return (frames, widest, max(0, y - lineSpacing))
    }
}

/// The card's sources, one chip per footnote: number, citation, page and a button that opens the
/// page in Zotero. Shown on Research cards, and on any card with Zotero footnotes.
struct SourceChipsRow: View {
    let sources: [FootnoteSource]
    let alsoCited: (ZoteroSource) -> [LibraryCard]
    let onSetPage: (FootnoteSource, String) -> Void
    let onOpen: (FootnoteSource) -> Void
    let onJump: (FootnoteSource) -> Void
    let onRemove: (FootnoteSource) -> Void
    let onOpenCard: (URL) -> Void
    let onAdd: () -> Void
    /// A source kept the older way (frontmatter + "Source:" line), offered for conversion.
    var legacy: (source: ZoteroSource, page: String?)? = nil
    var onOpenLegacy: () -> Void = {}
    var onConvertLegacy: () -> Void = {}

    var body: some View {
        ChipFlowLayout {
            Label("Sources", systemImage: "books.vertical").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .help("Sources are footnotes in the card. Each chip edits its footnote's page; the book opens that page in Zotero.")
            if let legacy {
                HStack(spacing: 4) {
                    Text(FootnoteSources.plain(legacy.source.cite)).font(.system(size: 12)).lineLimit(1).frame(maxWidth: 260, alignment: .leading).layoutPriority(-1)
                    if let page = legacy.page { Text("p. \(page)").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Button(action: onOpenLegacy) { Image(systemName: legacy.page.flatMap(ZoteroPageOpener.firstPage) == nil || legacy.source.pdf == nil ? "arrow.up.forward.square" : "book") }
                        .buttonStyle(.borderless).help("Open the cited page in Zotero")
                    Button("Make Footnote", action: onConvertLegacy).buttonStyle(.borderless)
                        .help("Move this source into a footnote on the quotation, with an editable page")
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .help("Saved the older way, as a Source line. Make it a footnote to edit its page here.")
            }
            ForEach(sources) { source in
                SourceChip(source: source, others: source.zotero.map(alsoCited) ?? [], onSetPage: onSetPage, onOpen: onOpen,
                           onJump: onJump, onRemove: onRemove, onOpenCard: onOpenCard)
            }
            Button(action: onAdd) { Label("Source", systemImage: "plus") }
                .buttonStyle(.borderless).fixedSize()
                .help("Add a Zotero source: its footnote number goes where your cursor is")
        }
    }
}

struct SourceChip: View {
    let source: FootnoteSource
    let others: [LibraryCard]
    let onSetPage: (FootnoteSource, String) -> Void
    let onOpen: (FootnoteSource) -> Void
    let onJump: (FootnoteSource) -> Void
    let onRemove: (FootnoteSource) -> Void
    let onOpenCard: (URL) -> Void
    @State private var draft = ""
    @FocusState private var editingPage: Bool

    private var shortTitle: String {
        let title = source.title
        return title.count > 44 ? String(title.prefix(42)).trimmingCharacters(in: .whitespaces) + "…" : title
    }
    private var openablePage: String? { source.page.flatMap(ZoteroPageOpener.firstPage) }

    var body: some View {
        HStack(spacing: 4) {
            Text(source.label).font(.system(size: 9, weight: .bold)).foregroundColor(AppearancePreference.currentAccent).baselineOffset(3)
            Menu {
                if let url = source.zotero?.selectURL { Button("Show in Zotero") { NSWorkspace.shared.open(url) } }
                Button("Go to Footnote") { onJump(source) }
                if !others.isEmpty {
                    Menu("Also Cited in \(others.count) Card\(others.count == 1 ? "" : "s")") {
                        ForEach(others.prefix(100)) { card in Button(card.title) { onOpenCard(card.url) } }
                    }
                }
                Divider()
                Button("Remove Footnote") { onRemove(source) }
            } label: { Text(shortTitle).font(.system(size: 12)).lineLimit(1) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(maxWidth: 260, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)   // In a narrow editor the title shortens; number, page and book stay.
                .help(FootnoteSources.plain(source.text))
            if source.zotero != nil && source.pageEditable {
                TextField("p.", text: $draft)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 52)
                    .focused($editingPage).onSubmit(commit)
                    .help("Page or location — press Return to save it in the footnote")
                    .accessibilityLabel("Page for footnote \(source.label)")
            } else if source.zotero != nil, let page = source.page {
                Text(page).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let zotero = source.zotero {
                Button { onOpen(source) } label: { Image(systemName: openablePage == nil ? "arrow.up.forward.square" : "book") }
                    .buttonStyle(.borderless)
                    .help(openablePage.map { zotero.pdf == nil ? "Find the PDF in Zotero and open page \($0)" : "Open page \($0) of the PDF in Zotero" } ?? "Show this source in Zotero")
                    .accessibilityLabel("Open in Zotero")
            }
        }
        .padding(.leading, 7).padding(.trailing, source.zotero == nil ? 7 : 4).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1), in: Capsule())
        .onAppear { draft = source.page ?? "" }
        .onChange(of: source.page) { draft = $0 ?? "" }
        .onChange(of: editingPage) { editing in if !editing { commit() } }
    }

    private func commit() {
        let page = draft.trimmingCharacters(in: .whitespaces)
        guard page != (source.page ?? "") else { return }
        onSetPage(source, page)
    }
}

/// Every source cited in footnotes across the vault, A–Z. Zotero items show their full entry in
/// the chosen citation style while Zotero is running; each source lists the cards that cite it.
struct BibliographyView: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [LibraryCard]
    let onOpen: (URL) -> Void
    let onPrint: ([String]) -> Void
    @AppStorage(ZoteroStyle.key) private var storedStyle = ""
    @State private var entries: [BibliographyEntry]?
    @State private var formatted: [String: String] = [:]
    @State private var note = ""
    @State private var query = ""

    private func display(_ entry: BibliographyEntry) -> String { formatted[entry.id] ?? entry.text }

    private var shown: [BibliographyEntry] {
        let sorted = (entries ?? []).sorted {
            FootnoteBibliography.sortKey(display($0)).localizedStandardCompare(FootnoteBibliography.sortKey(display($1))) == .orderedAscending
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { entry in
            FootnoteSources.plain(display(entry)).localizedCaseInsensitiveContains(q) || entry.cards.contains { $0.title.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bibliography").font(.title2.bold())
                Spacer()
                Button("Print Bibliography Cards") { onPrint(shown.map(display)) }.disabled(shown.isEmpty)
            }
            Text("Every source cited in a footnote, A–Z, with the cards that cite it. Zotero sources show their full entry in your citation style while Zotero is open.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Search sources and cards", text: $query)
            if entries == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                Text(entries?.isEmpty == true ? "No sources yet. Add one to a card with + Source, or type a citation in a footnote." : "No sources match.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { entry in row(entry) }
            }
            HStack {
                Text(note).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 640, height: 580)
        .task { await load() }
    }

    private func row(_ entry: BibliographyEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.attributed(display(entry))).font(.system(size: 13)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let url = entry.zotero?.selectURL {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.borderless).help("Show in Zotero")
                }
            }
            ChipFlowLayout(spacing: 5, lineSpacing: 4) {
                ForEach(entry.cards.prefix(24)) { card in
                    Button { onOpen(card.url); dismiss() } label: {
                        Text(card.title).font(.system(size: 11)).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain).help("Open \(card.path)")
                }
                if entry.cards.count > 24 { Text("+\(entry.cards.count - 24) more").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 3)
    }

    static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }

    @MainActor private func load() async {
        let cards = self.cards
        let collected = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: FootnoteBibliography.collect(cards)) }
        }
        entries = collected
        let zotero = collected.compactMap(\.zotero)
        guard !zotero.isEmpty else { return }
        let style = ZoteroStyle.current(stored: storedStyle)
        var reached = false, failed = false
        for (library, items) in Dictionary(grouping: zotero, by: \.library) {
            for start in stride(from: 0, to: items.count, by: 50) {
                let chunk = Array(items[start..<min(start + 50, items.count)])
                do {
                    let (data, response) = try await URLSession.shared.data(for: ZoteroSearchAPI.bibliographyRequest(library: chunk[0].zoteroLibrary, keys: chunk.map(\.key), style: style))
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { failed = true; continue }
                    for item in try JSONDecoder().decode([ZoteroBibEntry].self, from: data) {
                        guard let bib = item.bib else { continue }
                        let text = ZoteroCitation.markdown(fromHTML: bib, trimPeriod: false)
                        if !text.isEmpty { formatted["zotero:\(library)/\(item.key)"] = text }
                    }
                    reached = true
                } catch { failed = true }
            }
        }
        let title = ZoteroStyle.installed().first { $0.id == style }?.title ?? style
        note = reached ? "Zotero entries in \(title)." + (failed ? " Some could not be fetched." : "")
                       : "Zotero isn't reachable, so Zotero sources show their short citation."
    }
}
