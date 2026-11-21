import Foundation

/// Keeps permanent uids unique. A card copied outside Kaster (Finder, Obsidian) carries its
/// original's uid, and Kaster would treat the two as one card. The oldest card keeps the uid;
/// every newer copy gets a fresh one.
enum UIDRepair {
    struct Fix: Equatable {
        /// The copy that gets a new uid.
        let url: URL
        let title: String
        let newText: String
        let newUID: String
        /// The copy's text when the fix was planned (the write needs the file to still hold it).
        let original: String
        /// The card that keeps the uid.
        let keeper: String
    }

    /// Fixes for every uid on more than one card. Age is the file's creation date (then its
    /// modification date, then its path), so the original keeps its identity.
    static func fixes(index: LibraryIndex, created: [String: Date], modified: [String: Date]) -> [Fix] {
        guard !index.duplicateUIDs.isEmpty else { return [] }
        var used = Set(index.cards.compactMap { KasterFrontmatter.value("uid", in: $0.content) })
        func older(_ a: LibraryCard, _ b: LibraryCard) -> Bool {
            let ad = created[a.path] ?? modified[a.path] ?? .distantFuture, bd = created[b.path] ?? modified[b.path] ?? .distantFuture
            return ad != bd ? ad < bd : a.path < b.path
        }
        var fixes: [Fix] = []
        for (_, sharing) in index.duplicateUIDs.sorted(by: { $0.key < $1.key }) {
            let ordered = sharing.sorted(by: older)
            for copy in ordered.dropFirst() {
                var uid = KasterFrontmatter.newUID()
                while used.contains(uid) { uid = KasterFrontmatter.newUID() }
                guard let text = KasterFrontmatter.setting("uid", to: uid, in: copy.content) else { continue }
                used.insert(uid)
                fixes.append(Fix(url: copy.url, title: copy.title, newText: text, newUID: uid, original: copy.content, keeper: ordered[0].title))
            }
        }
        return fixes
    }

    /// "“Copy of Canon” had the same permanent ID as “Canon”; it now has its own."
    static func message(_ fixes: [Fix]) -> String {
        guard let first = fixes.first else { return "" }
        if fixes.count == 1 { return "“\(first.title)” had the same permanent ID as “\(first.keeper)”; it now has its own." }
        return "\(fixes.count) copied cards had the same permanent ID as their originals; each now has its own."
    }
}
