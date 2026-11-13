import Foundation

enum NoteEditing {
    static func title(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var start = 0
        if lines.first == "---", let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) { start = end + 1 }
        for line in lines.dropFirst(start) where line.hasPrefix("# ") { return String(line.dropFirst(2)) }
        return ""
    }
    static func setTitle(_ title: String, in text: String) -> String {
        let safe = title.components(separatedBy: .newlines).joined(separator: " ")
        var lines = text.components(separatedBy: "\n")
        var start = 0
        if lines.first == "---", let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) { start = end + 1 }
        if let index = lines.indices.dropFirst(start).first(where: { lines[$0].hasPrefix("# ") }) { lines[index] = "# " + safe }
        else { lines.insert("# " + safe, at: start); lines.insert("", at: start + 1) }
        return lines.joined(separator: "\n")
    }
    static func addID(_ id: String, to text: String) -> String? {
        if CardMetadata.parse(text).id != nil { return text }
        if CardMetadata.hasNonemptyID(text) { return nil }
        let raw = CardMetadata.frontmatter(id)
        guard !raw.isEmpty else { return nil }
        let idLine = raw.components(separatedBy: "\n")[1]
        var lines = text.components(separatedBy: "\n")
        if lines.first == "---" {
            guard let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return nil }
            if let index = lines.indices.dropFirst().prefix(end - 1).first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("card_id:") }) { lines[index] = idLine }
            else { lines.insert(idLine, at: end) }
            return lines.joined(separator: "\n")
        }
        return raw + text
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
