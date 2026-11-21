import Foundation

/// Reading card files exactly: an unreadable path is an error, never an absent file, and a file
/// symlink is never followed when deciding what may be overwritten.
enum CardFiles {
    /// The file's bytes, or nil when nothing exists at `url`.
    static func diskContents(at url: URL) throws -> Data? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInvalidFileNameError, userInfo: [NSLocalizedDescriptionKey: "The destination is not a regular file."])
        }
        return try Data(contentsOf: url)
    }

    /// UTF-8 text that re-encodes to the same bytes (so saving never silently changes a file).
    static func decodeMarkdown(_ data: Data) throws -> String {
        let decoded = String(decoding: data, as: UTF8.self)
        guard Data(decoded.utf8) == data else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                          userInfo: [NSLocalizedDescriptionKey: "This file is not valid UTF-8 Markdown."])
        }
        return decoded
    }
}

/// What saving needs from the editor window: answers only a person can give.
protocol CardSavePrompts {
    /// The notes folder is missing. Ask for its new location (manual saves only); nil = cancelled.
    func locateNotesFolder(message: String) -> String?
    /// The card's final text, after the editor adds an ID a new card needs; nil stops the save.
    func finalContent() -> String?
    /// Kaster's own place for a new card (its type folder); `prompting` may ask once for a folder.
    func automaticDestination(prompting: Bool) -> URL?
    /// Ask where to save a new card, starting in `folder`; nil = cancelled.
    func chooseDestination(startingIn folder: URL?) -> URL?
    /// Tell the person why a manual save failed.
    func reportFailure(_ message: String)
}

/// The open card, as the editor holds it when saving.
struct CardSaveRequest {
    /// "markdown", "habits", "todos" or "outline".
    var kind: String
    /// The file the editor has open, if the card was saved before.
    var currentURL: URL?
    var saveAs = false
    var automatic = false
    var notesFolder: String
    var saveFolder: String
    /// Card IDs matter for this card (an ID style is on, or it has an ID), so the notes folder
    /// must be reachable to check them.
    var checksIDs: Bool
    /// For a new habit tracker, to-do list or debate: its folder in the vault ("Habit", "To Do", "Debate").
    var typeFolder: String?
    /// For a new branch or idea: the parent card's folder.
    var branchFolder: URL?
    /// The bytes last read from or written to `currentURL`.
    var expectedDisk: Data?
    /// The text as last saved, so an unedited card isn't rewritten.
    var savedContent: String?
}

enum CardSaveOutcome: Equatable {
    /// Written (`created`: the file is new).
    case saved(url: URL, data: Data, content: String, created: Bool)
    /// Nothing changed; the file was left exactly as it was.
    case unchanged(url: URL, data: Data)
    case cancelled
    /// Not saved. The message is ready to show (autosaves say "Autosave paused: …").
    case failed(String)
}

struct CardSaveResult: Equatable {
    var outcome: CardSaveOutcome
    /// The notes folder after the save (changed if the person located a moved folder).
    var notesFolder: String
}

/// Saving cards: choosing the destination, refusing to overwrite a file that changed outside
/// Kaster, keeping card IDs unique, and writing so a new file never replaces an existing one.
struct CardStore {
    /// Card IDs already used under a folder (replaceable in tests).
    var existingIDs: (_ root: URL, _ excluding: URL) throws -> [(String, URL)] = { try CardIDIndex.ids(in: $0, excluding: $1) }

