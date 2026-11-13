import Foundation

// Navigation history contains saved cards only. Record opens with visit and
// saves with saveCurrent; commit a history move only after its target opens.
struct CardHistory {
    private var entries: [URL] = []
    private var position: Int?
    private(set) var detached = false

    var current: URL? { position.map { entries[$0] } }
    var backTarget: URL? {
        if detached { return current }
        guard let position, position > 0 else { return nil }
        return entries[position - 1]
    }
    var forwardTarget: URL? {
        if detached { return nil }
        guard let position, position + 1 < entries.count else { return nil }
        return entries[position + 1]
    }

    mutating func visit(_ url: URL) {
        guard url.isFileURL else { return }
        let normalized = url.standardizedFileURL
        if current == normalized { detached = false; return }
        if let position { entries.removeSubrange((position + 1)..<entries.count) }
        entries.append(normalized)
        position = entries.count - 1
        detached = false
    }

    // New, unsaved drafts are not persisted as history entries. Back returns
    // to the most recently visited card rather than skipping over it.
    mutating func detach() { detached = true }

    // Save As changes the identity of the current visit, rather than adding
    // an intermediate step between a pending history destination and the card.
    // A previously unsaved draft instead becomes a new visit.
    mutating func saveCurrent(_ url: URL) {
        guard url.isFileURL else { return }
        guard !detached, let position else { visit(url); return }
        let normalized = url.standardizedFileURL
        guard entries[position] != normalized else { return }
        entries[position] = normalized
        if position > 0 && entries[position - 1] == normalized {
            entries.remove(at: position)
            self.position = position - 1
        }
        if let currentPosition = self.position, currentPosition + 1 < entries.count,
           entries[currentPosition + 1] == normalized {
            entries.remove(at: currentPosition + 1)
        }
    }

    // A matching current entry is a no-op, useful when returning from an
    // unsaved draft. Non-adjacent or stale targets leave history unchanged.
    @discardableResult
    mutating func commitBack(to url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let target = url.standardizedFileURL
        if current == target { detached = false; return true }
        guard backTarget == target, let position else { return false }
        self.position = position - 1
        return true
    }

    @discardableResult
    mutating func commitForward(to url: URL) -> Bool {
        guard url.isFileURL, !detached else { return false }
        let target = url.standardizedFileURL
        if current == target { return true }
        guard forwardTarget == target, let position else { return false }
        self.position = position + 1
        return true
    }
}
