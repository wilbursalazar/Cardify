import Foundation

// Timestamp-based root IDs and alternating letter/number branch markers.
enum BranchIDs {
    enum BranchError: LocalizedError {
        case missingParent
        var errorDescription: String? { "Add a card ID to the current card before creating a branch." }
    }

    static func timestamp(at date: Date = Date(), timeZone: TimeZone = .current, existing: Set<String>) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = timeZone
        format.dateFormat = "yyyyMMddHHmm"
        let base = format.string(from: date)
        let used = Set(existing.map { $0.lowercased() })
        guard used.contains(base.lowercased()) else { return base }
        var counter = 2
        while used.contains((base + "-" + String(format: "%02d", counter)).lowercased()) { counter += 1 }
        return base + "-" + String(format: "%02d", counter)
    }

    // A branch appends a new component: 1 -> 1a; 1a -> 1a1.
    // Sibling collisions are resolved deterministically, without changing existing IDs.
    static func branch(from parent: String, existing: Set<String>) throws -> String {
        let clean = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw BranchError.missingParent }
        let used = Set(existing.map { $0.lowercased() })
        let scalar = clean.unicodeScalars.last!
        if (65...90).contains(scalar.value) || (97...122).contains(scalar.value) {
            var number = 1
            while used.contains((clean + String(number)).lowercased()) { number += 1 }
            return clean + String(number)
        }
        let separator = (48...57).contains(scalar.value) ? "" : "-"
        var number = 1
        while true {
            var n = number
            var suffix = ""
            while n > 0 {
                n -= 1
                suffix = String(UnicodeScalar(97 + n % 26)!) + suffix
                n /= 26
            }
            let candidate = clean + separator + suffix
            if !used.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }

    // Recognize Cardify/Obsidian timestamp-prefixed filenames, even without frontmatter.
    static func filenameID(for file: URL) -> String? {
        guard file.pathExtension.lowercased() == "md" else { return nil }
        let name = file.deletingPathExtension().lastPathComponent
        let pattern = try! NSRegularExpression(pattern: #"^([0-9]{12}(?:-[0-9]{2,})?(?:[A-Za-z]+[0-9]*)*)(?=$|[ _-])"#)
        guard let match = pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)), let range = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[range])
    }

    // Bare sequential/branch identifiers in imported filenames, used for collision checks.
    static func luhmannFilenameID(for file: URL) -> String? {
        guard file.pathExtension.lowercased() == "md" else { return nil }
        let name = file.deletingPathExtension().lastPathComponent
        let pattern = try! NSRegularExpression(pattern: #"^([0-9]+(?:[A-Za-z]+[0-9]*)*)(?=$|[ _-])"#)
        guard let match = pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)), let range = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[range])
    }

    // Debate parent IDs may appear in imported filenames without frontmatter.
    // Keep checking these even when a file also has a different metadata ID.
    static func debateFilenameID(for file: URL) -> String? {
        guard file.pathExtension.lowercased() == "md" else { return nil }
        let name = file.deletingPathExtension().lastPathComponent
        let pattern = try! NSRegularExpression(pattern: #"^((?:AFF|DEF)-[0-9]+(?:[A-Za-z]+[0-9]*)*(?:-(?:OB|EV|AR|RE|NT)-[0-9]+(?:[A-Za-z]+[0-9]*)*)*)(?=$|[ _-])"#, options: [.caseInsensitive])
        guard let match = pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)), let range = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[range])
    }

    static func existing(in roots: [URL], excluding target: URL? = nil) throws -> Set<String> {
        var result: Set<String> = []
        for root in roots {
            for (id, _) in try CardIDIndex.ids(in: root, excluding: target) { result.insert(id) }
        }
        return result
    }
}
