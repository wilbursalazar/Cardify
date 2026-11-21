import Foundation

/// Luhmann's keyword register: a short alphabetical list of keywords, each pointing to a few
/// entry cards (1–3 is the habit; more are allowed). It lives in one plain Markdown file,
/// `Register.md` at the top of the vault, one keyword per line:
///
///     - Atomicity: [[A card must stand on its own]], [[One idea per card]]
///
/// Lines Kaster doesn't recognise are kept exactly as written.
enum KeywordRegister {
    static let filename = "Register.md"
    static let suggestedLinks = 3

    struct Entry: Equatable, Identifiable {
        var keyword: String
        var links: [String]
        var id: String { keyword.lowercased() }
    }

    static func url(in root: URL) -> URL { root.appendingPathComponent(filename) }

    static let template = "---\nkaster_register: true\n---\n# Register\n\n"

    private static let linkPattern = try! NSRegularExpression(pattern: "\\[\\[([^\\]\\n]+)\\]\\]")

    /// The entry on one line, or nil if the line isn't a register entry.
    static func entry(in line: String) -> Entry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- "), let colon = trimmed.firstIndex(of: ":") else { return nil }
        let keyword = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colon].trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, !keyword.contains("[[") else { return nil }
        let rest = String(trimmed[trimmed.index(after: colon)...])
        let ns = rest as NSString
        let links = linkPattern.matches(in: rest, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        return Entry(keyword: keyword, links: links)
    }

    static func entries(in text: String) -> [Entry] {
        text.components(separatedBy: "\n").compactMap { entry(in: $0.hasSuffix("\r") ? String($0.dropLast()) : $0) }
            .sorted { $0.keyword.localizedStandardCompare($1.keyword) == .orderedAscending }
    }

    static func line(for entry: Entry) -> String {
        "- \(entry.keyword): " + entry.links.map { "[[\($0)]]" }.joined(separator: ", ")
    }

    /// Adds a link under a keyword (creating the keyword), keeping entries alphabetical.
    /// Matching is case-insensitive; the link isn't added twice.
    static func adding(_ link: String, to keyword: String, in text: String) -> String {
        let keyword = keyword.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: " ")
        guard !keyword.isEmpty, !link.isEmpty else { return text }
        var lines = (text.isEmpty ? template : text).components(separatedBy: "\n")
        if let index = lines.firstIndex(where: { entry(in: $0)?.keyword.caseInsensitiveCompare(keyword) == .orderedSame }),
           var existing = entry(in: lines[index]) {
            guard !existing.links.contains(where: { $0.caseInsensitiveCompare(link) == .orderedSame }) else { return lines.joined(separator: "\n") }
            existing.links.append(link)
            lines[index] = line(for: existing)
            return lines.joined(separator: "\n")
        }
        let newLine = line(for: Entry(keyword: keyword, links: [link]))
        // Insert before the first entry that sorts after it, else after the last entry (or at the end).
        let entryIndices = lines.indices.filter { entry(in: lines[$0]) != nil }
        if let after = entryIndices.first(where: { entry(in: lines[$0])!.keyword.localizedStandardCompare(keyword) == .orderedDescending }) {
            lines.insert(newLine, at: after)
        } else if let last = entryIndices.last {
            lines.insert(newLine, at: last + 1)
        } else {
            while lines.last == "" { lines.removeLast() }
            lines.append(""); lines.append(newLine); lines.append("")
            return lines.joined(separator: "\n")
        }
        return lines.joined(separator: "\n")
    }

    /// Removes one link from a keyword, or the whole keyword when `link` is nil or it was the last.
    static func removing(_ link: String?, from keyword: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { entry(in: $0)?.keyword.caseInsensitiveCompare(keyword) == .orderedSame }),
              var existing = entry(in: lines[index]) else { return text }
        if let link { existing.links.removeAll { $0.caseInsensitiveCompare(link) == .orderedSame } }
        if link == nil || existing.links.isEmpty { lines.remove(at: index) } else { lines[index] = line(for: existing) }
        return lines.joined(separator: "\n")
    }

    /// Register cards for printing: alphabetical, about `perCard` keywords per 3×5 card, each card
    /// headed with its letter range ("Register A–F").
    static func printCards(_ entries: [Entry], perCard: Int = 9) -> [String] {
        guard !entries.isEmpty else { return [] }
        return stride(from: 0, to: entries.count, by: perCard).map { start in
            let chunk = Array(entries[start..<min(start + perCard, entries.count)])
            let first = chunk.first!.keyword.prefix(1).uppercased(), last = chunk.last!.keyword.prefix(1).uppercased()
            let title = first == last ? "Register \(first)" : "Register \(first)–\(last)"
            let lines = chunk.map { entry in
                "**\(entry.keyword)** — " + entry.links.map { link in (link as NSString).lastPathComponent }.joined(separator: "; ")
            }
            return "# \(title)\n\n" + lines.joined(separator: "  \n") + "\n"
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The register as a list: keywords A–Z, each with its entry cards.
struct KeywordRegisterView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [KeywordRegister.Entry]
    let indexCardsToImport: Int
    let resolve: (String) -> URL?
    let onOpen: (URL) -> Void
    let onRemove: (_ link: String?, _ keyword: String) -> Void
    let onImportIndexCards: () -> Void
    let onPrint: () -> Void
    let onOpenFile: () -> Void
    @State private var query = ""

    private var shown: [KeywordRegister.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? entries : entries.filter { $0.keyword.localizedCaseInsensitiveContains(q) || $0.links.contains { $0.localizedCaseInsensitiveContains(q) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyword Register").font(.title2.bold())
                Spacer()
                Button("Open Register.md", action: { onOpenFile(); dismiss() }).help("Edit the register as a card")
                Button("Print Register Cards", action: onPrint).disabled(entries.isEmpty)
            }
            Text("Luhmann's index: a few keywords, each pointing to 1–3 entry cards where a line of thought begins. Add a card from its ⋯ menu or by right-clicking it in the sidebar.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Search keywords", text: $query)
            if indexCardsToImport > 0 {
                Button("Add \(indexCardsToImport) Index Card\(indexCardsToImport == 1 ? "" : "s") as Keywords", action: onImportIndexCards)
                    .help("Each card marked as an index card becomes a keyword pointing to it")
            }
            if shown.isEmpty {
                Text(entries.isEmpty ? "No keywords yet." : "No keywords match.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.keyword).font(.system(size: 13, weight: .semibold))
                            if entry.links.count > KeywordRegister.suggestedLinks {
                                Text("\(entry.links.count) entries").font(.caption2).foregroundStyle(.orange)
                                    .help("Luhmann kept 1–3 entry cards per keyword; consider pointing to a hub card instead")
                            }
                        }
                        FlowLinks(links: entry.links, resolve: resolve, onOpen: { onOpen($0); dismiss() }, onRemove: { onRemove($0, entry.keyword) })
                    }
                    .padding(.vertical, 2)
                    .contextMenu { Button("Remove Keyword", role: .destructive) { onRemove(nil, entry.keyword) } }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 560, height: 520)
    }
}

private struct FlowLinks: View {
    let links: [String]
    let resolve: (String) -> URL?
    let onOpen: (URL) -> Void
    let onRemove: (String) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(links, id: \.self) { link in
                let url = resolve(link)
                Button { if let url { onOpen(url) } } label: {
                    Text((link.split(separator: "|").last.map(String.init) ?? link).components(separatedBy: "/").last ?? link)
                        .font(.system(size: 12)).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(url == nil ? 0.05 : 0.12), in: Capsule())
                        .foregroundStyle(url == nil ? Color.secondary : Color.primary)
                }
                .buttonStyle(.plain)
                .help(url == nil ? "No card named \(link) was found" : "Open \(link)")
                .contextMenu { Button("Remove from This Keyword") { onRemove(link) } }
            }
        }
    }
}
#endif
