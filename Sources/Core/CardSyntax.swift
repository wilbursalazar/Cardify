import Foundation

/// The one definition of the Markdown Kaster reads from cards, used by the library, editor,
/// register, rename, preview and print alike, so they never disagree about a card:
/// - wiki links come from CardLinkParser, which skips code blocks, inline code, escaped
///   brackets and (unless asked) `![[embeds]]`; `WikiTarget` says what a link names;
/// - a #tag is `#` + a letter, then letters, digits, `_`, `-` or `/`, not inside a word, URL
///   fragment or HTML entity;
/// - frontmatter opens with a `---` line and closes with `---` or `...` (trailing spaces allowed).
enum CardSyntax {
    // MARK: Wiki links

    /// What a `[[…]]` link names. `Folder/Card.md#Heading|Label` → path "Folder/Card",
    /// fragment "Heading", alias "Label".
    struct WikiTarget: Equatable {
        /// The card path: trimmed, without ".md" or a leading "/". Empty for `[[#Heading]]`.
        let path: String
        let fragment: String?
        let alias: String?
        /// The text before the alias, as written (`Folder/Card#Heading`).
        let destination: String

        init(_ raw: String) {
            let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            destination = String(parts[0])
            alias = parts.count > 1 ? String(parts[1]) : nil
            let pieces = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            fragment = pieces.count > 1 ? String(pieces[1]) : nil
            var path = String(pieces[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            if path.lowercased().hasSuffix(".md") { path = String(path.dropLast(3)) }
            if path.hasPrefix("/") { path.removeFirst() }
            self.path = path
        }

        /// The card's own name (no folders), as links show it.
        var name: String { (path as NSString).lastPathComponent }
        /// What a link displays: its label, else the card name (with `#Heading`).
        var label: String { alias ?? ((name.isEmpty ? path : name) + (fragment.map { "#" + $0 } ?? "")) }
    }

    struct WikiLink: Equatable {
        /// The whole `[[…]]` (without an embed's `!`).
        let range: NSRange
        /// The text between the brackets.
        let raw: String
        var target: WikiTarget { WikiTarget(raw) }
    }

    /// The card's wiki links, in order. Embeds (`![[…]]`) only with `includeEmbeds`.
    static func wikiLinks(in text: String, includeEmbeds: Bool = false) -> [WikiLink] {
        CardLinkParser.links(in: text, includeEmbeds: includeEmbeds).compactMap { link in
            if case .wiki(let raw) = link.target { return WikiLink(range: link.range, raw: raw) }
            return nil
        }
    }

    // MARK: Tags

    static let tagPattern = try! NSRegularExpression(pattern: "(?<![\\w#&/])#([A-Za-z][\\w/-]*)")

    /// Every #tag in the text, first spelling kept, each once (case-insensitively).
    static func tags(in text: String) -> [String] {
        let ns = text as NSString
        var seen: [String] = []
        for match in tagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1))
            if !seen.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { seen.append(tag) }
        }
        return seen
    }

    /// The first #tag after the frontmatter (a card's Holiday–Greene theme).
    static func firstTag(in text: String) -> String? {
        let body = KasterTypesetter.stripFrontmatter(text)
        guard let match = tagPattern.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)) else { return nil }
        return (body as NSString).substring(with: match.range(at: 1))
    }

    // MARK: Frontmatter

    /// A line that opens frontmatter (the card's first line): `---`, then only spaces or tabs.
    static func isFrontmatterOpening<S: StringProtocol>(_ line: S) -> Bool {
        let value = line.hasPrefix("\u{FEFF}") ? line.dropFirst() : line[...]
        return value.hasPrefix("---") && value.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// A line that closes frontmatter: `---` or `...`, then only spaces or tabs.
    static func isFrontmatterClosing<S: StringProtocol>(_ line: S) -> Bool {
        (line.hasPrefix("---") || line.hasPrefix("...")) && line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
    }
}
