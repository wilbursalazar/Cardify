import Foundation

/// The editor's open cards, as card changes need them. Read again after every prompt: a dialog
/// runs the event loop, so the person may keep typing or switch cards while it is open.
protocol OpenCardState {
    var vaultRoot: URL? { get }
    /// The editor mode showing now ("markdown", "habits", "todos", "outline").
    var activeMode: String { get }
    /// Every editor mode's open file.
    var openURLs: [String: URL] { get }
    /// The bytes last read from or written to the active card's file.
    var activeDiskSnapshot: Data? { get }
    var activeDraft: String { get }
    var activeSaved: String? { get }
    /// Saves the active card's unsaved edits; false if that failed.
    func saveActiveCard() -> Bool
    /// Stops a pending autosave of the active card before its file changes.
    func pauseAutosave()
}

/// The questions card changes ask the person.
protocol CardActionPrompts {
    /// Duplicating a card with an ID: the copy won't keep it. Continue?
    func confirmDuplicateWithoutID() -> Bool
    /// The new title for a card; nil = cancelled.
    func newTitle(current: String) -> String?
    /// Move this card to the Trash?
    func confirmTrash(_ url: URL, closesOpenCard: Bool) -> Bool
}

/// Changing card files from the sidebar: duplicate, rename (title, filename and links), move and
/// Trash. Each change checks the file still matches what was read, that no open editor holds
/// unsaved edits to it, and checks again after any prompt.
struct CardMutationService {
    let cards: OpenCardState
    let prompts: CardActionPrompts
    var moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    struct Renamed: Equatable { let from: URL; let to: URL; let text: String; let title: String; let updatedLinks: [URL]; let wasActive: Bool }
    struct Moved: Equatable { let from: URL; let to: URL; let wasActive: Bool }
    struct Trashed: Equatable { let url: URL; let activeMode: String? }

    /// A change about to happen: the file as captured, and the active editor as it was then.
    struct Prepared {
        let snapshot: SidebarFileActions.Snapshot
        let activeMode: String?
        let activeDraft: Data?
    }

    private var root: URL? { cards.vaultRoot?.resolvingSymlinksInPath().standardizedFileURL }
    private func capture(_ url: URL) throws -> SidebarFileActions.Snapshot {
        guard let root else { throw SidebarFileActions.ActionError.unavailable }
        return try SidebarFileActions.capture(url, root: root)
    }

    /// Captures the card, saving the active editor's edits first if it is the card being changed.
    /// Nil when that save failed (the editor has already said why).
    func prepare(_ url: URL) throws -> Prepared? {
        let mode = cards.activeMode
        let active = cards.openURLs[mode]?.standardizedFileURL == url.standardizedFileURL
        let otherURLs = cards.openURLs.filter { !active || $0.key != mode }.map(\.value)
        let before = try capture(url)
        if active {
            try SidebarFileActions.validateActive(before, activeURL: cards.openURLs[mode], activeDiskSnapshot: cards.activeDiskSnapshot, otherOpenURLs: otherURLs)
            guard cards.saveActiveCard() else { return nil }
        } else {
            try SidebarFileActions.validate(before, openURLs: otherURLs)
        }
        let snapshot = try capture(url)
        if active {
            try SidebarFileActions.validateActive(snapshot, activeURL: cards.openURLs[mode], activeDiskSnapshot: cards.activeDiskSnapshot, otherOpenURLs: otherURLs)
            guard let saved = cards.activeSaved, Data(saved.utf8) == Data(cards.activeDraft.utf8) else { throw SidebarFileActions.ActionError.changed }
        } else {
            try SidebarFileActions.validate(snapshot, openURLs: otherURLs)
        }
        return Prepared(snapshot: snapshot, activeMode: active ? mode : nil, activeDraft: active ? Data(cards.activeDraft.utf8) : nil)
    }

