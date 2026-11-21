@testable import KasterCore
import Foundation

// Card changes from the sidebar keep open drafts safe: conflicts, cancellation, edits made while a
// dialog is open, rename, move, Trash, hardlinks and duplicate safeguards.
final class FakeCards: OpenCardState {
    var root: URL
    var mode = "markdown"
    var urls: [String: URL] = [:]
    var disks: [String: Data] = [:]
    var text = "", saved: String?
    var saves = 0, pauses = 0
    init(root: URL) { self.root = root }
    var vaultRoot: URL? { root }
    var activeMode: String { mode }
    var openURLs: [String: URL] { urls }
    var activeDiskSnapshot: Data? { disks[mode] }
    var activeDraft: String { text }
    var activeSaved: String? { saved }
    /// Like the editor: saves unsaved edits, refusing if the file changed on disk.
    func saveActiveCard() -> Bool {
        saves += 1
        guard let url = urls[mode], let expected = disks[mode], let current = try? Data(contentsOf: url), current == expected else { return false }
        if Data(text.utf8) != Data((saved ?? "").utf8) {
            do { try Data(text.utf8).write(to: url); disks[mode] = Data(text.utf8); saved = text } catch { return false }
        }
        return true
    }
    func pauseAutosave() { pauses += 1 }
}

final class FakePrompts: CardActionPrompts {
    var answer = true
    var title: String?
    var during: (() -> Void)?
    var asked = 0
    func confirmDuplicateWithoutID() -> Bool { asked += 1; during?(); return answer }
    func newTitle(current: String) -> String? { asked += 1; during?(); return answer ? title : nil }
    func confirmTrash(_ url: URL, closesOpenCard: Bool) -> Bool { asked += 1; during?(); return answer }
}

