import Foundation

// AFF and DEF numbers identify major points across the selected notes folders.
// They are generated for new parents only; existing notes are never rewritten.
enum DebateIDs {
    enum ScanError: LocalizedError {
        case missingFolder
        var errorDescription: String? { "Choose a notes or save folder before creating an AFF or DEF point." }
    }

    static func existing(in roots: [URL], excluding target: URL? = nil) throws -> Set<String> {
        guard !roots.isEmpty else { throw ScanError.missingFolder }
        let resolvedRoots = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        return try BranchIDs.existing(in: resolvedRoots, excluding: target?.resolvingSymlinksInPath().standardizedFileURL)
    }

    // Called on a new draft before replacing the current document. Existing
    // IDs are kept, and non-parent notes never receive an AFF/DEF ID.
    static func prepare(_ draft: String, existing: Set<String>) -> String? {
        let info = DebateNotes.parse(draft)
        guard info.valid else { return nil }
        if CardMetadata.parse(draft).id != nil { return draft }
        guard !CardMetadata.hasNonemptyID(draft) else { return nil }
        guard let role = info.role, role == .aff || role == .def else { return draft }
        guard let id = suggest(role: role, existing: existing),
              let updated = NoteEditing.addID(id, to: draft),
              CardMetadata.parse(updated).id == id else { return nil }
        return updated
    }

    // Keep each series monotonic, including when a root exists only through a
    // branch (AFF-01a) or uses different case/leading zeros (aff-1).
    static func suggest(role: DebateRole, existing: Set<String>) -> String? {
        let prefix: String
        switch role {
        case .aff: prefix = "AFF"
        case .def: prefix = "DEF"
        default: return nil
        }
        let regex = try! NSRegularExpression(pattern: #"^(AFF|DEF)-([0-9]+)(?:[A-Za-z]+[0-9]*|[/.][A-Za-z0-9./-]*)?$"#, options: [.caseInsensitive])
        var largest = 0
        for value in existing {
            guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let type = Range(match.range(at: 1), in: value),
                  String(value[type]).caseInsensitiveCompare(prefix) == .orderedSame,
                  let number = Range(match.range(at: 2), in: value), let serial = Int(value[number]) else { continue }
            largest = max(largest, serial)
        }
        guard largest < Int.max else { return nil }
        let digits = String(largest + 1)
        return prefix + "-" + (digits.count < 2 ? "0" : "") + digits
    }
}
