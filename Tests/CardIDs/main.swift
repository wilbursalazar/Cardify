@testable import KasterCore
import Foundation

// Card ID style changes and new IDs: confirmation before replacing, collision checks, saved and
// Debate cards, malformed metadata, failed scans, CRLF and the filename's own ID.
@main struct Checks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-ids-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "---\ncard_id: \"1\"\n---\n# First\n".write(to: root.appendingPathComponent("first.md"), atomically: true, encoding: .utf8)
        try "---\ncard_id: \"2a\"\n---\n# Branch\n".write(to: root.appendingPathComponent("branch.md"), atomically: true, encoding: .utf8)
        let original = "---\r\n# Keep this comment\r\ncard_id: \"202611131430\" # Keep this too\r\ntags: [research]\r\n---\r\n# A title\r\n\r\nBody.\r\n"
        let ids = CardIDService(notesFolder: root.path, saveFolder: "")

        // Replacing an existing ID asks first, and keeps the rest of the metadata, the text and CRLF.
        guard case .replace(let replaced, "3", let confirm?) = ids.changeStyle(to: .luhmann, text: original, fileURL: nil, isDebateCard: false) else { preconditionFailure("replace") }
        precondition(CardMetadata.parse(replaced).id == "3")
        precondition(replaced.contains("# Keep this comment\r\n") && replaced.contains("# Keep this too\r\n") && replaced.contains("# A title\r\n\r\nBody.\r\n"), "Replacement must preserve metadata, content, and CRLF")
        precondition(confirm.currentID == "202611131430" && confirm.details(style: .luhmann).contains("202611131430") && confirm.details(style: .luhmann).contains("3"))
        precondition(confirm.details(style: .luhmann).contains("unsaved draft"))

        // A saved card warns that its filename keeps the old ID; the file itself is untouched.
        let savedURL = root.appendingPathComponent("saved.md")
        try original.write(to: savedURL, atomically: true, encoding: .utf8)
        guard case .replace(_, "3", let savedConfirm?) = ids.changeStyle(to: .luhmann, text: original, fileURL: savedURL, isDebateCard: false) else { preconditionFailure("saved") }
        precondition(savedConfirm.details(style: .luhmann).contains("keep its filename"))
        precondition((try? String(contentsOf: savedURL, encoding: .utf8)) == original)

        // Switching from Luhmann proposes a timestamp ID.
        guard case .replace(let stamped, let stamp, _?) = ids.changeStyle(to: .timestamp, text: "---\ncard_id: \"1b\"\n---\n# Idea\n", fileURL: nil, isDebateCard: false) else { preconditionFailure("timestamp") }
        precondition(stamp != "1b" && CardMetadata.parse(stamped).id == stamp)

        // Debate cards keep their IDs; title-only needs nothing.
        precondition(ids.changeStyle(to: .luhmann, text: "---\ncard_id: \"AFF-01\"\n---\n# Point\n", fileURL: nil, isDebateCard: true) == .keepText(status: "Debate cards keep their existing IDs."))
        precondition(ids.changeStyle(to: .titleOnly, text: original, fileURL: nil, isDebateCard: false) == .keepText(status: nil))

        // A card without an ID simply gets one, no question asked.
        guard case .replace(let added, "3", nil) = ids.changeStyle(to: .luhmann, text: "# A title\n\nBody.\n", fileURL: nil, isDebateCard: false) else { preconditionFailure("no id") }
        precondition(CardMetadata.parse(added).id == "3")

        // Malformed metadata is left alone.
        for broken in ["---\ncard_id: \"unterminated\n---\n# Note\n", "---\n# unfinished metadata"] {
            guard case .refuse = ids.changeStyle(to: .luhmann, text: broken, fileURL: nil, isDebateCard: false) else { preconditionFailure(broken) }
            guard case .refuse = ids.changeStyle(to: .luhmann, text: broken, fileURL: savedURL, isDebateCard: false) else { preconditionFailure(broken) }
        }

        // A folder that can't be read, or no folder at all, never changes the ID.
        let missing = CardIDService(notesFolder: root.appendingPathComponent("missing").path, saveFolder: "")
        guard case .refuse(_, true) = missing.changeStyle(to: .luhmann, text: original, fileURL: nil, isDebateCard: false) else { preconditionFailure("missing") }
        guard case .refuse(_, true) = missing.changeStyle(to: .luhmann, text: "# Note\n", fileURL: nil, isDebateCard: true) else { preconditionFailure("missing debate") }
        let none = CardIDService(notesFolder: "", saveFolder: "")
        guard case .refuse(_, true) = none.changeStyle(to: .luhmann, text: original, fileURL: nil, isDebateCard: false) else { preconditionFailure("no folder") }

        // Folders checked: the notes folder, plus the card's folder only when it's outside.
        let inside = root.appendingPathComponent("Zettel/x.md"), outside = URL(fileURLWithPath: "/tmp/elsewhere/x.md")
        precondition(ids.scanRoots(for: inside).map(\.path) == [root.standardizedFileURL.path])
        precondition(ids.scanRoots(for: outside).map(\.path) == [root.standardizedFileURL.path, "/tmp/elsewhere"])
        precondition(CardIDService(notesFolder: "", saveFolder: "/tmp/save").scanRoots(for: nil).map(\.path) == ["/tmp/save"])

        // Adding an ID: the filename's ID first, else a new unique one; never over malformed metadata.
        precondition(ids.ensureID(text: original, style: .luhmann, fileURL: nil) == .unchanged)
        precondition(ids.ensureID(text: "# T\n", style: .titleOnly, fileURL: nil) == .unchanged)
        guard case .added(let kept, let keptStatus) = ids.ensureID(text: "# T\n", style: .luhmann, fileURL: root.appendingPathComponent("21a3 T.md")) else { preconditionFailure("filename id") }
        precondition(CardMetadata.parse(kept).id == "21a3" && keptStatus.contains("filename ID"), "\(kept)")
        guard case .added(let fresh, _) = ids.ensureID(text: "# T\n", style: .luhmann, fileURL: nil) else { preconditionFailure("new id") }
        precondition(CardMetadata.parse(fresh).id == "3")
        guard case .failed = ids.ensureID(text: "---\ncard_id: \"unterminated\n---\n# Note\n", style: .luhmann, fileURL: nil) else { preconditionFailure("malformed") }
        guard case .failed = missing.ensureID(text: "# T\n", style: .luhmann, fileURL: nil) else { preconditionFailure("unreadable folder") }
        print("Card IDs: style confirmation, collisions, saved and Debate cards, malformed metadata, failed scans, CRLF and filename IDs passed")
    }
}
