import SwiftUI
import AppKit

// Keep exact line ranges so edits preserve the note's existing line endings.
enum MarkdownSource {
    struct Line {
        let content: NSRange
        let full: NSRange
    }
    struct Lines {
        let source: NSString
        let values: [Line]
        let hasFrontmatterStart: Bool
        let frontmatterEnd: Int?
        let bomLength: Int
        let newline: String
    }

    static func lines(in text: String) -> Lines {
        let source = text as NSString
        var result: [Line] = []
        var offset = 0
        var newline: String?
        while offset < source.length {
            let full = source.lineRange(for: NSRange(location: offset, length: 0))
            var end = NSMaxRange(full)
            while end > full.location {
                let ch = source.character(at: end - 1)
                guard ch == 10 || ch == 13 else { break }
                end -= 1
            }
            if newline == nil && end < NSMaxRange(full) {
                newline = source.substring(with: NSRange(location: end, length: NSMaxRange(full) - end))
            }
            result.append(Line(content: NSRange(location: full.location, length: end - full.location), full: full))
            offset = NSMaxRange(full)
        }
        let bomLength = source.length > 0 && source.character(at: 0) == 0xFEFF ? 1 : 0
        func isDelimiter(_ line: Line, first: Bool) -> Bool {
            let extra = first ? bomLength : 0
            guard line.content.length >= extra else { return false }
            let range = NSRange(location: line.content.location + extra, length: line.content.length - extra)
            let value = source.substring(with: range)
            return value.hasPrefix("---") && value.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
        }
        let starts = result.first.map { isDelimiter($0, first: true) } ?? false
        let end = starts ? result.indices.dropFirst().first(where: { isDelimiter(result[$0], first: false) }) : nil
        return Lines(source: source, values: result, hasFrontmatterStart: starts, frontmatterEnd: end, bomLength: bomLength, newline: newline ?? "\n")
    }
}

// card_id is stored in ordinary YAML frontmatter; existing files are never renamed.
enum CardMetadata {
    static func parse(_ text: String) -> (id: String?, body: String) {
        let lines = MarkdownSource.lines(in: text)
        guard let end = lines.frontmatterEnd else { return (nil, text) }
        let idLines = lines.values[1..<end].filter { lines.source.substring(with: $0.content).hasPrefix("card_id:") }
        guard idLines.count <= 1 else { return (nil, text) }
        for line in idLines {
            let trimmed = lines.source.substring(with: line.content).trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("card_id:") else { continue }
            let value = valueWithoutComment(String(trimmed.dropFirst("card_id:".count)))
            let id: String
            if value.hasPrefix("\"") {
                guard let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) else { return (nil, text) }
                id = decoded
            } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                id = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            } else {
                id = value.components(separatedBy: " #").first?.trimmingCharacters(in: .whitespaces) ?? ""
            }
            guard !id.isEmpty else { return (nil, text) }
            return (id, lines.source.substring(from: NSMaxRange(lines.values[end].full)))
        }
        return (nil, IndexCardMetadata.isIndex(text) ? lines.source.substring(from: NSMaxRange(lines.values[end].full)) : text)
    }
    static func hasNonemptyID(_ text: String) -> Bool {
        let lines = MarkdownSource.lines(in: text)
        guard lines.hasFrontmatterStart else { return false }
        let end = lines.frontmatterEnd ?? lines.values.count
        let idLines = lines.values[1..<end].filter { lines.source.substring(with: $0.content).hasPrefix("card_id:") }
        if idLines.count > 1 { return true }
        for line in idLines {
            let trimmed = lines.source.substring(with: line.content).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("card_id:") {
                let raw = valueWithoutComment(String(trimmed.dropFirst("card_id:".count)))
                return !raw.isEmpty && raw != "\"\"" && raw != "''" && !raw.hasPrefix("#")
            }
        }
        return false
    }
    private static func valueWithoutComment(_ value: String) -> String {
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
                return String(value[..<index]).trimmingCharacters(in: .whitespaces)
            }
            index = value.index(after: index)
        }
        return value.trimmingCharacters(in: .whitespaces)
    }
    static func frontmatter(_ id: String) -> String {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, let data = try? JSONEncoder().encode(id), let encoded = String(data: data, encoding: .utf8) else { return "" }
        return "---\ncard_id: \(encoded)\n---\n\n"
    }
}

enum CardIDIndex {
    enum ScanError: LocalizedError {
        case inaccessible
        case invalidMetadata(String)
        var errorDescription: String? {
            switch self {
            case .inaccessible: return "The notes folder could not be fully read."
            case .invalidMetadata(let file): return "The card_id in \(file) could not be read."
            }
        }
    }
    static func ids(in root: URL, excluding target: URL? = nil) throws -> [(String, URL)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        var encounteredError = false
        guard FileManager.default.isReadableFile(atPath: root.path),
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in encounteredError = true; return false }) else { throw ScanError.inaccessible }
        var result: [(String, URL)] = []
        for case let url as URL in enumerator {
            let properties = try url.resourceValues(forKeys: Set(keys))
            if properties.isSymbolicLink == true || properties.isRegularFile != true || url.pathExtension.lowercased() != "md" { continue }
            if url.standardizedFileURL == target?.standardizedFileURL { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let metadataID = CardMetadata.parse(text).id
            if let id = metadataID { result.append((id, url)) }
            else if CardMetadata.hasNonemptyID(text) { throw ScanError.invalidMetadata(url.lastPathComponent) }
            if let filenameID = BranchIDs.filenameID(for: url), filenameID.caseInsensitiveCompare(metadataID ?? "") != .orderedSame { result.append((filenameID, url)) }
            else if metadataID == nil, let filenameID = BranchIDs.luhmannFilenameID(for: url) { result.append((filenameID, url)) }
        }
        if encounteredError { throw ScanError.inaccessible }
        return result
    }
    static func suggest(in root: URL?) -> String {
        let existing = (root.flatMap { try? ids(in: $0) } ?? []).map { $0.0.lowercased() }
        var n = 1
        while existing.contains(String(format: "c-%04d", n)) { n += 1 }
        return String(format: "C-%04d", n)
    }
}

