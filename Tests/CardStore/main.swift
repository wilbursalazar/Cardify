@testable import KasterCore
import Foundation

// Saving cards through CardStore: direct saves, conflict guards, BOM, CRLF, missing files,
// card-type folders, unchanged IDs and a moved notes folder.
final class Prompts: CardSavePrompts {
    var content: String?
    var locatedFolder: String?
    var destination: URL?
    var automatic: URL?
    var located = 0, chosen = 0, reported: [String] = []
    var lastFolder: URL?
    init(_ content: String) { self.content = content }
    func locateNotesFolder(message: String) -> String? { located += 1; return locatedFolder }
    func finalContent() -> String? { content }
    func automaticDestination(prompting: Bool) -> URL? { automatic }
    func chooseDestination(startingIn folder: URL?) -> URL? { chosen += 1; lastFolder = folder; return destination }
    func reportFailure(_ message: String) { reported.append(message) }
}

func request(_ kind: String = "markdown", url: URL?, disk: String? = nil, saved: String? = nil, notes: String = "", automatic: Bool = false, checksIDs: Bool = false, typeFolder: String? = nil) -> CardSaveRequest {
    CardSaveRequest(kind: kind, currentURL: url, automatic: automatic, notesFolder: notes, saveFolder: "", checksIDs: checksIDs,
                    typeFolder: typeFolder, branchFolder: nil, expectedDisk: disk.map { Data($0.utf8) }, savedContent: saved)
}
func data(_ url: URL) -> Data? { try? Data(contentsOf: url) }

@main struct Checks {
    static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-store-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = CardStore()

        // An edit to an open card is written in place, with no prompts.
        let existing = temporary.appendingPathComponent("existing.md")
        let old = "# Old\n"; try Data(old.utf8).write(to: existing)
        var prompts = Prompts("# New\n")
        var result = store.save(request(url: existing, disk: old, saved: old), prompts: prompts)
        guard case .saved(existing.standardizedFileURL, Data("# New\n".utf8), "# New\n", false) = result.outcome else { preconditionFailure("\(result)") }
        precondition(prompts.chosen == 0 && prompts.reported.isEmpty && data(existing) == Data("# New\n".utf8))

        // A file changed outside Kaster (even by Unicode normalization alone) is never overwritten;
        // autosave says so without an alert.
        let composed = "# Caf\u{00e9}\n", decomposed = "# Cafe\u{0301}\n"
        precondition(composed == decomposed && Data(composed.utf8) != Data(decomposed.utf8))
        try Data(decomposed.utf8).write(to: existing)
        prompts = Prompts("# My edit\n")
        result = store.save(request(url: existing, disk: composed, saved: composed, automatic: true), prompts: prompts)
        guard case .failed(let conflict) = result.outcome else { preconditionFailure("\(result)") }
        precondition(conflict.hasPrefix("Autosave paused") && prompts.reported.isEmpty && data(existing) == Data(decomposed.utf8))
        result = store.save(request(url: existing, disk: composed, saved: composed), prompts: prompts)
        precondition(prompts.reported.count == 1, "A manual save explains the conflict")

        // Exact decoding: a BOM survives, invalid UTF-8 is refused.
        let bom = Data([0xef, 0xbb, 0xbf, 0x23, 0x20, 0x41, 0x0d, 0x0a])
        let decodedBOM = try CardFiles.decodeMarkdown(bom)
        precondition(Data(decodedBOM.utf8) == bom)
        precondition((try? CardFiles.decodeMarkdown(Data([0xff]))) == nil)

        // A deleted file is not silently recreated.
        let missing = temporary.appendingPathComponent("missing.md")
        result = store.save(request(url: missing, disk: old, saved: old, automatic: true), prompts: Prompts("# Edit"))
        guard case .failed = result.outcome else { preconditionFailure("\(result)") }
        precondition(!FileManager.default.fileExists(atPath: missing.path))

