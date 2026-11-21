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


    /// The entry on one line, or nil if the line isn't a register entry.
    static func entry(in line: String) -> Entry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- "), let colon = trimmed.firstIndex(of: ":") else { return nil }
        let keyword = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colon].trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, !keyword.contains("[[") else { return nil }
        let rest = String(trimmed[trimmed.index(after: colon)...])
        let links = CardSyntax.wikiLinks(in: rest).map(\.raw)
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
