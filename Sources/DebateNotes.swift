import Foundation

// Debate notes remain ordinary Markdown. Markers identify the kind of a note;
// visible wiki links keep its connections usable in the editor and Obsidian.
enum DebateRole: String, CaseIterable {
    case project, aff, def, evidence, objection, argument, reply
}

struct DebateRelation: Equatable {
    let path: String
    let explanation: String
}

struct DebateInfo {
    let role: DebateRole?
    let projects: [DebateRelation]
    let primary: DebateRelation?
    let related: [DebateRelation]
    let valid: Bool
}

enum DebateNotes {
    private enum Field { case role, project, primary, related }
    private struct Item {
        let field: Field
        let line: NSRange
        let full: NSRange
        let relation: DebateRelation?
        let role: DebateRole?
    }
    private struct Document {
        let source: NSString
        let items: [Item]
        let valid: Bool
        let newline: String
    }

    // Links are vault-relative paths, using the same characters the note picker
    // permits. Reject traversal and absolute paths instead of resolving them.
    static func validPath(_ path: String) -> Bool {
        guard !path.isEmpty, path == path.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.hasPrefix("/"), !path.contains("%%"),
              !path.contains(where: { "[]|#^:\n\r\\".contains($0) }) else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func document(_ text: String) -> Document {
        let source = text as NSString
        var items: [Item] = []
        var valid = true
        var offset = 0
        var firstNewline: String?
        var fence: (unichar, Int)?
        var frontmatter = false
        var firstLine = true
        var htmlComment = false
        func scanComments(_ value: String) {
            var cursor = value.startIndex
            while cursor < value.endIndex {
                let marker = htmlComment ? "-->" : "<!--"
                guard let range = value.range(of: marker, range: cursor..<value.endIndex) else { return }
                htmlComment.toggle()
                cursor = range.upperBound
            }
        }
        while offset < source.length {
            let full = source.lineRange(for: NSRange(location: offset, length: 0))
            var end = NSMaxRange(full)
            while end > full.location && (source.character(at: end - 1) == 10 || source.character(at: end - 1) == 13) { end -= 1 }
            if firstNewline == nil && end < NSMaxRange(full) {
                firstNewline = source.substring(with: NSRange(location: end, length: NSMaxRange(full) - end))
            }
            var start = full.location
            if start == 0 && source.character(at: start) == 0xFEFF { start += 1 }
            let line = NSRange(location: start, length: end - start)
            let value = source.substring(with: line)
            let delimiter = value.hasPrefix("---") && value.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
            if firstLine {
                firstLine = false
                if delimiter { frontmatter = true; offset = NSMaxRange(full); continue }
            } else if frontmatter {
                if delimiter { frontmatter = false }
                offset = NSMaxRange(full); continue
            }
            if htmlComment {
                scanComments(value)
                offset = NSMaxRange(full); continue
            }
            let trimmed = value.drop(while: { $0 == " " })
            let indent = value.count - trimmed.count
            if indent <= 3, let first = trimmed.utf16.first, first == 96 || first == 126 {
                let count = trimmed.utf16.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if let current = fence {
                        if current.0 == first && count >= current.1 && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    } else { fence = (first, count) }
                    offset = NSMaxRange(full); continue
                }
            }
            if fence != nil { offset = NSMaxRange(full); continue }
            // An ordinary multi-line HTML comment may contain examples that
            // look like relationships; they are not active note metadata.
            if value.hasPrefix("<!-- cardify:debate=") {
                let prefix = "<!-- cardify:debate="
                guard value.hasSuffix(" -->"), let role = DebateRole(rawValue: String(value.dropFirst(prefix.count).dropLast(4))) else {
                    valid = false; offset = NSMaxRange(full); continue
                }
                items.append(Item(field: .role, line: line, full: full, relation: nil, role: role))
            } else {
                scanComments(value)
                let fields: [(String, Field)] = [("Debate project: ", .project), ("Primary parent: ", .primary), ("Related parent: ", .related)]
                if let (prefix, field) = fields.first(where: { value.hasPrefix($0.0) }) {
                    let remainder = String(value.dropFirst(prefix.count))
                    guard remainder.hasPrefix("[["), let close = remainder.range(of: "]]"), close.lowerBound > remainder.index(remainder.startIndex, offsetBy: 2) else {
                        valid = false; offset = NSMaxRange(full); continue
                    }
                    let path = String(remainder[remainder.index(remainder.startIndex, offsetBy: 2)..<close.lowerBound])
                    let suffix = String(remainder[close.upperBound...])
                    guard validPath(path), suffix.isEmpty || suffix.hasPrefix(" — "), field != .project || suffix.isEmpty else {
                        valid = false; offset = NSMaxRange(full); continue
                    }
                    let explanation = suffix.isEmpty ? "" : String(suffix.dropFirst(3))
                    items.append(Item(field: field, line: line, full: full, relation: DebateRelation(path: path, explanation: explanation), role: nil))
                }
            }
            offset = NSMaxRange(full)
        }
        // Appending into an unfinished YAML or fenced-code block would make
        // the new relationship part of that block instead of a note link.
        if frontmatter || fence != nil || htmlComment { valid = false }
        if items.filter({ $0.field == .role }).count > 1 || items.filter({ $0.field == .primary }).count > 1 { valid = false }
        for field in [Field.project, .related] {
            var seen: Set<String> = []
            for item in items where item.field == field {
                guard let relation = item.relation else { valid = false; continue }
                if !seen.insert(relation.path.lowercased()).inserted { valid = false }
            }
        }
        if let primary = items.first(where: { $0.field == .primary })?.relation,
           items.contains(where: { $0.field == .related && $0.relation?.path.caseInsensitiveCompare(primary.path) == .orderedSame }) { valid = false }
        return Document(source: source, items: items, valid: valid, newline: firstNewline ?? "\n")
    }

