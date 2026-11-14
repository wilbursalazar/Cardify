import Foundation

// Operations on sidebar rows always recheck the selected root, path and bytes.
// A snapshot can safely be held while a confirmation dialog is open.
enum SidebarFileActions {
    enum ActionError: LocalizedError {
        case unavailable, changed, open, invalidName, filenameID, invalidMarkdown, idComment, existingDestination, invalidFolder
        var errorDescription: String? {
            switch self {
            case .unavailable: return "This note is no longer available in the selected notes folder. Refresh and try again."
            case .changed: return "The note changed while the action was open. Refresh and try again."
            case .open: return "This note is open in Cardify. Open a different note before changing its file."
            case .invalidName: return "Choose a valid Markdown filename without slashes or control characters."
            case .filenameID: return "Keep the existing filename card ID unchanged. A filename without an ID cannot gain one through Rename."
            case .invalidMarkdown: return "This note's metadata or UTF-8 encoding cannot be safely duplicated."
            case .idComment: return "The card ID has an inline comment. Move the comment to its own line before duplicating, so it is preserved."
            case .existingDestination: return "A file with that name already exists. Choose a different name."
            case .invalidFolder: return "Choose a folder inside the selected notes folder."
            }
        }
    }

    struct Snapshot {
        let url: URL
        let root: URL
        let bytes: Data
        let cardID: String?
    }

    static func capture(_ url: URL, root: URL) throws -> Snapshot {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let url = url.standardizedFileURL
        guard CardGraph.canOpen(url, in: root) else { throw ActionError.unavailable }
        let bytes = try Data(contentsOf: url)
        let text = String(decoding: bytes, as: UTF8.self)
        let id = Data(text.utf8) == bytes ? CardMetadata.parse(text).id : nil
        return Snapshot(url: url, root: root, bytes: bytes, cardID: id)
    }

    static func validate(_ snapshot: Snapshot, openURLs: [URL], allowOpen: Bool = false) throws {
        guard CardGraph.canOpen(snapshot.url, in: snapshot.root) else { throw ActionError.unavailable }
        if !allowOpen && openURLs.contains(where: { sameFile($0, snapshot.url) }) {
            throw ActionError.open
        }
        guard try Data(contentsOf: snapshot.url) == snapshot.bytes else { throw ActionError.changed }
    }

