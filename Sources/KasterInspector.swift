import SwiftUI
import AppKit

enum InspectorTab: String, CaseIterable { case preview, backlinks, info }
enum PreviewStyle: String, CaseIterable { case document, card }

struct KasterInspector<CardPreview: View>: View {
    @ObservedObject var store: LibraryStore
    let markdown: String
    let isMarkdownMode: Bool
    let currentURL: URL?
    let cardType: String
    let onFollowLink: (CardLinkTarget) -> Void
    let onOpen: (URL) -> Void
    var documentPDF: Data? = nil
    var documentRevision: PDFPreviewRevision? = nil
    var typesetError: String? = nil
    var onPrintCard: () -> Void = {}
    @ViewBuilder let cardPreview: () -> CardPreview

    @AppStorage("kasterInspectorTab") private var storedTab = InspectorTab.preview.rawValue
    @AppStorage("kasterPreviewStyle") private var storedStyle = PreviewStyle.document.rawValue
    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue

    private var tab: InspectorTab { InspectorTab(rawValue: storedTab) ?? .preview }
    private var style: PreviewStyle { isMarkdownMode ? (PreviewStyle(rawValue: storedStyle) ?? .document) : .card }
    private var accent: Color { AppearancePreference.accent(for: appearance) ?? AppearancePreference.kasterPurple }

