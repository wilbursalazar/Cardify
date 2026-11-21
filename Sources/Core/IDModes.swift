import Foundation

// Identity policy proposes an ID for the current card; changing an existing
// ID requires confirmation and does not rename its saved file.
enum IDMode: String, CaseIterable, Identifiable {
    case timestamp = "Timestamp"
    case luhmann = "Luhmann"
    case titleOnly = "Title only"
    var id: String { rawValue }
}

enum CardIDs {
    enum IDError: LocalizedError {
        case missingParent
        case unsupportedContinuation
        var errorDescription: String? {
            switch self {
            case .missingParent: return "The current card needs an ID."
            case .unsupportedContinuation: return "This card ID cannot be continued automatically; enter a continuation ID manually."
            }
        }
    }

    static func newID(mode: IDMode, existing: Set<String>, at date: Date = Date(), timeZone: TimeZone = .current, timestampStyle: TimestampDateStyle = .sortable, timestampIncludeTime: Bool = true) -> String? {
        switch mode {
        case .timestamp: return BranchIDs.timestamp(at: date, timeZone: timeZone, existing: existing, style: timestampStyle, includeTime: timestampIncludeTime)
        case .titleOnly: return nil
        case .luhmann:
            // Avoid assigning a missing root when a descendant, e.g. 1a or 1/2, already exists.
            // Looking for the first available root also keeps timestamp-based IDs from
            // forcing the next Luhmann number into an unrelated, enormous range.
            let used = existing.map { $0.lowercased() }
            var root = 1
            while true {
                let candidate = String(root)
                let reserved = used.contains { value in
                    guard value.hasPrefix(candidate) else { return false }
                    let remainder = value.dropFirst(candidate.count)
                    guard let first = remainder.first else { return true }
                    return first == "/" || first.isASCII && first.isLetter
                }
                if !reserved { return candidate }
                root += 1
            }
        }
    }

    static func branch(from parent: String, existing: Set<String>) throws -> String {
        try BranchIDs.branch(from: parent, existing: existing)
    }

    // Continue the final component without changing existing addresses:
    // 1a -> 1b, 1/1 -> 1/2, and 1a1 -> 1a2.
    static func continuation(from parent: String, existing: Set<String>) throws -> String {
        let clean = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw IDError.missingParent }
        let chars = Array(clean)
        guard let final = chars.last, final.isASCII, final.isLetter || final.isNumber else { throw IDError.unsupportedContinuation }
        let numeric = final.isNumber
        var index = chars.count - 1
        while index > 0 {
            let before = chars[index - 1]
            guard before.isASCII, numeric ? before.isNumber : before.isLetter else { break }
            index -= 1
        }
        let prefix = String(chars[..<index])
        var suffix = String(chars[index...])
        let used = Set(existing.map { $0.lowercased() })
        while true {
            suffix = numeric ? nextNumber(suffix) : nextLetters(suffix)
            let candidate = prefix + suffix
            if !used.contains(candidate.lowercased()) { return candidate }
        }
    }

    private static func nextNumber(_ value: String) -> String {
        var digits = Array(value.utf8)
        var i = digits.count
        while i > 0 {
            i -= 1
            if digits[i] < 57 { digits[i] += 1; return String(decoding: digits, as: UTF8.self) }
            digits[i] = 48
        }
        return "1" + String(decoding: digits, as: UTF8.self)
    }

    private static func nextLetters(_ value: String) -> String {
        let upper = value == value.uppercased()
        var letters = Array(value.lowercased().utf8)
        var i = letters.count
        while i > 0 {
            i -= 1
            if letters[i] < 122 {
                letters[i] += 1
                let result = String(decoding: letters, as: UTF8.self)
                return upper ? result.uppercased() : result
            }
            letters[i] = 97
        }
        let result = "a" + String(decoding: letters, as: UTF8.self)
        return upper ? result.uppercased() : result
    }
}
