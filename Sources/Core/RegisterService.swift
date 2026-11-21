import Foundation

/// The keyword register (Register.md at the vault root): reading it, updating it safely, adding
/// entry cards and index cards, and its print cards.
struct RegisterService {
    let root: URL
    var url: URL { KeywordRegister.url(in: root) }

    func text() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    func entries() -> [KeywordRegister.Entry] { KeywordRegister.entries(in: text()) }

    /// Creates Register.md from the template if the vault has none.
    func ensureFile() {
        if !FileManager.default.fileExists(atPath: url.path) { try? Data(KeywordRegister.template.utf8).write(to: url, options: .withoutOverwriting) }
    }

    /// Cards marked as index cards that no keyword points to yet.
    func indexCardsNotInRegister(index: LibraryIndex) -> [LibraryCard] {
        let linked = Set(entries().flatMap(\.links).compactMap { index.resolve(link: $0)?.path })
        return index.cards.filter { IndexCardMetadata.isIndex($0.content) && !linked.contains($0.path) }
    }

    enum Update: Equatable {
        case unchanged
        case written
        /// Not changed; the message says why.
        case refused(String)
        case failed(String)
    }

    /// Rewrites Register.md with `change`. Refuses while Register.md is open with unsaved edits.
    func update(openWithUnsavedEdits: Bool, _ change: (String) -> String) -> Update {
        if openWithUnsavedEdits { return .refused("Register.md has unsaved edits; it saves in a moment, then try again.") }
        let before = text()
        let after = change(before)
        guard after != before else { return .unchanged }
        do {
            try Data(after.utf8).write(to: url, options: .atomic)
            return .written
        } catch { return .failed("Could not update the register: \(error.localizedDescription)") }
    }

    /// The keyword offered for a card: its first #tag, else its title.
    static func suggestedKeyword(for card: LibraryCard) -> String { KasterTypesetter.firstTag(in: card.content) ?? card.title }

    /// Adds `card` under `keyword`, linked by its shortest unambiguous name.
    func add(_ card: LibraryCard, keyword: String, index: LibraryIndex, openWithUnsavedEdits: Bool) -> Update {
        let link = CardifyNote.shortestLink(for: card.path, among: index.cards.map(\.path))
        return update(openWithUnsavedEdits: openWithUnsavedEdits) { KeywordRegister.adding(link, to: keyword, in: $0) }
    }

    /// How many entry cards a keyword points to.
    func entryCount(_ keyword: String) -> Int {
        entries().first { $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame }?.links.count ?? 0
    }

    /// Every index card no keyword reaches becomes a keyword (its title) pointing to it.
    func importIndexCards(index: LibraryIndex, openWithUnsavedEdits: Bool) -> (update: Update, count: Int) {
        let cards = indexCardsNotInRegister(index: index)
        let paths = index.cards.map(\.path)
        let result = update(openWithUnsavedEdits: openWithUnsavedEdits) { text in
            cards.reduce(text) { KeywordRegister.adding(CardifyNote.shortestLink(for: $1.path, among: paths), to: $1.title, in: $0) }
        }
        return (result, cards.count)
    }

    /// The register as 3×5 cards for printing.
    func printPages() -> [String] { KeywordRegister.printCards(entries()) }
}
