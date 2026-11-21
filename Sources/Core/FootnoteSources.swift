import Foundation

/// A footnote that names a source: a Zotero item (as Kaster's picker writes it) or a citation typed
/// by hand. Footnotes that only link another card, or explain a point, are not sources.
struct FootnoteSource: Equatable, Identifiable {
    enum Kind: Equatable { case zotero(ZoteroSource), typed }
    let label: String
    let kind: Kind
    /// The definition's text on its first line (after "[^1]: "), trimmed.
    let text: String
    /// UTF-16 range of the definition's text in the card.
    let range: NSRange
    /// The page or location after a Zotero citation ("42", "43–45", "ch. 4").
    let page: String?
    /// True when the footnote reads exactly as Kaster writes it, so its page can be rewritten in place.
    let pageEditable: Bool
    var id: String { label }
    var zotero: ZoteroSource? { if case .zotero(let source) = kind { return source }; return nil }
    /// The citation as plain text, for a chip.
    var title: String { FootnoteSources.plain(zotero?.cite ?? text) }
}

enum FootnoteSources {
    typealias Edit = (range: NSRange, replacement: String)
    struct Definition { let label: String; let text: String; let range: NSRange; let line: NSRange }

    private static let definitionPattern = try! NSRegularExpression(pattern: "^\\[\\^([^\\]\\s]+)\\]:[ \\t]*([^\\r\\n]*)", options: .anchorsMatchLines)
    private static let zoteroLinkPattern = try! NSRegularExpression(pattern: "\\[((?:\\\\.|[^\\]\\\\])*)\\]\\((zotero://[^)\\s]+)\\)")
    private static let itemPattern = try! NSRegularExpression(pattern: "^zotero://(select|open-pdf)/(?:library|groups/([0-9]+))/items/([A-Za-z0-9]+)")