    var body: some View {
        let backlinks = store.backlinks(for: currentURL)
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                tabButton(.preview, "Preview")
                tabButton(.backlinks, "Backlinks (\(backlinks.count))")
                tabButton(.info, "Info")
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 36)
            Divider()
            switch tab {
            case .preview: preview
            case .backlinks: backlinksView(backlinks)
            case .info: infoView(backlinks: backlinks.count)
            }
        }
        .frame(minWidth: 240, maxHeight: .infinity)
    }

    private func tabButton(_ value: InspectorTab, _ title: String) -> some View {
        let selected = tab == value
        return Button { storedTab = value.rawValue } label: {
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? accent : .secondary)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { if selected { Rectangle().fill(accent).frame(height: 2) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var preview: some View {
        VStack(spacing: 0) {
            if isMarkdownMode {
                Picker("Preview", selection: $storedStyle) {
                    Text("Document").tag(PreviewStyle.document.rawValue)
                    Text("Index Card").tag(PreviewStyle.card.rawValue)
                }
                .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.vertical, 8)
                .help("Read the note as a document, or see how it prints on 3 × 5 cards")
            }
            if style == .document {
                Group {
                    if let documentPDF {
                        // Typeset by the same engine that prints the card.
                        PDFPreview(data: documentPDF, revision: documentRevision, fitWidth: true, onFollowLink: onFollowLink)
                    } else {
                        ScrollView {
                            KasterDocumentView(markdown: markdown, onFollowLink: onFollowLink)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if let typesetError {
                        Label(typesetError, systemImage: "exclamationmark.triangle")
                            .font(.caption).lineLimit(3).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding([.horizontal, .bottom], 12)
            } else {
                cardPreview().padding([.horizontal, .bottom], 12).padding(.top, isMarkdownMode ? 0 : 10)
            }
        }
    }

    private func backlinksView(_ backlinks: [LibraryCard]) -> some View {
        let outgoing = store.outgoing(for: currentURL)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if currentURL == nil {
                    hint("Save this card in your notes folder to see which cards link to it.")
                } else if store.card(for: currentURL) == nil {
                    hint("This card is outside the notes folder, so its backlinks aren't indexed.")
                } else {
                    sectionLabel("Linked from")
                    if backlinks.isEmpty { hint("No cards link here yet. Link to it with [[\(store.card(for: currentURL)?.title ?? "")]].") }
                    ForEach(backlinks) { card in linkRow(card, context: snippet(in: card)) }
                    sectionLabel("Links to").padding(.top, 10)
                    if outgoing.isEmpty { hint("This card doesn't link to other cards yet.") }
                    ForEach(outgoing) { card in linkRow(card, context: nil) }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func snippet(in card: LibraryCard) -> String? {
        guard let target = store.card(for: currentURL) else { return nil }
        let names = [target.title, target.path, (target.path as NSString).lastPathComponent].map { $0.lowercased() }
        for line in card.content.components(separatedBy: .newlines) where line.contains("[[") {
            let lower = line.lowercased()
            if names.contains(where: { lower.contains("[[" + $0) }) { return line.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    private func linkRow(_ card: LibraryCard, context: String?) -> some View {
        Button { onOpen(card.url) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(card.title).font(.system(size: 13, weight: .medium)).foregroundColor(accent).lineLimit(1)
                    Spacer()
                    if let id = card.cardID { Text(id).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                if let context { Text(context).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(card.path)
    }

    private func infoView(backlinks: Int) -> some View {
        let card = store.card(for: currentURL)
        let metadata = CardMetadata.parse(markdown)
        let tags = KasterText.tags(markdown)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                infoRow("Type", cardType)
                infoRow("Card ID", metadata.id ?? card?.cardID ?? "—")
                infoRow("File", currentURL?.lastPathComponent ?? "Unsaved draft")
                if let card { infoRow("Folder", (card.path as NSString).deletingLastPathComponent.isEmpty ? "Notes folder" : (card.path as NSString).deletingLastPathComponent) }
                infoRow("Created", KasterDates.full(card.flatMap { store.created[$0.path] }))
                infoRow("Modified", KasterDates.full(card.flatMap { store.modified[$0.path] }))
                infoRow("Words", "\(KasterText.wordCount(markdown))")
                infoRow("Characters", "\(markdown.count)")
                infoRow("Links out", "\(CardLinkParser.links(in: markdown).count)")
                infoRow("Backlinks", "\(backlinks)")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags").font(.system(size: 11)).foregroundStyle(.secondary)
                    if tags.isEmpty { Text("None").font(.system(size: 12)).foregroundStyle(.tertiary) }
                    else {
                        FlowTags(tags: tags, accent: accent)
                    }
                }.padding(.vertical, 8)
                if let currentURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([currentURL]) }
                        .padding(.top, 8)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                Text(value).font(.system(size: 12)).textSelection(.enabled).lineLimit(2)
                Spacer(minLength: 0)
            }.padding(.vertical, 7)
            Divider()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.6)
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct FlowTags: View {
    let tags: [String]
    let accent: Color
    var body: some View {
        // Simple wrapping via a lazy grid of adaptive columns.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#" + tag).font(.system(size: 11)).foregroundColor(accent).lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accent.opacity(0.12), in: Capsule())
            }
        }
    }
}

// MARK: Rendered document

struct KasterDocumentView: View {
    let markdown: String
    let onFollowLink: (CardLinkTarget) -> Void
    static let wikiScheme = "kaster-wiki"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let blocks = MarkdownBlocks.parse(Self.body(of: markdown))
            if blocks.isEmpty { Text("Nothing to preview yet.").foregroundStyle(.secondary) }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in view(for: block) }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == Self.wikiScheme {
                let target = url.absoluteString.dropFirst(Self.wikiScheme.count + 1)
                onFollowLink(.wiki(String(target).removingPercentEncoding ?? String(target)))
            } else {
                onFollowLink(.url(url.absoluteString))
            }
            return .handled
        })
    }

    static func body(of text: String) -> String {
        guard let range = LinkCompletionTextView.frontmatterRange(in: text) else { return text }
        return (text as NSString).substring(from: NSMaxRange(range))
    }

    @ViewBuilder private func view(for block: MarkdownBlocks.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(.system(size: [22, 17, 15, 14, 13, 13][min(level, 6) - 1], weight: level == 1 ? .bold : .semibold))
                .padding(.top, level == 1 ? 0 : 6)
        case .paragraph(let text):
            inline(text).font(.system(size: 13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker).font(.system(size: 13, weight: item.ordered ? .regular : .bold)).foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                        inline(item.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 14)
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(AppearancePreference.kasterPurple.opacity(0.5)).frame(width: 3)
                inline(text).font(.system(size: 13)).italic().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text):
            Text(text).font(.system(size: 12, design: .monospaced)).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider().padding(.vertical, 4)
        case .table(let header, let rows):
            table(header: header, rows: rows)
        case .image(let alt, let source):
            if let image = Self.localImage(source) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260).help(alt)
            } else {
                Label(alt.isEmpty ? source : alt, systemImage: "photo").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func localImage(_ source: String) -> NSImage? {
        let decoded = source.removingPercentEncoding ?? source
        let path = decoded.hasPrefix("file://") ? (URL(string: source)?.path ?? decoded) : decoded
        guard path.hasPrefix("/") else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columns, id: \.self) { column in
                    cell(column < header.count ? header[column] : "", header: true)
                }
            }
            .background(AppearancePreference.kasterSelection)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in cell(column < row.count ? row[column] : "", header: false) }
                }
            }
        }
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.3)))
    }

    private func cell(_ text: String, header: Bool) -> some View {
        inline(text).font(.system(size: 12, weight: header ? .semibold : .regular))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .border(Color.secondary.opacity(0.22), width: 0.5)
    }

    private func inline(_ text: String) -> Text {
        Text(Self.attributed(text))
    }

    static func attributed(_ text: String) -> AttributedString {
        // Turn [[target|label]] into ordinary Markdown links with a private scheme.
        var source = text.replacingOccurrences(of: "</?u>", with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]|#]+)(#[^\\]|]*)?(?:\\|([^\\]]+))?\\]\\]") {
            let ns = source as NSString
            var result = ""
            var last = 0
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let target = ns.substring(with: match.range(at: 1))
                let fragment = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
                let label = match.range(at: 3).location == NSNotFound ? "[[" + target + fragment + "]]" : ns.substring(with: match.range(at: 3))
                let encoded = (target + fragment).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? target
                result += "[\(label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]"))](\(wikiScheme):\(encoded))"
                last = NSMaxRange(match.range)
            }
            result += ns.substring(from: last)
            source = result
        }
        var attributed = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = AppearancePreference.kasterPurple
            attributed[run.range].underlineStyle = .single
        }
        return attributed
    }
}