    static func parse(_ text: String) -> DebateInfo {
        let doc = document(text)
        return DebateInfo(role: doc.items.first(where: { $0.field == .role })?.role,
                          projects: doc.items.filter { $0.field == .project }.compactMap(\.relation),
                          primary: doc.items.first(where: { $0.field == .primary })?.relation,
                          related: doc.items.filter { $0.field == .related }.compactMap(\.relation),
                          valid: doc.valid)
    }
    private static func line(_ prefix: String, path: String, explanation: String = "") -> String {
        let clean = explanation.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "[[" + path + "]]" + (clean.isEmpty ? "" : " — " + clean)
    }
    private static func append(_ line: String, to doc: Document) -> String {
        let text = doc.source as String
        let separator = text.isEmpty || text.hasSuffix("\n") || text.hasSuffix("\r") ? "" : doc.newline
        return text + separator + line + doc.newline
    }
    private static func remove(_ item: Item, from doc: Document) -> String {
        // An initial BOM belongs to the file, not to its first metadata line.
        let range = NSRange(location: item.line.location, length: NSMaxRange(item.full) - item.line.location)
        return doc.source.replacingCharacters(in: range, with: "")
    }
    private static func checked(_ text: String) -> String? {
        // User-supplied paths and explanations must not create a malformed
        // comment or a new unterminated YAML/code block in the resulting note.
        document(text).valid ? text : nil
    }
    static func setRole(_ role: DebateRole, in text: String) -> String? {
        let doc = document(text)
        guard doc.valid else { return nil }
        let value = "<!-- cardify:debate=\(role.rawValue) -->"
        if let item = doc.items.first(where: { $0.field == .role }) {
            return checked(doc.source.replacingCharacters(in: item.line, with: value))
        }
        return checked(append(value, to: doc))
    }
    static func addProject(_ path: String, in text: String) -> String? {
        let doc = document(text)
        guard doc.valid, validPath(path), !doc.items.contains(where: { $0.field == .project && $0.relation?.path.caseInsensitiveCompare(path) == .orderedSame }) else { return nil }
        return checked(append(line("Debate project: ", path: path), to: doc))
    }
    static func removeProject(_ path: String, in text: String) -> String? {
        let doc = document(text)
        guard doc.valid else { return nil }
        guard let item = doc.items.first(where: { $0.field == .project && $0.relation?.path.caseInsensitiveCompare(path) == .orderedSame }) else { return text }
        return checked(remove(item, from: doc))
    }
    static func setPrimary(_ path: String?, explanation: String, in text: String) -> String? {
        let doc = document(text)
        guard doc.valid else { return nil }
        let current = doc.items.first(where: { $0.field == .primary })
        guard let path else {
            // A connected card cannot have secondary parents without a primary.
            guard !doc.items.contains(where: { $0.field == .related }) else { return nil }
            guard let current else { return text }
            return checked(remove(current, from: doc))
        }
        guard validPath(path), !doc.items.contains(where: { $0.field == .related && $0.relation?.path.caseInsensitiveCompare(path) == .orderedSame }) else { return nil }
        let value = line("Primary parent: ", path: path, explanation: explanation)
        if let current { return checked(doc.source.replacingCharacters(in: current.line, with: value)) }
        return checked(append(value, to: doc))
    }
    static func addRelated(_ path: String, explanation: String, in text: String) -> String? {
        let doc = document(text)
        guard doc.valid, validPath(path), doc.items.contains(where: { $0.field == .primary }), !doc.items.contains(where: { ($0.field == .primary || $0.field == .related) && $0.relation?.path.caseInsensitiveCompare(path) == .orderedSame }) else { return nil }
        return checked(append(line("Related parent: ", path: path, explanation: explanation), to: doc))
    }
    static func removeRelated(_ path: String, in text: String) -> String? {
        let doc = document(text)
        guard doc.valid else { return nil }
        guard let item = doc.items.first(where: { $0.field == .related && $0.relation?.path.caseInsensitiveCompare(path) == .orderedSame }) else { return text }
        return checked(remove(item, from: doc))
    }
}
