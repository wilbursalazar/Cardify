import Foundation

/// Following links from cards: which folder links resolve in, reading a linked card to open beside
/// the current one, and the Quick card that a link to a missing card creates.
enum CardNavigation {
    /// Links resolve in the notes folder, else the save folder; a Debate card with neither set
    /// uses its own folder. Empty when there's nowhere to look.
    static func linkFolder(notesFolder: String, saveFolder: String, debateFile: URL? = nil) -> String {
        let configured = notesFolder.isEmpty ? saveFolder : notesFolder
        if configured.isEmpty, let debateFile { return debateFile.deletingLastPathComponent().path }
        return configured
    }

    /// A linked card's text for a side tab: it must be inside the vault, decode exactly, and have
    /// the linked heading. Failure carries a message for the person.
    static func readLinked(_ url: URL, vault folder: String, fragment: String?) -> Result<String, Problem> {
        guard !folder.isEmpty, CardGraph.canOpen(url, in: URL(fileURLWithPath: folder, isDirectory: true)) else {
            return .failure(Problem("This linked note is no longer available in the selected notes folder."))
        }
        do {
            let content = try CardFiles.decodeMarkdown(Data(contentsOf: url))
            if let fragment, CardLinkNavigation.headingRange(fragment, in: content) == nil {
                return .failure(Problem("The linked heading was not found."))
            }
            return .success(content)
        } catch { return .failure(Problem("Could not open linked note: \(error.localizedDescription)")) }
    }

    struct Problem: Error, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// The Quick card a `[[link]]` to a missing card becomes: Quick/<Title>.md, titled by the
    /// link's last path part (alias and heading ignored). `exists`: the file is already there.
    static func cardForMissingLink(_ raw: String, root: URL) -> (url: URL, title: String, exists: Bool)? {
        let target = String(raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let withoutFragment = String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let title = (withoutFragment as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let name = KasterVault.filename(mode: .quick, id: nil, title: title) else { return nil }
        let url = root.appendingPathComponent(KasterMode.quick.folder, isDirectory: true).appendingPathComponent(name)
        return (url, title, FileManager.default.fileExists(atPath: url.path))
    }

    /// Writes that Quick card (never over an existing file).
    static func createQuickCard(at url: URL, title: String) throws {
        try KasterVault.ensureFolder(url.deletingLastPathComponent())
        try Data(KasterFrontmatter.ensuringUID(in: "# \(title)\n\n").utf8).write(to: url, options: .withoutOverwriting)
    }
}