    /// Every footnote definition in the card (the first one for each label).
    static func definitions(in text: String) -> [Definition] {
        guard text.contains("[^") else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        return definitionPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let label = ns.substring(with: match.range(at: 1))
            guard seen.insert(label).inserted else { return nil }
            return Definition(label: label, text: ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces),
                              range: match.range(at: 2), line: ns.lineRange(for: match.range))
        }
    }

    /// The card's sources, in the order their footnotes are defined.
    static func parse(_ text: String) -> [FootnoteSource] {
        definitions(in: text).compactMap(source(from:))
    }

    static func source(from definition: Definition) -> FootnoteSource? {
        let body = definition.text
        if let found = zotero(in: body) {
            return FootnoteSource(label: definition.label, kind: .zotero(found.source), text: body, range: definition.range,
                                  page: found.page, pageEditable: found.editable)
        }
        guard looksLikeCitation(body) else { return nil }
        return FootnoteSource(label: definition.label, kind: .typed, text: body, range: definition.range, page: nil, pageEditable: false)
    }

    /// Reads a Zotero footnote: `[cite](zotero://select/…)`, then the page — a link to the PDF
    /// (`[42](zotero://open-pdf/…?page=42)`) or plain text.
    static func zotero(in body: String) -> (source: ZoteroSource, page: String?, editable: Bool)? {
        let ns = body as NSString
        var select: (match: NSTextCheckingResult, library: String, key: String)?
        var pdf: (key: String, page: String)?
        for match in zoteroLinkPattern.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let url = ns.substring(with: match.range(at: 2)) as NSString
            guard let item = itemPattern.firstMatch(in: url as String, range: NSRange(location: 0, length: url.length)) else { continue }
            let library = item.range(at: 2).location == NSNotFound ? "personal" : url.substring(with: item.range(at: 2))
            let key = url.substring(with: item.range(at: 3))
            if url.substring(with: item.range(at: 1)) == "select" {
                if select == nil { select = (match, library, key) }
            } else if select != nil, pdf == nil {
                pdf = (key, unescape(ns.substring(with: match.range(at: 1))))
            }
        }
        guard let select else { return nil }
        let label = unescape(ns.substring(with: select.match.range(at: 1)))
        let parenthetical = body.hasPrefix("([")
        let source = ZoteroSource(key: select.key, library: select.library, pdf: pdf?.key, cite: parenthetical ? "(" + label + ")" : label)
        var page = pdf?.page
        if pdf == nil {
            var tail = ns.substring(from: NSMaxRange(select.match.range)).trimmingCharacters(in: .whitespaces)
            if tail.hasSuffix(".") { tail.removeLast() }
            if parenthetical, tail.hasSuffix(")") { tail.removeLast() }
            if tail.hasPrefix(",") { tail.removeFirst() }
            tail = tail.trimmingCharacters(in: .whitespaces)
            page = tail.isEmpty ? nil : unescape(tail)
        }
        // Rewriting is safe only when the footnote is what Kaster would write (older Kaster versions
        // ended a quoted title with an extra period).
        var canonical = [ZoteroFootnote.citation(source, page: page)]
        if page == nil { canonical.append("[\(ZoteroFootnote.escapeLabel(source.cite))](\(source.selectURL?.absoluteString ?? "")).") }
        let editable = canonical.contains(body) && (page.map(isLocation) ?? true)
        return (source, editable ? page : pdf?.page, editable)
    }

    /// A page or location ("42", "pp. 43–45", "ch. 4", "vol. 2, p. 14"), not a sentence of commentary.
    static func isLocation(_ text: String) -> Bool {
        text.count <= 24 && !text.contains("[") && text.split(whereSeparator: \.isWhitespace).count <= 4
    }

    /// A typed footnote is a citation when it names an author and then a title in italics or
    /// quotation marks ("Tov, Emanuel. “The Septuagint.” …"), or links a web page. A footnote that
    /// only links another card, or starts with a sentence, is a note rather than a source.
    static func looksLikeCitation(_ text: String) -> Bool {
        let body = text.trimmingCharacters(in: .whitespaces)
        guard !body.contains("[["), body.contains(where: \.isLetter) else { return false }
        if body.range(of: "^\\[[^\\]]+\\]\\(https?://", options: .regularExpression) != nil { return true }
        guard let title = body.firstIndex(where: { "*_\u{201C}\"".contains($0) }) else { return false }
        return body.distance(from: body.startIndex, to: title) <= 60
    }

    /// Reverses ZoteroFootnote.escapeLabel.
    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\[", with: "[").replacingOccurrences(of: "\\]", with: "]")
    }

    /// Markdown citation → plain text: no emphasis marks, escapes or link targets.
    static func plain(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\\\(.)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?<![\\w])[*_]+|[*_]+(?![\\w])", with: "", options: .regularExpression)
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Edits (applied through the text view so ⌘Z undoes them)

    static func apply(_ edits: [Edit], to text: String) -> String {
        let result = NSMutableString(string: text)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) { result.replaceCharacters(in: edit.range, with: edit.replacement) }
        return result as String
    }

    /// Rewrites a Zotero footnote with a new page; with `pdf`, also links the PDF it was missing.
    /// Nil when nothing changes or the footnote was edited by hand beyond Kaster's format.
    static func settingPage(_ page: String?, label: String, pdf: String? = nil, in text: String) -> Edit? {
        guard let found = parse(text).first(where: { $0.label == label }), var source = found.zotero, found.pageEditable else { return nil }
        if source.pdf == nil, let pdf { source.pdf = pdf }
        let page = page?.trimmingCharacters(in: .whitespaces)
        let replacement = ZoteroFootnote.citation(source, page: page?.isEmpty == true ? nil : page)
        return replacement == found.text ? nil : (found.range, replacement)
    }

    /// Once Zotero has named the item's PDF: links the footnote's page to it, if the footnote still
    /// cites that item without one.
    static func linkingPDF(_ pdf: String, label: String, key: String, in text: String) -> Edit? {
        guard let found = parse(text).first(where: { $0.label == label }), let source = found.zotero,
              source.key == key, source.pdf == nil else { return nil }
        return settingPage(found.page, label: label, pdf: pdf, in: text)
    }

    /// Removes a footnote: every `[^label]` marker and its definition line.
    static func removing(label: String, in text: String) -> [Edit] {
        let ns = text as NSString
        let definition = definitions(in: text).first { $0.label == label }
        let marker = try! NSRegularExpression(pattern: "\\[\\^" + NSRegularExpression.escapedPattern(for: label) + "\\](?!:)")
        var edits: [Edit] = marker.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .filter { match in definition.map { NSIntersectionRange($0.line, match.range).length == 0 } ?? true }
            .map { ($0.range, "") }
        if let definition { edits.append((definition.line, "")) }
        return edits
    }

    // MARK: Older Research cards: `zotero` fields in the frontmatter and a "Source:" line

    private static let legacyFields = ["zotero", "zotero-library", "zotero-pdf", "zotero-cite"]
    private static let legacyLinePattern = try! NSRegularExpression(pattern: "^(?:\\[[0-9]+\\][ \\t]*)?Source:[ \\t]*([^\\r\\n]*)", options: .anchorsMatchLines)

    /// A source kept the way Kaster did before footnotes, with the page from its Source line.
    static func legacy(in text: String) -> (source: ZoteroSource, page: String?)? {
        let header = KasterFrontmatter.fields(in: text)
        guard let key = header["zotero"] else { return nil }
        var cite = "", escaping = false
        for character in header["zotero-cite"] ?? "" {
            if escaping { cite.append(character); escaping = false } else if character == "\\" { escaping = true } else { cite.append(character) }
        }
        let source = ZoteroSource(key: key, library: header["zotero-library"] ?? "personal", pdf: header["zotero-pdf"], cite: cite)
        return (source, legacyLine(in: text).flatMap { legacyPage($0.rest, cite: cite) })
    }

    private static func legacyLine(in text: String) -> (line: NSRange, rest: String)? {
        let ns = text as NSString
        guard let match = legacyLinePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return (ns.lineRange(for: match.range), ns.substring(with: match.range(at: 1)))
    }

    /// "Lim, *Title*, 42." → "42"; "(Lim, n.d., 42)." → "42"; "*W*, “Gospels,” 3." → "3".
    static func legacyPage(_ line: String, cite: String) -> String? {
        let clean = cite.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var base = clean.hasPrefix("(") && clean.hasSuffix(")") ? String(clean.dropLast()) : clean
        for quote in ["\u{201D}", "\""] where clean.hasSuffix("." + quote) || clean.hasSuffix("," + quote) { base = String(clean.dropLast(2)) }
        let rest = line.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, rest.hasPrefix(base) else { return nil }
        let page = String(rest.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: " .,)\u{201D}\""))
        return page.isEmpty ? nil : page
    }

    /// Moves an older source into a footnote: the marker at the end of the card's quotation (or of
    /// its last paragraph), the citation at the bottom. The old fields and Source line are removed.
    static func convertingLegacy(_ text: String) -> (text: String, marker: NSRange)? {
        guard let (source, page) = legacy(in: text) else { return nil }
        var result = text
        if let line = legacyLine(in: result) { result = (result as NSString).replacingCharacters(in: line.line, with: "") }
        for field in legacyFields { if let updated = KasterFrontmatter.setting(field, to: nil, in: result) { result = updated } }
        if result.hasPrefix("---\n---\n") { result.removeFirst(8) }   // nothing else was in the frontmatter
        while result.hasSuffix("\n") || result.hasSuffix(" ") { result.removeLast() }
        let lines = result.components(separatedBy: "\n")
        let body = KasterFrontmatter.fields(in: result).isEmpty ? 0 : (lines.dropFirst().firstIndex { $0.trimmingCharacters(in: .whitespaces) == "---" } ?? 0) + 1
        let quoteStart = lines.indices.first { $0 >= body && lines[$0].hasPrefix(">") }
        var target = lines.indices.last { $0 >= body && !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty && !lines[$0].hasPrefix("[^") }
        if let quoteStart {
            let run = lines[quoteStart...].prefix { $0.hasPrefix(">") }.indices
            target = run.last { lines[$0].dropFirst().trimmingCharacters(in: .whitespaces).isEmpty == false } ?? target
        }
        guard let target else { return nil }
        let label = ZoteroFootnote.nextLabel(in: result)
        let marker = "[^\(label)]"
        let lineStart = lines[..<target].reduce(0) { $0 + ($1 as NSString).length + 1 }
        let location = lineStart + (lines[target].replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) as NSString).length
        let withMarker = (result as NSString).replacingCharacters(in: NSRange(location: location, length: 0), with: marker) + "\n"
        let final = withMarker + ZoteroFootnote.appendix(label: label, citation: ZoteroFootnote.citation(source, page: page), to: withMarker)
        return (final, NSRange(location: location, length: (marker as NSString).length))
    }
}