        // A new card asks where to go, then is linked into place.
        let created = temporary.appendingPathComponent("created.md")
        prompts = Prompts("# Draft\n"); prompts.destination = created
        result = store.save(request(url: nil), prompts: prompts)
        guard case .saved(_, _, _, true) = result.outcome else { preconditionFailure("\(result)") }
        precondition(prompts.chosen == 1 && data(created) == Data("# Draft\n".utf8))
        // Choosing an existing file in the Save panel (which asks before replacing) replaces it.
        prompts = Prompts("# Second\n"); prompts.destination = created
        result = store.save(request(url: nil), prompts: prompts)
        guard case .saved(_, _, _, false) = result.outcome else { preconditionFailure("\(result)") }
        precondition(data(created) == Data("# Second\n".utf8))
        // Autosave never opens a Save panel.
        prompts = Prompts("# Quiet\n"); prompts.destination = created
        result = store.save(request(url: nil, automatic: true), prompts: prompts)
        precondition(result.outcome == .cancelled && prompts.chosen == 0)
        // Kaster's own destination for a new card needs no panel.
        let automatic = temporary.appendingPathComponent("auto.md")
        prompts = Prompts("# Auto\n"); prompts.automatic = automatic
        result = store.save(request(url: nil, automatic: true), prompts: prompts)
        guard case .saved(_, _, _, true) = result.outcome else { preconditionFailure("\(result)") }
        precondition(prompts.chosen == 0 && data(automatic) == Data("# Auto\n".utf8))

        // The file changing while IDs are checked stops the save.
        let race = temporary.appendingPathComponent("race.md")
        let raceOld = "---\ncard_id: 7\n---\n# Old\n", raceExternal = "# External update\n"
        try Data(raceOld.utf8).write(to: race)
        var racing = CardStore()
        racing.existingIDs = { _, _ in try Data(raceExternal.utf8).write(to: race); return [] }
        result = racing.save(request(url: race, disk: raceOld, saved: raceOld, notes: temporary.path, automatic: true, checksIDs: true), prompts: Prompts("---\ncard_id: 8\n---\n# My edit\n"))
        guard case .failed = result.outcome else { preconditionFailure("\(result)") }
        precondition(data(race) == Data(raceExternal.utf8))

        // A duplicate card ID is refused, naming the other card.
        var duplicates = CardStore()
        duplicates.existingIDs = { root, _ in [("8", root.appendingPathComponent("Other.md"))] }
        try Data(raceOld.utf8).write(to: race)
        result = duplicates.save(request(url: race, disk: raceOld, saved: raceOld, notes: temporary.path, automatic: true, checksIDs: true), prompts: Prompts("---\ncard_id: 8\n---\n# Mine\n"))
        guard case .failed(let duplicate) = result.outcome, duplicate.contains("Other.md") else { preconditionFailure("\(result)") }
        precondition(data(race) == Data(raceOld.utf8))

        // An ID the file already had is not re-checked against the whole vault on every autosave.
        let steady = temporary.appendingPathComponent("steady.md"), steadyOld = "---\ncard_id: 9\n---\n# Old\n"
        try Data(steadyOld.utf8).write(to: steady)
        var scanned = false
        var steadying = CardStore()
        steadying.existingIDs = { _, _ in scanned = true; return [] }
        result = steadying.save(request(url: steady, disk: steadyOld, saved: steadyOld, notes: temporary.path, automatic: true, checksIDs: true), prompts: Prompts("---\ncard_id: 9\n---\n# Edited\n"))
        guard case .saved = result.outcome else { preconditionFailure("\(result)") }
        precondition(!scanned, "Unchanged IDs skip the vault scan")

        // An unedited card isn't rewritten (an imported file keeps its formatting).
        result = store.save(request(url: steady, disk: "---\ncard_id: 9\n---\n# Edited\n", saved: "---\ncard_id: 9\n---\n# Edited\n"), prompts: Prompts("---\ncard_id: 9\n---\n# Edited\n"))
        guard case .unchanged = result.outcome else { preconditionFailure("\(result)") }

