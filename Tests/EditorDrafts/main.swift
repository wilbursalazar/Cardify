@testable import KasterCore
import Foundation

// Opening a card while drafts are unsaved: saved cards save quietly, new drafts get one
// Save / Discard / Cancel question, stale sidebar targets keep the draft, and outlines open
// in the outline editor unchanged.
final class FakeDrafts: EditorDraftState {
    var mode = "markdown"
    var texts: [String: String] = [:]
    var savedTexts: [String: String] = [:]
    var urls: [String: URL] = [:]
    var saveTargets: [URL] = []
    var quietSaves: [Bool] = []
    var shown: OpenedCard?
    var activeMode: String { mode }
    func contents(_ mode: String) -> String { texts[mode] ?? initial(mode) }
    func saved(_ mode: String) -> String? { savedTexts[mode] }
    func baseline(_ mode: String) -> Data? { nil }
    func initial(_ mode: String) -> String { mode == "outline" ? OutlineDocument().markdown : mode == "habits" ? HabitTracker().markdown : mode == "todos" ? TodoList().markdown : "" }
    func fileURL(_ mode: String) -> URL? { urls[mode] }
    func save(_ mode: String, quietHistory: Bool) -> Bool {
        quietSaves.append(quietHistory)
        let target: URL
        if let current = urls[mode] { target = current } else { guard !saveTargets.isEmpty else { return false }; target = saveTargets.removeFirst() }
        do { try contents(mode).write(to: target, atomically: true, encoding: .utf8) } catch { return false }
        urls[mode] = target; savedTexts[mode] = contents(mode)
        return true
    }
    func clear(_ mode: String) { texts[mode] = nil; savedTexts[mode] = nil; urls[mode] = nil }
    func show(_ card: OpenedCard) {
        mode = card.mode; texts[card.mode] = card.text; savedTexts[card.mode] = card.text; urls[card.mode] = card.url; shown = card
    }
}

final class Answers: DraftPrompts {
    var replies: [DraftChoice] = []
    var asked: [[String]] = []
    func saveDrafts(_ unsaved: [String], hidden: Bool) -> DraftChoice {
        asked.append(unsaved)
        precondition(!replies.isEmpty, "Unexpected question")
        return replies.removeFirst()
    }
}

@main struct Checks {
    static func main() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-drafts-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let a = temp.appendingPathComponent("a.md"), b = temp.appendingPathComponent("b.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        try "# B".write(to: b, atomically: true, encoding: .utf8)

        // Edits to a saved card are saved without a question when opening another card.
        var state = FakeDrafts(); var answers = Answers()
        state.texts["markdown"] = "# A edited"; state.savedTexts["markdown"] = "# A"; state.urls["markdown"] = a
        precondition(EditorDrafts(state: state, prompts: answers).open(b) == .opened(mode: "markdown"))
        precondition((try? String(contentsOf: a, encoding: .utf8)) == "# A edited" && state.texts["markdown"] == "# B" && answers.asked.isEmpty)

        // Cancel keeps a new draft; Discard opens the card.
        state = FakeDrafts(); answers = Answers(); state.texts["markdown"] = "# Unsaved"
        answers.replies = [.cancel]
        precondition(EditorDrafts(state: state, prompts: answers).open(b) == .cancelled)
        precondition(state.texts["markdown"] == "# Unsaved" && state.urls["markdown"] == nil)
        answers.replies = [.discard]
        precondition(EditorDrafts(state: state, prompts: answers).open(b) == .opened(mode: "markdown"))
        precondition(state.texts["markdown"] == "# B" && state.urls["markdown"] == b)

        // Saving a new draft first keeps what was written.
        let newFile = temp.appendingPathComponent("new.md")
        state = FakeDrafts(); answers = Answers(); state.texts["markdown"] = "# New"; state.saveTargets = [newFile]
        answers.replies = [.save]
        precondition(EditorDrafts(state: state, prompts: answers).open(b) == .opened(mode: "markdown"))
        precondition((try? String(contentsOf: newFile, encoding: .utf8)) == "# New" && state.urls["markdown"] == b)

        // Two unsaved drafts (research and habits) get one combined question.
        state = FakeDrafts(); answers = Answers(); state.mode = "habits"
        state.texts["markdown"] = "# Research draft"; state.texts["habits"] = "| Habit | Mon |\n|---|---|\n| Draft | x |\n"
        answers.replies = [.cancel]
        precondition(EditorDrafts(state: state, prompts: answers).open(b) == .cancelled)
        precondition(answers.asked == [["habits", "markdown"]] && state.mode == "habits" && state.texts["markdown"] == "# Research draft")
        answers.replies = [.discard]
        precondition(EditorDrafts(state: state, prompts: answers).open(b) == .opened(mode: "markdown"))
        precondition(answers.asked.count == 2 && state.mode == "markdown" && state.texts["markdown"] == "# B" && state.texts["habits"] == nil, "Discarded drafts are cleared")

        // A sidebar target invalidated while the question is open keeps the draft.
        state = FakeDrafts(); answers = Answers(); state.texts["markdown"] = "# Keep"
        var checks = 0; answers.replies = [.discard]
        let stale = EditorDrafts(state: state, prompts: answers).open(b, validating: { checks += 1; return checks == 1 })
        guard case .failed(let message) = stale, message.contains("no longer safely available") else { preconditionFailure("\(stale)") }
        precondition(state.texts["markdown"] == "# Keep" && state.urls["markdown"] == nil)

        // An outline file opens in the outline editor, unchanged.
        let outlineFile = temp.appendingPathComponent("outline.md")
        let original = OutlineDocument().markdown
        try original.write(to: outlineFile, atomically: true, encoding: .utf8)
        state = FakeDrafts(); answers = Answers()
        precondition(EditorDrafts(state: state, prompts: answers).open(outlineFile) == .opened(mode: "outline"))
        precondition(state.mode == "outline" && state.shown?.outline?.markdown == original && state.texts["outline"] == original)

        // Unreadable files fail with a message; nothing is replaced.
        state = FakeDrafts(); answers = Answers(); state.texts["markdown"] = "# Mine"
        try Data([0xff, 0xfe]).write(to: temp.appendingPathComponent("bad.md"))
        guard case .failed = EditorDrafts(state: state, prompts: answers).open(temp.appendingPathComponent("bad.md")) else { preconditionFailure("bad utf-8") }
        precondition(state.texts["markdown"] == "# Mine" && answers.asked.isEmpty)

        // Saves for the other editor mode don't record a history visit.
        state = FakeDrafts(); answers = Answers(); state.mode = "habits"
        state.texts["markdown"] = "# A again"; state.savedTexts["markdown"] = "# A"; state.urls["markdown"] = a
        precondition(EditorDrafts(state: state, prompts: answers).confirmReplacing(["habits", "markdown"]) == [])
        precondition(state.quietSaves == [true])
        print("Editor drafts: quiet saves, Save/Discard/Cancel, combined questions, stale targets, outlines and unreadable files passed")
    }
}
