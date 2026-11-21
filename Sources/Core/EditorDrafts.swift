import Foundation

/// A card file read for opening: the exact bytes, and which editor shows it.
struct OpenedCard {
    let url: URL
    let data: Data
    let text: String
    let outline: OutlineDocument?
    let habit: HabitTracker?
    let todo: TodoList?
    /// "outline", "habits", "todos" or "markdown".
    var mode: String { outline != nil ? "outline" : habit != nil ? "habits" : todo != nil ? "todos" : "markdown" }

    static func read(_ url: URL) throws -> OpenedCard {
        let data = try Data(contentsOf: url)
        let text = try CardFiles.decodeMarkdown(data)
        let outline = OutlineDocument.fromMarkdown(text)
        let habit = outline == nil ? HabitTracker.fromMarkdown(text) : nil
        let todo = outline == nil && habit == nil ? TodoList.fromMarkdown(text) : nil
        return OpenedCard(url: url, data: data, text: text, outline: outline, habit: habit, todo: todo)
    }
}

/// The editor's drafts, one per editor mode, as EditorDrafts needs them.
protocol EditorDraftState {
    var activeMode: String { get }
    func contents(_ mode: String) -> String
    func saved(_ mode: String) -> String?
    /// A new card's starting text (unchanged = nothing to save).
    func baseline(_ mode: String) -> Data?
    /// An empty editor's text.
    func initial(_ mode: String) -> String
    func fileURL(_ mode: String) -> URL?
    /// Saves that mode's draft (asking where, for a new card). `quietHistory`: don't record a visit.
    func save(_ mode: String, quietHistory: Bool) -> Bool
    /// Empties that mode's editor (after the person chose Discard).
    func clear(_ mode: String)
    /// Shows a card that was just read.
    func show(_ card: OpenedCard)
}

enum DraftChoice { case save, discard, cancel }

protocol DraftPrompts {
    /// Unsaved new drafts are about to be replaced: save them, discard them, or cancel?
    func saveDrafts(_ unsaved: [String], hidden: Bool) -> DraftChoice
}

/// Replacing drafts safely: edits to saved cards are saved without asking; unsaved new drafts
/// get one Save / Discard / Cancel question, even when two editor modes are involved.
struct EditorDrafts {
    let state: EditorDraftState
    let prompts: DraftPrompts

    /// Before `modes`' drafts are replaced. Nil = cancelled (or a save failed); otherwise the
    /// modes the person chose to discard.
    func confirmReplacing(_ modes: [String], hidden: Bool = false) -> [String]? {
        let original = state.activeMode
        var unique: [String] = []
        for mode in modes where !unique.contains(mode) { unique.append(mode) }
        var unsaved: [String] = []
        for mode in unique {
            let baseline = state.saved(mode).map { Data($0.utf8) } ?? state.baseline(mode) ?? Data(state.initial(mode).utf8)
            guard Data(state.contents(mode).utf8) != baseline else { continue }
            if state.fileURL(mode) != nil {
                guard state.save(mode, quietHistory: mode != original) else { return nil }
            } else { unsaved.append(mode) }
        }
        guard !unsaved.isEmpty else { return [] }
        switch prompts.saveDrafts(unsaved, hidden: hidden) {
        case .save:
            for mode in unsaved { guard state.save(mode, quietHistory: mode != original || hidden) else { return nil } }
            return []
        case .discard: return unsaved
        case .cancel: return nil
        }
    }

    enum Opening: Equatable { case opened(mode: String), cancelled, failed(String) }

    /// Opens a card file in the editor that suits it. `validating` is asked before and after the
    /// draft question, since a sidebar row can go stale while the question is open.
    func open(_ url: URL, validating validate: (() -> Bool)? = nil) -> Opening {
        let unavailable = Opening.failed("This note is no longer safely available. Refresh the sidebar and try again.")
        do {
            guard validate?() ?? true else { return unavailable }
            let target = try OpenedCard.read(url).mode
            let original = state.activeMode
            guard let discarded = confirmReplacing(target == original ? [original] : [original, target]) else { return .cancelled }
            guard validate?() ?? true else { return unavailable }
            let card = try OpenedCard.read(url)
            guard card.mode == target else { return .failed("The card changed while opening. Try again.") }
            for mode in discarded where mode != card.mode { state.clear(mode) }
            state.show(card)
            return .opened(mode: card.mode)
        } catch { return .failed("Could not open file: \(error.localizedDescription)") }
    }
}