    /// Checks again after a prompt; returns the other open files the change must not touch.
    func validate(_ prepared: Prepared) throws -> [URL] {
        let snapshot = prepared.snapshot
        guard root == snapshot.root else { throw SidebarFileActions.ActionError.unavailable }
        if let mode = prepared.activeMode {
            guard cards.activeMode == mode, cards.openURLs[mode]?.standardizedFileURL == snapshot.url,
                  Data(cards.activeDraft.utf8) == prepared.activeDraft,
                  let saved = cards.activeSaved, Data(saved.utf8) == prepared.activeDraft else {
                throw SidebarFileActions.ActionError.changed
            }
            let otherURLs = cards.openURLs.filter { $0.key != mode }.map(\.value)
            try SidebarFileActions.validateActive(snapshot, activeURL: cards.openURLs[mode], activeDiskSnapshot: cards.activeDiskSnapshot, otherOpenURLs: otherURLs)
            return otherURLs
        }
        let openURLs = Array(cards.openURLs.values)
        try SidebarFileActions.validate(snapshot, openURLs: openURLs)
        return openURLs
    }

    /// A copy beside the card ("Copy of …") without its card ID. Nil = cancelled.
    func duplicate(_ url: URL) throws -> URL? {
        guard let prepared = try prepare(url) else { return nil }
        let snapshot = prepared.snapshot
        if snapshot.cardID != nil || BranchIDs.filenameID(for: url) != nil || BranchIDs.luhmannFilenameID(for: url) != nil || BranchIDs.debateFilenameID(for: url) != nil {
            guard prompts.confirmDuplicateWithoutID() else { return nil }
        }
        let others = try validate(prepared)
        return try SidebarFileActions.duplicate(snapshot, openURLs: others)
    }

    /// New title: the heading and filename change together, and links to the card follow.
    /// Nil = cancelled.
    func rename(_ url: URL) throws -> Renamed? {
        guard let prepared = try prepare(url) else { return nil }
        let original = String(decoding: prepared.snapshot.bytes, as: UTF8.self)
        guard Data(original.utf8) == prepared.snapshot.bytes else { throw SidebarFileActions.ActionError.invalidMarkdown }
        guard let entered = prompts.newTitle(current: KasterVault.displayTitle(for: url, text: original)) else { return nil }
        let title = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = prepared.snapshot.root
        guard let filename = KasterVault.retitledFilename(for: url, root: root, text: original, title: title) else {
            throw SidebarFileActions.ActionError.invalidName
        }
        let newText = NoteEditing.setTitle(title, in: original)
        let others = try validate(prepared)
        if prepared.activeMode != nil { cards.pauseAutosave() }
        let target = KasterVault.uniqueURL(in: url.deletingLastPathComponent(), filename: filename, excluding: url)
        let renamed = try SidebarFileActions.retitle(prepared.snapshot, newText: newText, filename: target.lastPathComponent, openURLs: others)
        let updated = (try? KasterVault.updateLinks(root: root, oldURL: url, newURL: renamed, skip: [renamed.resolvingSymlinksInPath().standardizedFileURL.path])) ?? []
        return Renamed(from: url, to: renamed, text: newText, title: title, updatedLinks: updated, wasActive: prepared.activeMode != nil)
    }

    /// Into another folder of the vault. Nil when saving the open card first failed.
    func move(_ url: URL, to folder: URL) throws -> Moved? {
        guard let prepared = try prepare(url) else { return nil }
        let others = try validate(prepared)
        if prepared.activeMode != nil { cards.pauseAutosave() }
        let moved = try SidebarFileActions.move(prepared.snapshot, to: folder, openURLs: others)
        return Moved(from: url, to: moved, wasActive: prepared.activeMode != nil)
    }

    /// To the macOS Trash. Nil = cancelled.
    func trash(_ url: URL) throws -> Trashed? {
        guard let prepared = try prepare(url) else { return nil }
        guard prompts.confirmTrash(url, closesOpenCard: prepared.activeMode != nil) else { return nil }
        _ = try validate(prepared)
        if prepared.activeMode != nil { cards.pauseAutosave() }
        try moveToTrash(prepared.snapshot.url)
        return Trashed(url: url, activeMode: prepared.activeMode)
    }
}
