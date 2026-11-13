import SwiftUI

// The marker is optional YAML metadata. It never changes a file by itself.
enum IndexCardMetadata {
    private static let key = try! NSRegularExpression(pattern: #"^(?:cardify_index|'cardify_index'|"cardify_index")[ \t]*:"#)
    private static let mapping = try! NSRegularExpression(pattern: #"^(?:[A-Za-z_][A-Za-z0-9_. -]*|'(?:[^']|'')+'|"(?:[^"\\]|\\.)+"):(?:[ \t]|$)"#)
    private static let boolean = try! NSRegularExpression(pattern: #"^(cardify_index[ \t]*:[ \t]*)(true|false)([ \t]*(?:#.*)?)$"#, options: .caseInsensitive)

    private static func range(_ line: String) -> NSRange { NSRange(line.startIndex..., in: line) }

    private static func newline(in text: String) -> String {
        let source = text as NSString
        let end = source.range(of: "\n").location
        guard end != NSNotFound, end > 0 else { return "\n" }
        return source.character(at: end - 1) == 13 ? "\r\n" : "\n"
    }

    // Return the YAML lines and the closing delimiter, if frontmatter is present.
    private static func frontmatter(_ text: String) -> (lines: [String], end: Int, newline: String)? {
        let newline = newline(in: text)
        let lines = text.components(separatedBy: newline)
        func delimiter(_ line: String) -> Bool {
            line.hasPrefix("---") && line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
        }
        guard let first = lines.first, delimiter(first), let end = lines.indices.dropFirst().first(where: { delimiter(lines[$0]) }) else { return nil }
        return (lines, end, newline)
    }

    // A pair of Markdown horizontal rules can look like frontmatter. Only accept
    // a top-level mapping; otherwise adding the marker could hide ordinary prose.
    // Indented lines may contain nested collections or multiline scalar content.
    private static func isMapping(_ front: (lines: [String], end: Int, newline: String)) -> Bool {
        var hasKey = false
        for line in front.lines[1..<front.end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if line.hasPrefix(" ") {
                // The card renderer treats an indented --- as the end of frontmatter.
                // Refuse it rather than hide or misprint part of a block value.
                if !hasKey || trimmed == "---" || key.firstMatch(in: trimmed, range: range(trimmed)) != nil { return false }
                continue
            }
            guard mapping.firstMatch(in: line, range: range(line)) != nil else { return false }
            hasKey = true
        }
        return hasKey
    }

    static func isIndex(_ text: String) -> Bool {
        guard let front = frontmatter(text), isMapping(front) else { return false }
        let keys = (1..<front.end).filter { key.firstMatch(in: front.lines[$0], range: range(front.lines[$0])) != nil }
        guard keys.count == 1 else { return false }
        let line = front.lines[keys[0]]
        guard let match = boolean.firstMatch(in: line, range: range(line)), let value = Range(match.range(at: 2), in: line) else { return false }
        return line[value].lowercased() == "true"
    }

    // Refuse malformed frontmatter, repeated keys and non-boolean values instead of overwriting them.
    static func marking(_ text: String) -> String? {
        guard !text.hasPrefix("\u{FEFF}") else { return nil }
        let newline = newline(in: text)
        let startsFrontmatter = text.components(separatedBy: newline).first?.trimmingCharacters(in: .whitespaces) == "---"
        guard startsFrontmatter else { return "---\(newline)cardify_index: true\(newline)---\(newline)" + text }
        guard let front = frontmatter(text), isMapping(front) else { return nil }
        var lines = front.lines
        let keys = (1..<front.end).filter { key.firstMatch(in: lines[$0], range: range(lines[$0])) != nil }
        guard keys.count <= 1 else { return nil }
        if let index = keys.first {
            let line = lines[index]
            guard let match = boolean.firstMatch(in: line, range: range(line)), let value = Range(match.range(at: 2), in: line) else { return nil }
            if line[value].lowercased() == "true" { return text }
            lines[index].replaceSubrange(value, with: "true")
        } else {
            lines.insert("cardify_index: true", at: front.end)
        }
        return lines.joined(separator: front.newline)
    }
}

// Each indexed topic is an ordinary Markdown note with the explicit marker above.
struct CuratedIndexView: View {
    let cards: [LibraryCard]
    let onOpen: (URL) -> Void
    let onRefresh: () -> Void
    @State private var query = ""
    private var indexCards: [LibraryCard] {
        let all = cards.filter { IndexCardMetadata.isIndex($0.content) }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? all : all.filter {
            $0.title.localizedStandardContains(search) || $0.path.localizedStandardContains(search) || ($0.cardID?.localizedStandardContains(search) ?? false) || $0.content.localizedStandardContains(search)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search index cards", text: $query)
                Button("Refresh", action: onRefresh)
            }
            Text("Index cards hold selected links to starting points for a topic.")
                .font(.caption).foregroundStyle(.secondary)
            if indexCards.isEmpty {
                Text(query.isEmpty ? "No index cards yet. Use the Index Card template, or mark an open note as an index card, then save it." : "No index cards match this search.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(indexCards) { card in
                    Button { onOpen(card.url) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title).fontWeight(.medium)
                            Text(card.cardID.map { "\($0) · \(card.path)" } ?? card.path)
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