/// One source in the vault's bibliography, with the cards whose footnotes cite it.
struct BibliographyEntry: Identifiable {
    let id: String
    var zotero: ZoteroSource?
    /// Markdown: Zotero's short citation, or the typed citation without its page.
    var text: String
    var cards: [LibraryCard]
}

enum FootnoteBibliography {
    /// Every source cited in footnotes across the cards, A–Z, each listing its citing cards.
    static func collect(_ cards: [LibraryCard]) -> [BibliographyEntry] {
        var entries: [String: BibliographyEntry] = [:]
        for card in cards where card.content.contains("[^") {
            for source in FootnoteSources.parse(card.content) {
                let id: String, text: String
                if let zotero = source.zotero { id = "zotero:\(zotero.library)/\(zotero.key)"; text = zotero.cite }
                else { text = withoutPage(source.text); id = "typed:" + normalized(text) }
                var entry = entries[id] ?? BibliographyEntry(id: id, zotero: source.zotero, text: text, cards: [])
                if entry.zotero?.pdf == nil, let pdf = source.zotero?.pdf { entry.zotero?.pdf = pdf }
                if !entry.cards.contains(where: { $0.path == card.path }) { entry.cards.append(card) }
                entries[id] = entry
            }
        }
        return entries.values.map { entry in
            var entry = entry
            entry.cards.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return entry
        }.sorted { sortKey($0.text).localizedStandardCompare(sortKey($1.text)) == .orderedAscending }
    }

