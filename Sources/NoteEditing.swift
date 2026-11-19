import Foundation

enum NoteEditing {
    // An Obsidian file may have a YAML title without a Markdown H1.
    // Keep the file untouched when merely displaying its title.
    static func title(in text: String, fileURL: URL?) -> String {
        let explicit = title(in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        return explicit.isEmpty ? (fileURL?.deletingPathExtension().lastPathComponent ?? "") : explicit
    }

    private static func yamlTitleLine(_ lines: MarkdownSource.Lines) -> (range: NSRange, raw: String)? {
        guard let end = lines.frontmatterEnd else { return nil }
        let matches = lines.values[1..<end].compactMap { line -> (range: NSRange, raw: String)? in
            let content = lines.source.substring(with: line.content)
            guard content.hasPrefix("title:") else { return nil }
            return (line.content, String(content.dropFirst("title:".count)))
        }
        // Ambiguous properties should not be automatically rewritten.
        return matches.count == 1 ? matches[0] : nil
    }

    private static func decodeYAMLTitle(_ raw: String) -> String {
        let candidate = raw.trimmingCharacters(in: .whitespaces)
        if candidate.hasPrefix("\"") {
            // Match an ordinary JSON-compatible YAML double-quoted scalar.
            var closing = false, escaped = false
            for (index, character) in candidate.enumerated() where index > 0 {
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" { closing = true; break }
            }
            guard closing, let lastQuote = candidate.indices.dropFirst().first(where: { index in
                candidate[index] == "\"" && candidate[candidate.index(before: index)] != "\\"
            }) else { return "" }
            let quoted = String(candidate[...lastQuote])
            guard let decoded = try? JSONDecoder().decode(String.self, from: Data(quoted.utf8)) else { return "" }
            return decoded
        }
        if candidate.hasPrefix("'") {
            guard let end = candidate.dropFirst().firstIndex(of: "'") else { return "" }
            return String(candidate[candidate.index(after: candidate.startIndex)..<end]).replacingOccurrences(of: "''", with: "'")
        }
        return String(candidate.components(separatedBy: " #").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func title(in text: String) -> String {
        let lines = MarkdownSource.lines(in: text)
        if lines.hasFrontmatterStart && lines.frontmatterEnd == nil { return "" }
        if let property = yamlTitleLine(lines) {
            let metadataTitle = decodeYAMLTitle(property.raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if !metadataTitle.isEmpty { return metadataTitle }
        }
        let start = lines.frontmatterEnd.map { $0 + 1 } ?? 0
        for index in lines.values.indices.dropFirst(start) {
            let line = lines.values[index].content
            let bom = index == 0 ? lines.bomLength : 0
            let content = lines.source.substring(with: NSRange(location: line.location + bom, length: line.length - bom))
            if content.hasPrefix("# ") { return String(content.dropFirst(2)) }
        }
        return ""
    }
    static func setTitle(_ title: String, in text: String) -> String {
        let safe = title.components(separatedBy: .newlines).joined(separator: " ")
        let lines = MarkdownSource.lines(in: text)
        // An unterminated header may contain YAML comments that look like titles.
        guard !lines.hasFrontmatterStart || lines.frontmatterEnd != nil else { return text }
        if let property = yamlTitleLine(lines),
           let encoded = try? JSONEncoder().encode(safe),
           let quoted = String(data: encoded, encoding: .utf8) {
            let suffix = trailingCommentOrWhitespace(property.raw)
            return lines.source.replacingCharacters(in: property.range, with: "title: " + quoted + suffix)
        }
        let start = lines.frontmatterEnd.map { $0 + 1 } ?? 0
        for index in lines.values.indices.dropFirst(start) {
            let line = lines.values[index].content
            let bom = index == 0 ? lines.bomLength : 0
            let range = NSRange(location: line.location + bom, length: line.length - bom)
            if lines.source.substring(with: range).hasPrefix("# ") {
                return lines.source.replacingCharacters(in: range, with: "# " + safe)
            }
        }
        let location: Int
        let before: String
        if let end = lines.frontmatterEnd {
            let closing = lines.values[end]
            location = NSMaxRange(closing.full)
            before = NSMaxRange(closing.content) == location ? lines.newline : ""
        } else {
            location = lines.bomLength
            before = ""
        }
        return lines.source.replacingCharacters(in: NSRange(location: location, length: 0), with: before + "# " + safe + lines.newline + lines.newline)
    }
    static func addID(_ id: String, to text: String) -> String? {
        if CardMetadata.parse(text).id != nil { return text }
        if CardMetadata.hasNonemptyID(text) { return nil }
        guard !CardMetadata.frontmatter(id).isEmpty else { return nil }
        return setID(id, in: text)
    }
    // Edit only the card_id property; preserve all other frontmatter and note text.
    static func setID(_ id: String, in text: String) -> String? {
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.contains(where: { $0.isNewline }) else { return nil }
        let lines = MarkdownSource.lines(in: text)
        if lines.hasFrontmatterStart {
            guard let end = lines.frontmatterEnd else { return nil }
            let indices = lines.values.indices.dropFirst().prefix(end - 1).filter {
                lines.source.substring(with: lines.values[$0].content).hasPrefix("card_id:")
            }
            guard indices.count <= 1 else { return nil }
            if clean.isEmpty {
                guard let index = indices.first else { return text }
                let updated = lines.source.replacingCharacters(in: lines.values[index].full, with: "")
                let remaining = MarkdownSource.lines(in: updated)
                if remaining.frontmatterEnd == 1 {
                    var finish = NSMaxRange(remaining.values[1].full)
                    if remaining.values.count > 2 && remaining.values[2].content.length == 0 { finish = NSMaxRange(remaining.values[2].full) }
                    return remaining.source.replacingCharacters(in: NSRange(location: remaining.bomLength, length: finish - remaining.bomLength), with: "")
                }
                return updated
            }
            guard let encoded = try? JSONEncoder().encode(clean), let quoted = String(data: encoded, encoding: .utf8) else { return nil }
            if let index = indices.first {
                let line = lines.values[index].content
                let original = lines.source.substring(with: line)
                guard let colon = original.range(of: "card_id:") else { return nil }
                let prefixEnd = original[colon.upperBound...].firstIndex(where: { !$0.isWhitespace }) ?? original.endIndex
                let prefix = String(original[..<prefixEnd])
                let value = String(original[prefixEnd...])
                let suffix = trailingCommentOrWhitespace(value)
                let separator = prefix.last?.isWhitespace == true ? "" : " "
                return lines.source.replacingCharacters(in: line, with: prefix + separator + quoted + suffix)
            }
            return lines.source.replacingCharacters(in: NSRange(location: lines.values[end].content.location, length: 0), with: "card_id: " + quoted + lines.newline)
        }
        guard !clean.isEmpty else { return text }
        let header = CardMetadata.frontmatter(clean).replacingOccurrences(of: "\n", with: lines.newline)
        guard !header.isEmpty else { return nil }
        return lines.source.replacingCharacters(in: NSRange(location: lines.bomLength, length: 0), with: header)
    }
    // Keep any inline YAML comment (and its spacing) when the ID is changed.
    private static func trailingCommentOrWhitespace(_ value: String) -> String {
        var quote: Character?
        var escaped = false
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if escaped { escaped = false; index = value.index(after: index); continue }
            if quote == "\"" && character == "\\" { escaped = true; index = value.index(after: index); continue }
            if let active = quote {
                if character == active {
                    if active == "'" {
                        let next = value.index(after: index)
                        if next < value.endIndex && value[next] == "'" { index = value.index(after: next); continue }
                    }
                    quote = nil
                }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "#" && (index == value.startIndex || value[value.index(before: index)].isWhitespace) {
                var start = index
                while start > value.startIndex && value[value.index(before: start)].isWhitespace { start = value.index(before: start) }
                let suffix = String(value[start...])
                return start == value.startIndex ? " " + suffix : suffix
            }
            index = value.index(after: index)
        }
        var start = value.endIndex
        while start > value.startIndex && value[value.index(before: start)].isWhitespace { start = value.index(before: start) }
        return String(value[start...])
    }
    static func filename(id: String?, title: String) -> String {
        func clean(_ input: String) -> String {
            let prohibited = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
            let result = input.components(separatedBy: prohibited).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
            return result.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        let safeID = clean(id ?? "")
        let safeTitle = clean(title)
        let base = [safeID, safeTitle].filter { !$0.isEmpty }.joined(separator: " ")
        var short = ""
        for character in (base.isEmpty ? "Index Card" : base) {
            if (short + String(character)).utf8.count > 220 { break }
            short.append(character)
        }
        return short + ".md"
    }
}