        // Habit and to-do files keep their CRLF line endings.
        let habitFile = temporary.appendingPathComponent("habit.md")
        let habitDisk = "# Week\r\n\r\n| Habit | Mon |\r\n", habitOriginal = "# Week\n\n| Habit | Mon |\n", habitEdit = "# Week\n\n| Habit | Tue |\n"
        try Data(habitDisk.utf8).write(to: habitFile)
        result = store.save(request("habits", url: habitFile, disk: habitDisk, saved: habitOriginal, automatic: true), prompts: Prompts(habitEdit))
        guard case .saved = result.outcome else { preconditionFailure("\(result)") }
        precondition(data(habitFile) == Data(habitEdit.replacingOccurrences(of: "\n", with: "\r\n").utf8))
        precondition(CardStore.matchingNewlines("a\nb", original: "x\ry") == "a\rb" && CardStore.matchingNewlines("a\nb", original: "x\ny") == "a\nb")

        // A moved notes folder: autosave waits; a manual save asks for its new place, then saves.
        let missingFolder = temporary.appendingPathComponent("moved-notes", isDirectory: true)
        let unchanged = try Data(contentsOf: existing)
        prompts = Prompts("---\ncard_id: 17\n---\n# Recovered\n")
        result = store.save(request(url: existing, disk: decomposed, saved: decomposed, notes: missingFolder.path, automatic: true, checksIDs: true), prompts: prompts)
        guard case .failed(let paused) = result.outcome, paused.hasPrefix("Autosave paused") else { preconditionFailure("\(result)") }
        precondition(prompts.located == 0 && data(existing) == unchanged)
        result = store.save(request(url: existing, disk: decomposed, saved: decomposed, notes: missingFolder.path, checksIDs: true), prompts: prompts)
        precondition(prompts.located == 1 && result.outcome == .failed("The selected notes folder is unavailable: \(missingFolder.path). Choose its current location to check card IDs."))
        prompts.locatedFolder = temporary.path
        result = store.save(request(url: existing, disk: decomposed, saved: decomposed, notes: missingFolder.path, checksIDs: true), prompts: prompts)
        guard case .saved = result.outcome else { preconditionFailure("\(result)") }
        precondition(result.notesFolder == temporary.path && data(existing) == Data("---\ncard_id: 17\n---\n# Recovered\n".utf8))

        // New habit trackers, to-do lists and debates start in their own vault folders.
        let vault = temporary.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: false)
        for (kind, folderName) in [("habits", "Habit"), ("todos", "To Do"), ("markdown", "Debate")] {
            let expectedFolder = vault.appendingPathComponent(folderName, isDirectory: true)
            prompts = Prompts("# \(folderName)\n"); prompts.destination = expectedFolder.appendingPathComponent("New.md")
            result = store.save(request(kind, url: nil, notes: vault.path, typeFolder: folderName), prompts: prompts)
            guard case .saved = result.outcome else { preconditionFailure("\(kind): \(result)") }
            precondition(prompts.lastFolder?.standardizedFileURL == expectedFolder.resolvingSymlinksInPath().standardizedFileURL, "\(String(describing: prompts.lastFolder))")
        }
        // A habit file opened from elsewhere is saved in place.
        let habitNow = String(decoding: data(habitFile)!, as: UTF8.self)
        prompts = Prompts("# Updated in place\n")
        result = store.save(request("habits", url: habitFile, disk: habitNow, saved: habitEdit, notes: vault.path), prompts: prompts)
        guard case .saved(let url, _, _, false) = result.outcome, url == habitFile.standardizedFileURL else { preconditionFailure("\(result)") }
        precondition(prompts.chosen == 0 && data(habitFile) == Data("# Updated in place\r\n".utf8))
        // A file where a type folder should be is refused, not replaced.
        try Data("not a folder".utf8).write(to: vault.appendingPathComponent("Blocked"))
        prompts = Prompts("# Blocked\n"); prompts.destination = vault.appendingPathComponent("x.md")
        result = store.save(request("habits", url: nil, notes: vault.path, typeFolder: "Blocked"), prompts: prompts)
        guard case .failed = result.outcome else { preconditionFailure("\(result)") }
        precondition(prompts.chosen == 0 && prompts.reported.count == 1)
        print("Card saves: direct saves, conflict guards, BOM, CRLF, missing files, IDs, moved notes folder and type folders passed")
    }
}
