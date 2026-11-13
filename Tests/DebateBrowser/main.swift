import Foundation

@main struct Check {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("cardify-debate-safety-" + UUID().uuidString, isDirectory: true)
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: vault, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let parent = vault.appendingPathComponent("Parent.md")
        let external = outside.appendingPathComponent("Outside.md")
        try "# Parent\n".write(to: parent, atomically: true, encoding: .utf8)
        try "# Outside\n".write(to: external, atomically: true, encoding: .utf8)
        precondition(DebateBrowserSafety.canOpen(parent, in: vault), "A regular in-vault note should open")
        let alias = base.appendingPathComponent("Vault Alias", isDirectory: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: vault)
        let scanRoot = alias.resolvingSymlinksInPath().standardizedFileURL
        let snapshot = LibrarySnapshot.load(folder: scanRoot)
        guard let scanned = snapshot?.cards.first(where: { $0.path == "Parent" }) else { fatalError("Could not scan through a symlinked vault root") }
        precondition(DebateBrowserSafety.canOpen(scanned.url, in: alias), "Notes in a symlinked vault root must remain accessible")
        precondition(!DebateBrowserSafety.canOpen(external, in: vault), "Outside notes must not be opened from a stale snapshot")
        try fm.removeItem(at: parent)
        try fm.createSymbolicLink(at: parent, withDestinationURL: external)
        precondition(!DebateBrowserSafety.canOpen(parent, in: vault), "A scanned note replaced by a symlink must be refused")
        let orphan = DebateNotes.parse("# Note\nRelated parent: [[Other]] — context\n")
        precondition(!DebateBrowserSafety.isRelated(orphan, to: "Other"), "A related link without a primary must not appear as a complete connection")
        let related = DebateNotes.parse("# Note\nPrimary parent: [[First]]\nRelated parent: [[Other]] — context\n")
        precondition(DebateBrowserSafety.isRelated(related, to: "other"), "A related parent with a distinct primary should be visible")
        precondition(!DebateBrowserSafety.isRelated(related, to: "First"), "A primary parent must not also appear as related")
        print("Debate browser rejects stale external links and excludes orphan relationships")
    }
}