enum MarkdownBlocks {
    struct ListItem { let marker: String; let text: String; let indent: Int; let ordered: Bool }
    enum Block {
        case heading(Int, String), paragraph(String), list([ListItem]), quote(String), code(String), rule
        case table([String], [[String]]), image(String, String)
    }

    static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func parse(_ text: String) -> [Block] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [Block] = []
        var paragraph: [String] = []
        var list: [ListItem] = []
        var quote: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !list.isEmpty { blocks.append(.list(list)); list = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))); quote = [] }
        }
        let listPattern = try? NSRegularExpression(pattern: "^(\\s*)([-*+]|\\d+[.)])\\s+(\\[[ xX]\\]\\s+)?(.*)$")
        let separator = try? NSRegularExpression(pattern: "^\\s*\\|?\\s*:?-{3,}:?\\s*(\\|\\s*:?-{3,}:?\\s*)*\\|?\\s*$")
        let imagePattern = try? NSRegularExpression(pattern: "^!\\[([^\\]]*)\\]\\(([^)]+)\\)\\s*$")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let ns = line as NSString
            let whole = NSRange(location: 0, length: ns.length)
            if trimmed.isEmpty { flush(); index += 1; continue }
            if trimmed.hasPrefix("```") {
                flush()
                var code: [String] = []
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[index]); index += 1 }
                blocks.append(.code(code.joined(separator: "\n"))); index += 1; continue
            }
            if let match = trimmed.range(of: "^#{1,6} ", options: .regularExpression) {
                flush()
                let level = trimmed[match].filter { $0 == "#" }.count
                blocks.append(.heading(level, String(trimmed[match.upperBound...]))); index += 1; continue
            }
            if trimmed.range(of: "^([-*_])\\s*(\\1\\s*){2,}$", options: .regularExpression) != nil {
                flush(); blocks.append(.rule); index += 1; continue
            }
            if trimmed.hasPrefix("|"), index + 1 < lines.count,
               separator?.firstMatch(in: lines[index + 1], range: NSRange(location: 0, length: (lines[index + 1] as NSString).length)) != nil {
                flush()
                let header = cells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(cells(lines[index])); index += 1 }
                blocks.append(.table(header, rows)); continue
            }
            if let match = imagePattern?.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                flush()
                let t = trimmed as NSString
                blocks.append(.image(t.substring(with: match.range(at: 1)), t.substring(with: match.range(at: 2)))); index += 1; continue
            }
            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty || !list.isEmpty { let q = quote; flush(); quote = q }
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)); index += 1; continue
            }
            if let match = listPattern?.firstMatch(in: line, range: whole) {
                if !paragraph.isEmpty || !quote.isEmpty { let l = list; flush(); list = l }
                let indent = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "\t", with: "  ").count / 2
                let rawMarker = ns.substring(with: match.range(at: 2))
                let ordered = rawMarker.first?.isNumber == true
                var marker = ordered ? rawMarker : "•"
                if match.range(at: 3).location != NSNotFound {
                    marker = ns.substring(with: match.range(at: 3)).lowercased().contains("x") ? "☑" : "☐"
                }
                list.append(ListItem(marker: marker, text: ns.substring(with: match.range(at: 4)), indent: indent, ordered: ordered))
                index += 1; continue
            }
            if !list.isEmpty || !quote.isEmpty { flush() }
            paragraph.append(trimmed)
            index += 1
        }
        flush()
        return blocks
    }
}