@main struct Checks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-mutations-" + UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func fixture(_ name: String, disk: String = "# Old\n", draft: String? = nil) throws -> (FakeCards, URL) {
            let file = root.appendingPathComponent(name)
            try Data(disk.utf8).write(to: file)
            let cards = FakeCards(root: root); cards.urls["markdown"] = file; cards.disks["markdown"] = Data(disk.utf8)
            cards.saved = disk; cards.text = draft ?? disk
            return (cards, file)
        }
        func data(_ url: URL) -> Data? { try? Data(contentsOf: url) }
        func service(_ cards: FakeCards, _ prompts: FakePrompts) -> CardMutationService { CardMutationService(cards: cards, prompts: prompts) }
        func failsSafely(_ body: () throws -> Any?) -> Bool { do { _ = try body(); return false } catch { return true } }

        // Rename saves the open draft first, then changes heading and filename together.
        let (renaming, original) = try fixture("original.md", draft: "# Edited\n")
        var prompts = FakePrompts(); prompts.title = "renamed"
        let renamed = try service(renaming, prompts).rename(original)!
        let renamedURL = root.appendingPathComponent("renamed.md")
        precondition(renaming.saves == 1 && renamed.to == renamedURL && renamed.wasActive && renamed.text == "# renamed\n")
        precondition(data(renamedURL) == Data("# renamed\n".utf8) && data(original) == nil && renaming.pauses == 1, "Rename changes the heading with the filename")

        // Move saves first, then moves; a file already there is never replaced.
        let folder = root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let (moving, source) = try fixture("move.md", draft: "# Saved before move\n")
        let moved = try service(moving, FakePrompts()).move(source, to: folder)!
        precondition(moved.to == folder.appendingPathComponent("move.md") && moved.wasActive && moving.saves == 1)
        precondition(data(source) == nil && data(moved.to) == Data("# Saved before move\n".utf8))
        let (occupiedMove, occupiedSource) = try fixture("occupied-move.md")
        let occupiedTarget = folder.appendingPathComponent(occupiedSource.lastPathComponent)
        try Data("another note".utf8).write(to: occupiedTarget)
        precondition(failsSafely { try service(occupiedMove, FakePrompts()).move(occupiedSource, to: folder) })
        precondition(data(occupiedTarget) == Data("another note".utf8) && data(occupiedSource) == Data("# Old\n".utf8))

        // Cancelling a rename changes nothing, though the draft was saved before asking.
        let (cancel, cancelFile) = try fixture("cancel.md", draft: "# Pending\n")
        prompts = FakePrompts(); prompts.answer = false; prompts.title = "unused"
        let cancelled = try service(cancel, prompts).rename(cancelFile)
        precondition(cancelled == nil)
        precondition(data(cancelFile) == Data("# Pending\n".utf8) && data(root.appendingPathComponent("unused.md")) == nil)

        // A file changed outside Kaster is not renamed.
        let (stale, staleFile) = try fixture("stale.md")
        try Data("# External\n".utf8).write(to: staleFile)
        prompts = FakePrompts(); prompts.title = "stale-renamed"
        precondition(failsSafely { try service(stale, prompts).rename(staleFile) } && prompts.asked == 0)
        precondition(data(staleFile) == Data("# External\n".utf8) && data(root.appendingPathComponent("stale-renamed.md")) == nil)

        // Changes during the dialog: the file edited outside, the draft edited, or another card type shown.
        let (race, raceFile) = try fixture("race.md")
        prompts = FakePrompts(); prompts.title = "race-renamed"; prompts.during = { try! Data("# Outside\n".utf8).write(to: raceFile) }
        precondition(failsSafely { try service(race, prompts).rename(raceFile) })
        precondition(data(raceFile) == Data("# Outside\n".utf8) && data(root.appendingPathComponent("race-renamed.md")) == nil)
        let (editedInModal, modalFile) = try fixture("modal.md")
        prompts = FakePrompts(); prompts.title = "modal-renamed"; prompts.during = { editedInModal.text = "# In progress" }
        precondition(failsSafely { try service(editedInModal, prompts).rename(modalFile) })
        precondition(editedInModal.text == "# In progress" && data(root.appendingPathComponent("modal-renamed.md")) == nil)
        let (modeRace, modeFile) = try fixture("mode.md")
        prompts = FakePrompts(); prompts.title = "mode-renamed"; prompts.during = { modeRace.mode = "habits" }
        precondition(failsSafely { try service(modeRace, prompts).rename(modeFile) })
        precondition(data(modeFile) != nil && data(root.appendingPathComponent("mode-renamed.md")) == nil)

        // Trash saves first and reports the closed editor mode; cancel or a failed Trash changes nothing.
        let (trash, trashFile) = try fixture("trash-me.md", draft: "# Saved before trash\n")
        let trashFolder = root.appendingPathComponent("trash", isDirectory: true)
        var trashing = service(trash, FakePrompts())
        trashing.moveToTrash = { url in
            try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trashFolder.appendingPathComponent(url.lastPathComponent))
        }
        let trashed = try trashing.trash(trashFile)
        precondition(trashed == .init(url: trashFile, activeMode: "markdown") && data(trashFile) == nil)
        precondition(data(trashFolder.appendingPathComponent("trash-me.md")) == Data("# Saved before trash\n".utf8))
        let (trashCancel, trashCancelFile) = try fixture("trash-cancel.md")
        prompts = FakePrompts(); prompts.answer = false
        let kept = try service(trashCancel, prompts).trash(trashCancelFile)
        precondition(kept == nil && data(trashCancelFile) != nil)
        let (trashFailure, trashFailureFile) = try fixture("trash-fail.md")
        var failing = service(trashFailure, FakePrompts())
        failing.moveToTrash = { _ in throw NSError(domain: "test", code: 1) }
        precondition(failsSafely { try failing.trash(trashFailureFile) } && data(trashFailureFile) != nil)

        // A card also open through a hardlink in another editor mode is protected.
        let (alias, aliasFile) = try fixture("alias.md")
        let hardlink = root.appendingPathComponent("alias-hardlink.md")
        try FileManager.default.linkItem(at: aliasFile, to: hardlink)
        alias.urls["habits"] = hardlink
        prompts = FakePrompts(); prompts.title = "alias-renamed"
        precondition(failsSafely { try service(alias, prompts).rename(aliasFile) })
        precondition(data(aliasFile) != nil && data(root.appendingPathComponent("alias-renamed.md")) == nil)

        // Duplicate copies the saved draft; a stale file or an edit during the dialog stops it.
        let (duplicate, duplicateFile) = try fixture("duplicate.md", draft: "# Updated duplicate\n")
        let copy = try service(duplicate, FakePrompts()).duplicate(duplicateFile)
        precondition(copy == root.appendingPathComponent("Copy of duplicate.md") && data(copy!) == Data("# Updated duplicate\n".utf8))
        let (duplicateStale, duplicateStaleFile) = try fixture("duplicate-stale.md")
        try Data("# Outside\n".utf8).write(to: duplicateStaleFile)
        precondition(failsSafely { try service(duplicateStale, FakePrompts()).duplicate(duplicateStaleFile) })
        precondition(data(root.appendingPathComponent("Copy of duplicate-stale.md")) == nil)
        let idText = "---\ncard_id: 1a\n---\n# ID\n"
        let (duplicateRace, duplicateRaceFile) = try fixture("1a Duplicate.md", disk: idText)
        prompts = FakePrompts(); prompts.during = { duplicateRace.text = "# Changed during dialog" }
        precondition(failsSafely { try service(duplicateRace, prompts).duplicate(duplicateRaceFile) } && prompts.asked == 1, "Cards with an ID ask first")
        precondition(data(root.appendingPathComponent("Copy of 1a Duplicate.md")) == nil)

        // A card that isn't open is changed without saving anything.
        let other = root.appendingPathComponent("Closed.md")
        try Data("# Closed\n".utf8).write(to: other)
        let (bystander, _) = try fixture("bystander.md")
        prompts = FakePrompts(); prompts.title = "Closed renamed"
        let closed = try service(bystander, prompts).rename(other)!
        precondition(!closed.wasActive && bystander.saves == 0 && bystander.pauses == 0 && data(closed.to) == Data("# Closed renamed\n".utf8))
        print("Card changes: open drafts, conflicts, cancellation, rename, move, Trash, hardlinks and duplicates passed")
    }
}
