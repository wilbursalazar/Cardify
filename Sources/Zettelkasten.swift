import SwiftUI
import AppKit

// card_id is stored in ordinary YAML frontmatter; existing files are never renamed.
enum CardMetadata {
    static func parse(_ text: String) -> (id: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return (nil, text) }
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("card_id:") else { continue }
            let value = String(trimmed.dropFirst("card_id:".count)).trimmingCharacters(in: .whitespaces)
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
            return (id, lines.dropFirst(end + 1).joined(separator: "\n"))
        }
        return (nil, text)
    }
    static func hasNonemptyID(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return false }
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("card_id:") {
                let raw = String(trimmed.dropFirst("card_id:".count)).trimmingCharacters(in: .whitespaces)
                return !raw.isEmpty && raw != "\"\"" && raw != "''" && !raw.hasPrefix("#")
            }
        }
        return false
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