    /// "Archer, *Quotations*, 25-32" → "Archer, *Quotations*." (one entry however many pages are cited).
    static func withoutPage(_ text: String) -> String {
        var result = text.replacingOccurrences(of: ",\\s*(?:pp?\\.\\s*)?(?:[0-9]+|[ivxlcdm]+)(?:\\s*[–—-]\\s*(?:[0-9]+|[ivxlcdm]+))?\\s*\\.?\\s*$",
                                               with: "", options: [.regularExpression, .caseInsensitive])
        result = result.trimmingCharacters(in: .whitespaces)
        if let last = result.last, !".!?\u{201D}\"".contains(last) { result += "." }
        return result
    }

    static func normalized(_ text: String) -> String {
        FootnoteSources.plain(text).lowercased().replacingOccurrences(of: "[\u{201C}\u{201D}\"'.,]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// Alphabetical by author: ignores emphasis, quotation marks and parentheses.
    static func sortKey(_ text: String) -> String {
        FootnoteSources.plain(text).trimmingCharacters(in: CharacterSet(charactersIn: "(\u{201C}\"' ")).lowercased()
    }

    /// Bibliography cards for printing, about `perCard` entries per 3×5 card, headed with their letters.
    static func printCards(_ entries: [String], perCard: Int = 5) -> [String] {
        guard !entries.isEmpty else { return [] }
        let single = entries.count <= perCard
        return stride(from: 0, to: entries.count, by: perCard).map { start in
            let chunk = Array(entries[start..<min(start + perCard, entries.count)])
            let first = sortKey(chunk.first!).prefix(1).uppercased(), last = sortKey(chunk.last!).prefix(1).uppercased()
            let title = single ? "Bibliography" : first == last ? "Bibliography \(first)" : "Bibliography \(first)–\(last)"
            return "# \(title)\n\n" + chunk.joined(separator: "\n\n") + "\n"
        }
    }
}