    func save(_ request: CardSaveRequest, prompts: CardSavePrompts) -> CardSaveResult {
        var notesFolder = request.notesFolder
        func done(_ outcome: CardSaveOutcome) -> CardSaveResult { CardSaveResult(outcome: outcome, notesFolder: notesFolder) }
        func fail(_ message: String) -> CardSaveResult {
            if !request.automatic { prompts.reportFailure(message) }
            return done(.failed(request.automatic ? "Autosave paused: " + message : message))
        }

        if !notesFolder.isEmpty && request.checksIDs {
            var isDirectory = ObjCBool(false)
            let available = FileManager.default.fileExists(atPath: notesFolder, isDirectory: &isDirectory) &&
                isDirectory.boolValue && FileManager.default.isReadableFile(atPath: notesFolder)
            if !available {
                let message = "The selected notes folder is unavailable: \(notesFolder). Choose its current location to check card IDs."
                guard !request.automatic else { return done(.failed("Autosave paused: " + message)) }
                guard let located = prompts.locateNotesFolder(message: message) else { return done(.failed(message)) }
                notesFolder = located
                guard !notesFolder.isEmpty, FileManager.default.isReadableFile(atPath: notesFolder) else { return done(.failed(message)) }
            }
        }
        guard let content = prompts.finalContent() else { return done(.cancelled) }

        var target: URL
        if !request.saveAs, let current = request.currentURL {
            target = current
        } else if !request.saveAs, request.currentURL == nil, let automatic = prompts.automaticDestination(prompting: !request.automatic) {
            target = automatic
        } else {
            guard !request.automatic else { return done(.cancelled) }
            var folder: URL?
            if let current = request.currentURL { folder = current.deletingLastPathComponent() }
            else if let typeFolder = request.typeFolder, !(notesFolder.isEmpty && request.saveFolder.isEmpty) {
                do {
                    let root = URL(fileURLWithPath: notesFolder.isEmpty ? request.saveFolder : notesFolder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                    folder = try Self.prepareTypeFolder(typeFolder, in: root)
                } catch {
                    return fail("Could not prepare the \(typeFolder) folder: \(error.localizedDescription)")
                }
            }
            else if let branch = request.branchFolder { folder = branch }
            else if !request.saveFolder.isEmpty { folder = URL(fileURLWithPath: request.saveFolder, isDirectory: true) }
            guard let chosen = prompts.chooseDestination(startingIn: folder) else { return done(.cancelled) }
            target = chosen
        }
        target = target.standardizedFileURL
        let sameFile = request.currentURL.map { $0.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL } ?? false

        do {
            let before = try CardFiles.diskContents(at: target)
            if sameFile {
                guard let expected = request.expectedDisk else { return fail("The saved version could not be verified. Use Save As to preserve this draft.") }
                guard before == expected else { return fail("This file changed or was removed outside Kaster. Your draft is still open. Use Save As to keep a copy; if it has an ID, change the copy's ID to avoid a duplicate.") }
            }
            if CardMetadata.parse(content).id == nil && CardMetadata.hasNonemptyID(content) {
                return fail("Could not read card_id metadata. Check its formatting before saving.")
            }
            if let id = CardMetadata.parse(content).id {
                guard !id.contains(where: { $0.isNewline || ($0.isASCII && $0.isWhitespace && $0 != " ") }) else { return fail("Card IDs must be a single line.") }
                // An ID this same file already had was checked when it was first saved; re-reading the
                // whole vault on every autosave made typing stall in large vaults.
                let previousID = sameFile ? before.flatMap { try? CardFiles.decodeMarkdown($0) }.flatMap { CardMetadata.parse($0).id } : nil
                if previousID?.caseInsensitiveCompare(id) != .orderedSame {
                    for root in Self.idRoots(target: target, notesFolder: notesFolder) {
                        if let duplicate = try existingIDs(root, target.resolvingSymlinksInPath().standardizedFileURL).first(where: { $0.0.caseInsensitiveCompare(id) == .orderedSame }) {
                            return fail("Card ID \(id) is already used by \(duplicate.1.lastPathComponent). Change the ID before saving.")
                        }
                    }
                }
            }
            guard try CardFiles.diskContents(at: target) == before else { return fail("The destination changed while saving. Your draft is still open; try Save As.") }
            var output = content
            if sameFile, let before, request.kind == "habits" || request.kind == "todos" {
                output = Self.matchingNewlines(content, original: try CardFiles.decodeMarkdown(before))
            }
            if sameFile, let saved = request.savedContent, Data(saved.utf8) == Data(content.utf8), let before {
                // No edit: don't normalize an imported file's formatting.
                return done(.unchanged(url: target, data: before))
            }
            let outputData = Data(output.utf8)
            if before == nil {
                // Link a fully written temporary file into place. linkItem refuses an existing
                // destination, including one created after the destination was chosen.
                let temporary = target.deletingLastPathComponent().appendingPathComponent(".cardify-\(UUID().uuidString).tmp")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try outputData.write(to: temporary, options: .withoutOverwriting)
                try FileManager.default.linkItem(at: temporary, to: target)
            } else {
                try outputData.write(to: target, options: .atomic)
            }
            return done(.saved(url: target, data: outputData, content: content, created: before == nil))
        } catch { return fail("Could not verify or write the destination: \(error.localizedDescription)") }
    }

    /// The folders whose IDs a card's ID must not repeat: the notes folder (when the card is
    /// inside it), otherwise the card's own folder as well.
    static func idRoots(target: URL, notesFolder: String) -> [URL] {
        var roots = [target.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL]
        if !notesFolder.isEmpty {
            let folder = URL(fileURLWithPath: notesFolder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
            if roots[0].path == folder.path || roots[0].path.hasPrefix(folder.path + "/") { roots = [folder] }
            else { roots.append(folder) }
        }
        return roots
    }

    /// The habit/to-do editors write LF; an imported file keeps its CRLF or CR line endings.
    static func matchingNewlines(_ content: String, original: String) -> String {
        let withoutCRLF = original.replacingOccurrences(of: "\r\n", with: "")
        if original.contains("\r\n") && !withoutCRLF.contains("\n") && !withoutCRLF.contains("\r") {
            return content.replacingOccurrences(of: "\n", with: "\r\n")
        } else if original.contains("\r") && !original.contains("\n") {
            return content.replacingOccurrences(of: "\n", with: "\r")
        }
        return content
    }

    /// The vault folder for a type of card ("Habit", "To Do", "Debate"), created if missing;
    /// refuses a symlink or a file in its place.
    static func prepareTypeFolder(_ name: String, in root: URL) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
        } else { try manager.createDirectory(at: folder, withIntermediateDirectories: false) }
        return folder
    }
}