    // The active note may be changed only after its pending edits have been
    // saved and the exact disk baseline still matches this captured row.
    // A separate hardlink is not the active pathname and remains protected.
    static func validateActive(_ snapshot: Snapshot, activeURL: URL?, activeDiskSnapshot: Data?, otherOpenURLs: [URL]) throws {
        guard let activeURL,
              activeURL.resolvingSymlinksInPath().standardizedFileURL == snapshot.url else { throw ActionError.open }
        guard let activeDiskSnapshot, activeDiskSnapshot == snapshot.bytes else { throw ActionError.changed }
        try validate(snapshot, openURLs: otherOpenURLs)
    }

    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        if a.resolvingSymlinksInPath().standardizedFileURL == b.resolvingSymlinksInPath().standardizedFileURL { return true }
        let manager = FileManager.default
        guard let left = try? manager.attributesOfItem(atPath: a.path),
              let right = try? manager.attributesOfItem(atPath: b.path),
              let leftDevice = left[.systemNumber] as? NSNumber, let rightDevice = right[.systemNumber] as? NSNumber,
              let leftFile = left[.systemFileNumber] as? NSNumber, let rightFile = right[.systemFileNumber] as? NSNumber else { return false }
        return leftDevice == rightDevice && leftFile == rightFile
    }

    static func rename(_ snapshot: Snapshot, filename: String, openURLs: [URL]) throws -> URL {
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let prohibited = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        guard !name.isEmpty, !name.hasPrefix("."), name != ".", name != "..",
              name.rangeOfCharacter(from: prohibited) == nil,
              URL(fileURLWithPath: name).pathExtension.lowercased() == "md" else { throw ActionError.invalidName }
        try validate(snapshot, openURLs: openURLs)
        let destination = snapshot.url.deletingLastPathComponent().appendingPathComponent(name)
        func filenameIDs(_ url: URL) -> Set<String> {
            Set([BranchIDs.filenameID(for: url), BranchIDs.luhmannFilenameID(for: url), BranchIDs.debateFilenameID(for: url)]
                .compactMap { $0?.lowercased() })
        }
        guard filenameIDs(snapshot.url) == filenameIDs(destination) else { throw ActionError.filenameID }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ActionError.existingDestination }
        // moveItem refuses an existing destination even if one appeared after the check.
        try FileManager.default.moveItem(at: snapshot.url, to: destination)
        return destination
    }

    static func move(_ snapshot: Snapshot, to folder: URL, openURLs: [URL]) throws -> URL {
        let folder = folder.standardizedFileURL
        let root = snapshot.root
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard folder == root || folder.path.hasPrefix(prefix) else { throw ActionError.invalidFolder }
        var item = folder
        while item != root {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]),
                  values.isDirectory == true, values.isSymbolicLink != true, values.isHidden != true,
                  item.resolvingSymlinksInPath().standardizedFileURL == item else { throw ActionError.invalidFolder }
            item = item.deletingLastPathComponent()
        }
        guard folder == root || (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { throw ActionError.invalidFolder }
        try validate(snapshot, openURLs: openURLs)
        let destination = folder.appendingPathComponent(snapshot.url.lastPathComponent)
        guard destination != snapshot.url else { return destination }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ActionError.existingDestination }
        try FileManager.default.moveItem(at: snapshot.url, to: destination)
        return destination
    }

    static func duplicate(_ snapshot: Snapshot, openURLs: [URL], allowOpen: Bool = false) throws -> URL {
        try validate(snapshot, openURLs: openURLs, allowOpen: allowOpen)
        let text = String(decoding: snapshot.bytes, as: UTF8.self)
        if hasCardIDComment(text) { throw ActionError.idComment }
        guard Data(text.utf8) == snapshot.bytes,
              CardMetadata.parse(text).id != nil || !CardMetadata.hasNonemptyID(text),
              let copy = NoteEditing.setID("", in: text), CardMetadata.parse(copy).id == nil,
              !CardMetadata.hasNonemptyID(copy) else { throw ActionError.invalidMarkdown }
        let folder = snapshot.url.deletingLastPathComponent()
        let stem = "Copy of " + snapshot.url.deletingPathExtension().lastPathComponent
        let temporary = folder.appendingPathComponent(".cardify-copy-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data(copy.utf8).write(to: temporary, options: .withoutOverwriting)
        try validate(snapshot, openURLs: openURLs, allowOpen: allowOpen)
        var suffix = 1
        while true {
            let name = stem + (suffix == 1 ? "" : " \(suffix)") + ".md"
            let target = folder.appendingPathComponent(name)
            do {
                try FileManager.default.linkItem(at: temporary, to: target)
                return target
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                suffix += 1
            }
        }
    }

    // Removing card_id removes its whole line; refuse rather than silently
    // drop a user's inline YAML comment. Quoted '#' characters are values.
    private static func hasCardIDComment(_ text: String) -> Bool {
        let lines = MarkdownSource.lines(in: text)
        guard let end = lines.frontmatterEnd else { return false }
        for line in lines.values[1..<end] {
            let value = lines.source.substring(with: line.content)
            guard value.hasPrefix("card_id:") else { continue }
            var quote: Character?
            var escaped = false
            let characters = Array(value.dropFirst("card_id:".count))
            var i = 0
            while i < characters.count {
                let ch = characters[i]
                if escaped { escaped = false; i += 1; continue }
                if quote == "\"" && ch == "\\" { escaped = true; i += 1; continue }
                if let active = quote {
                    if ch == active {
                        if active == "'", i + 1 < characters.count, characters[i + 1] == "'" { i += 2; continue }
                        quote = nil
                    }
                } else if ch == "\"" || ch == "'" { quote = ch }
                else if ch == "#" && (i == 0 || characters[i - 1].isWhitespace) { return true }
                i += 1
            }
        }
        return false
    }
}
