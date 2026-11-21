import Foundation

/// Card IDs for the open card: which folders an ID must be unique in, switching the ID style,
/// and adding an ID to a card that needs one. Never writes files; returns the new text.
struct CardIDService {
    var notesFolder: String
    var saveFolder: String
    var timestampStyle: TimestampDateStyle = .sortable
    var timestampIncludeTime = true
    /// IDs already used under these folders, apart from one file (replaceable in tests).
    var existingIDs: (_ roots: [URL], _ excluding: URL?) throws -> Set<String> = { try BranchIDs.existing(in: $0, excluding: $1) }

    /// The notes folder, plus the card's own folder (or the save folder) when it lies outside it.
    func scanRoots(for file: URL?) -> [URL] {
        var roots: [URL] = []
        if !notesFolder.isEmpty { roots.append(URL(fileURLWithPath: notesFolder, isDirectory: true).standardizedFileURL) }
        let fallback = file?.deletingLastPathComponent() ?? (!saveFolder.isEmpty ? URL(fileURLWithPath: saveFolder, isDirectory: true) : nil)
        if let folder = fallback?.standardizedFileURL,
           !roots.contains(where: { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") }) { roots.append(folder) }
        return roots
    }

    func newID(_ mode: IDMode, existing: Set<String>) -> String? {
        CardIDs.newID(mode: mode, existing: existing, timestampStyle: timestampStyle, timestampIncludeTime: timestampIncludeTime)
    }

    enum StyleChange: Equatable {
        /// Use the new style; the card keeps its text. `status` explains why, when there's a reason.
        case keepText(status: String?)
        /// Keep the old style and the card as it is.
        case refuse(status: String, alert: Bool)
        /// Give the card this ID. With `confirm`, ask first (it replaces an existing ID).
        case replace(text: String, id: String, confirm: Confirmation?)
    }
    struct Confirmation: Equatable {
        let currentID: String
        let proposedID: String
        let savedFile: Bool
        var message: String { "Replace the current card ID?" }
        func details(style: IDMode) -> String {
            "Current ID: \(currentID)\nSuggested \(style.rawValue) ID: \(proposedID)" +
                (savedFile ? "\n\nThe saved file will keep its filename. Links using the old ID may need updating." : "\n\nThis changes the unsaved draft.")
        }
    }

    /// Switching the ID style for a card: what happens to its ID.
    func changeStyle(to mode: IDMode, text: String, fileURL: URL?, isDebateCard: Bool) -> StyleChange {
        let currentID = CardMetadata.parse(text).id
        if mode == .titleOnly { return .keepText(status: nil) }
        if isDebateCard && currentID != nil { return .keepText(status: "Debate cards keep their existing IDs.") }
        guard currentID != nil || !CardMetadata.hasNonemptyID(text) else {
            return .refuse(status: "Fix existing card_id metadata before changing ID style.", alert: false)
        }
        let roots = scanRoots(for: fileURL)
        guard currentID == nil || !roots.isEmpty else {
            return .refuse(status: "Choose a notes or save folder before changing the card ID.", alert: true)
        }
        do {
            let existing = try existingIDs(roots, fileURL)
            guard let proposed = newID(mode, existing: existing),
                  let updated = NoteEditing.setID(proposed, in: text),
                  CardMetadata.parse(updated).id == proposed else {
                return .refuse(status: "Could not prepare a \(mode.rawValue) ID. Check the card metadata.", alert: false)
            }
            let confirm = currentID.flatMap { $0 != proposed ? Confirmation(currentID: $0, proposedID: proposed, savedFile: fileURL != nil) : nil }
            return .replace(text: updated, id: proposed, confirm: confirm)
        } catch {
            return .refuse(status: "Could not check card IDs: \(error.localizedDescription)", alert: true)
        }
    }

    enum Addition: Equatable {
        /// Nothing to add (no ID style, or the card has one).
        case unchanged
        case added(text: String, status: String)
        case failed(status: String)
    }

    /// Adds an ID to a card that needs one: the ID its filename already carries, else a new one.
    func ensureID(text: String, style: IDMode, fileURL: URL?) -> Addition {
        if style == .titleOnly || CardMetadata.parse(text).id != nil { return .unchanged }
        if CardMetadata.hasNonemptyID(text) { return .failed(status: "Fix existing card_id metadata before adding an ID.") }
        if let file = fileURL, let existingID = (BranchIDs.filenameID(for: file) ?? (style == .luhmann ? BranchIDs.luhmannFilenameID(for: file) : nil)) {
            guard let updated = NoteEditing.addID(existingID, to: text) else { return .failed(status: "Could not add ID to the existing metadata.") }
            return .added(text: updated, status: "Kept the existing filename ID: \(existingID).")
        }
        do {
            let existing = try existingIDs(scanRoots(for: fileURL), nil)
            guard let id = newID(style, existing: existing) else { return .unchanged }
            guard let updated = NoteEditing.addID(id, to: text) else { return .failed(status: "Could not add ID to the existing metadata.") }
            return .added(text: updated, status: "Card ID added: \(id).")
        } catch { return .failed(status: "Could not check existing IDs: \(error.localizedDescription)") }
    }
}
