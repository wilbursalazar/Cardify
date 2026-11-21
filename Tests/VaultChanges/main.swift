@testable import KasterCore
import Foundation

// The change engine under failure: errors at each kind of step are undone byte-exact, a change
// interrupted by a quit is finished or undone at the next launch, and nothing is ever reported
// as done when it isn't.

/// Real file operations that can be told to fail, mangle a write, or Trash into a test folder.
final class FaultyFiles: VaultFileOperations {
    let real = RealFileOperations()
    let trashFolder: URL
    var failOn: (kind: String, count: Int)?
    var mangleWrites = false
    private var seen: [String: Int] = [:]
    init(trash: URL) { trashFolder = trash }
    private func check(_ kind: String) throws {
        seen[kind, default: 0] += 1
        if let failOn, failOn.kind == kind, seen[kind] == failOn.count { throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "Simulated \(kind) failure"]) }
    }
    func read(_ url: URL) throws -> Data? { try real.read(url) }
    func exists(_ url: URL) -> Bool { real.exists(url) }
    func write(_ data: Data, to url: URL, creating: Bool) throws {
        try check("write")
        try real.write(mangleWrites ? data + Data("!".utf8) : data, to: url, creating: creating)
    }
    func remove(_ url: URL) throws { try check("remove"); try real.remove(url) }
    func move(_ from: URL, to: URL) throws { try check("move"); try real.move(from, to: to) }
    func makeFolder(_ url: URL) throws { try check("folder"); try real.makeFolder(url) }
    func trash(_ url: URL) throws -> URL? {
        try check("trash")
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        let destination = trashFolder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

@main struct Checks {
    static func main() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("kaster-changes-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        defer { try? manager.removeItem(at: base) }
        var round = 0
        // A fresh vault: A.md links B.md; Notes/ holds C.md.
        func vault() throws -> (root: URL, journal: URL, files: FaultyFiles) {
            round += 1
            let root = base.appendingPathComponent("vault\(round)", isDirectory: true)
            try manager.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
            try Data("# A\n\nSee [[B]].\n".utf8).write(to: root.appendingPathComponent("A.md"))
            try Data("# B\n".utf8).write(to: root.appendingPathComponent("B.md"))
            try Data("# C\n".utf8).write(to: root.appendingPathComponent("Notes/C.md"))
            return (root, base.appendingPathComponent("journal\(round)", isDirectory: true), FaultyFiles(trash: base.appendingPathComponent("trash\(round)", isDirectory: true)))
        }
        func journalEmpty(_ journal: URL) -> Bool { ((try? manager.contentsOfDirectory(atPath: journal.path)) ?? []).isEmpty }
        func renameB(_ root: URL) -> VaultChange {
            VaultChange(summary: "Rename “B” to “Bee”", steps: [
                .makeFolder(root.appendingPathComponent("Archive").path),
                .write(root.appendingPathComponent("B.md").path, Data("# Bee\n".utf8)),
                .write(root.appendingPathComponent("A.md").path, Data("# A\n\nSee [[Bee]].\n".utf8)),
                .move(root.appendingPathComponent("B.md").path, root.appendingPathComponent("Archive/Bee.md").path),
            ])
        }
        func untouched(_ root: URL) -> Bool {
            text(root.appendingPathComponent("A.md")) == "# A\n\nSee [[B]].\n" && text(root.appendingPathComponent("B.md")) == "# B\n"
                && !manager.fileExists(atPath: root.appendingPathComponent("Archive").path)
        }

        // 1. A change applies completely and leaves no journal.
        var (root, journal, files) = try vault()
        var engine = VaultChanges(journalFolder: journal, files: files)
        try engine.apply(renameB(root))
        precondition(text(root.appendingPathComponent("Archive/Bee.md")) == "# Bee\n" && text(root.appendingPathComponent("A.md")) == "# A\n\nSee [[Bee]].\n" && !manager.fileExists(atPath: root.appendingPathComponent("B.md").path))
        precondition(journalEmpty(journal))

        // 2. A failure at any step undoes every finished step, byte-exact, and says so.
        for failure in [("write", 1), ("write", 2), ("move", 1), ("folder", 1)] {
            (root, journal, files) = try vault()
            files.failOn = failure
            engine = VaultChanges(journalFolder: journal, files: files)
            do { try engine.apply(renameB(root)); preconditionFailure("\(failure) should fail") }
            catch let error as VaultChanges.Failure {
                precondition(error.undone && error.leftAsIs.isEmpty && error.localizedDescription.contains("Nothing was changed"), "\(failure): \(error)")
            }
            precondition(untouched(root), "\(failure): the vault is exactly as before")
            precondition(journalEmpty(journal))
        }

        // 3. A move onto an existing file fails before touching it, and earlier steps are undone.
        (root, journal, files) = try vault()
        try manager.createDirectory(at: root.appendingPathComponent("Archive"), withIntermediateDirectories: true)
        try Data("someone else's".utf8).write(to: root.appendingPathComponent("Archive/Bee.md"))
        engine = VaultChanges(journalFolder: journal, files: files)
        precondition((try? engine.apply(renameB(root))) == nil)
        precondition(text(root.appendingPathComponent("Archive/Bee.md")) == "someone else's" && text(root.appendingPathComponent("B.md")) == "# B\n" && text(root.appendingPathComponent("A.md")) == "# A\n\nSee [[B]].\n")
        precondition(manager.fileExists(atPath: root.appendingPathComponent("Archive").path), "A folder that already existed is never removed")

        // 4. A write that doesn't read back correctly counts as a failure and is undone.
        (root, journal, files) = try vault()
        files.mangleWrites = true
        engine = VaultChanges(journalFolder: journal, files: files)
        precondition((try? engine.apply(renameB(root))) == nil)
        files.mangleWrites = false
        precondition(text(root.appendingPathComponent("B.md")) == "# B\n" || text(root.appendingPathComponent("B.md")) == "# Bee\n!", "A mangled write is reported, never silently kept as success")

        // 5. Quit after two steps: the journal stays; the next launch finishes the change.
        (root, journal, files) = try vault()
        engine = VaultChanges(journalFolder: journal, files: files, stopAfter: 2)
        try engine.apply(renameB(root))
        precondition(!journalEmpty(journal) && text(root.appendingPathComponent("B.md")) == "# Bee\n" && text(root.appendingPathComponent("A.md")) == "# A\n\nSee [[B]].\n", "Half done, as after a crash")
        var reports = VaultChanges(journalFolder: journal, files: files).recoverInterrupted()
        precondition(reports == [.init(summary: "Rename “B” to “Bee”", outcome: .finished)] && reports[0].message.contains("finished"))
        precondition(text(root.appendingPathComponent("Archive/Bee.md")) == "# Bee\n" && text(root.appendingPathComponent("A.md")) == "# A\n\nSee [[Bee]].\n" && journalEmpty(journal))

        // 6. Quit, then someone edits a file the change hadn't reached: the change is undone instead.
        (root, journal, files) = try vault()
        try VaultChanges(journalFolder: journal, files: files, stopAfter: 2).apply(renameB(root))
        try Data("# A edited elsewhere\n".utf8).write(to: root.appendingPathComponent("A.md"))
        reports = VaultChanges(journalFolder: journal, files: files).recoverInterrupted()
        precondition(reports.map(\.outcome) == [.undone], "\(reports)")
        precondition(text(root.appendingPathComponent("B.md")) == "# B\n" && text(root.appendingPathComponent("A.md")) == "# A edited elsewhere\n" && !manager.fileExists(atPath: root.appendingPathComponent("Archive").path))

        // 7. Quit, then someone edits files the change had already written: it can still finish
        //    (the remaining move doesn't overwrite anything), and their edits are kept.
        (root, journal, files) = try vault()
        try VaultChanges(journalFolder: journal, files: files, stopAfter: 3).apply(renameB(root))
        try Data("# Bee, then edited\n".utf8).write(to: root.appendingPathComponent("B.md"))
        reports = VaultChanges(journalFolder: journal, files: files).recoverInterrupted()
        precondition(reports.map(\.outcome) == [.finished] && text(root.appendingPathComponent("Archive/Bee.md")) == "# Bee, then edited\n", "\(reports)")

        // 7b. Quit; then a remaining step is blocked and an already-written file was edited: the
        //     change is undone, except that file, which is left as it is and named in the report.
        (root, journal, files) = try vault()
        try VaultChanges(journalFolder: journal, files: files, stopAfter: 3).apply(renameB(root))
        try Data("# A edited too\n".utf8).write(to: root.appendingPathComponent("A.md"))
        try Data("someone else's".utf8).write(to: root.appendingPathComponent("Archive/Bee.md"))
        reports = VaultChanges(journalFolder: journal, files: files).recoverInterrupted()
        guard case .partlyUndone(let left) = reports.first?.outcome else { preconditionFailure("\(reports)") }
        precondition(left.map { ($0 as NSString).lastPathComponent } == ["A.md"] && reports[0].message.contains("left as they are"))
        precondition(text(root.appendingPathComponent("A.md")) == "# A edited too\n" && text(root.appendingPathComponent("B.md")) == "# B\n" && text(root.appendingPathComponent("Archive/Bee.md")) == "someone else's")

        // 8. A step that happened just before the quit, but wasn't recorded, isn't done twice.
        (root, journal, files) = try vault()
        try VaultChanges(journalFolder: journal, files: files, stopAfter: 3).apply(renameB(root))
        // The move happened, then Kaster quit before writing down that it had.
        try manager.moveItem(at: root.appendingPathComponent("B.md"), to: root.appendingPathComponent("Archive/Bee.md"))
        reports = VaultChanges(journalFolder: journal, files: files).recoverInterrupted()
        precondition(reports.map(\.outcome) == [.finished] && text(root.appendingPathComponent("Archive/Bee.md")) == "# Bee\n", "\(reports)")

        // 9. A journal whose plan never got written means nothing happened; it's just cleared.
        try manager.createDirectory(at: journal.appendingPathComponent("broken"), withIntermediateDirectories: true)
        precondition(VaultChanges(journalFolder: journal, files: files).recoverInterrupted().isEmpty && journalEmpty(journal))

        // 10. Trash can be undone: a later failure brings the file back.
        (root, journal, files) = try vault()
        files.failOn = ("write", 1)
        engine = VaultChanges(journalFolder: journal, files: files)
        let trashThenWrite = VaultChange(summary: "Trash B", steps: [.trash(root.appendingPathComponent("B.md").path), .write(root.appendingPathComponent("A.md").path, Data("# A\n".utf8))])
        precondition((try? engine.apply(trashThenWrite)) == nil && text(root.appendingPathComponent("B.md")) == "# B\n", "A trashed file comes back when the change fails")

        // 11. Case-only renames work (and undo) on a case-insensitive volume.
        (root, journal, files) = try vault()
        engine = VaultChanges(journalFolder: journal, files: files)
        try engine.apply(VaultChange(summary: "Rename", steps: [.move(root.appendingPathComponent("B.md").path, root.appendingPathComponent("b.md").path)]))
        let renamedNames = try manager.contentsOfDirectory(atPath: root.path)
        precondition(renamedNames.contains("b.md"))
        files.failOn = ("write", 1)
        let caseThenWrite = VaultChange(summary: "Rename", steps: [.move(root.appendingPathComponent("b.md").path, root.appendingPathComponent("B.md").path), .write(root.appendingPathComponent("A.md").path, Data("x".utf8))])
        let failedCase = (try? engine.apply(caseThenWrite)) == nil
        let namesAfter = try manager.contentsOfDirectory(atPath: root.path)
        precondition(failedCase && namesAfter.contains("b.md"))

        // 12. New files: created without overwriting; undone by removing them.
        (root, journal, files) = try vault()
        files.failOn = ("move", 1)
        engine = VaultChanges(journalFolder: journal, files: files)
        let createThenMove = VaultChange(summary: "Duplicate", steps: [.write(root.appendingPathComponent("Copy.md").path, Data("# Copy\n".utf8)), .move(root.appendingPathComponent("B.md").path, root.appendingPathComponent("Notes/B.md").path)])
        precondition((try? engine.apply(createThenMove)) == nil && !manager.fileExists(atPath: root.appendingPathComponent("Copy.md").path))
        print("Vault changes: journaled steps, undo on failure, finish or undo after a quit, Trash and case-only renames passed")
    }
}
