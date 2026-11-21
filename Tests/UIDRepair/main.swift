@testable import KasterCore
import Foundation

// Permanent uids stay unique: copies made outside Kaster get their own; the original keeps its.
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("kaster-uids-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
try! manager.createDirectory(at: root.appendingPathComponent("Zettel"), withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
func write(_ name: String, _ text: String) { try! Data(text.utf8).write(to: root.appendingPathComponent(name)) }
write("Zettel/Canon.md", "---\nuid: canon234\ncard_id: \"3\"\n---\n# Canon\n")
write("Zettel/Canon copy.md", "---\nuid: canon234\ncard_id: \"3\"\n---\n# Canon copy\n")
write("Zettel/Canon copy 2.md", "---\nuid: canon234\n---\n# Canon copy 2\n")
write("Zettel/Other.md", "---\nuid: other567\n---\n# Other\n")
write("Zettel/No uid.md", "# No uid\n")
let snapshot = LibrarySnapshot.load(folder: root)!
let index = LibraryIndex(snapshot: snapshot, root: root)
precondition(index.duplicateUIDs.keys.sorted() == ["canon234"] && index.duplicateUIDs["canon234"]?.count == 3)
precondition(index.card(uid: "canon234") != nil, "The uid still finds a card while duplicates exist")

// The original keeps the uid: copy-named files lose first, then creation dates decide.
let now = Date()
let created = ["Zettel/Canon copy": now.addingTimeInterval(-300), "Zettel/Canon": now.addingTimeInterval(-100), "Zettel/Canon copy 2": now]
let fixes = UIDRepair.fixes(index: index, created: created, modified: [:])
precondition(fixes.map(\.title) == ["Canon copy", "Canon copy 2"] && fixes.allSatisfy { $0.keeper == "Canon" }, "\(fixes.map(\.title))")
precondition(Set(fixes.map(\.newUID)).count == 2 && !fixes.contains { ["canon234", "other567"].contains($0.newUID) })
for fix in fixes {
    precondition(KasterFrontmatter.value("uid", in: fix.newText) == fix.newUID && fix.newText.contains("# \(fix.title)\n"))
    precondition(fix.original == (try! String(contentsOf: fix.url, encoding: .utf8)))
}
precondition(UIDRepair.message(Array(fixes.prefix(1))) == "“Canon copy” had the same permanent ID as “Canon”; it now has its own.")
precondition(UIDRepair.message(fixes).hasPrefix("2 copied cards"))

// Applied as one guarded change, the vault has no duplicate uids left.
let engine = VaultChanges(journalFolder: root.deletingLastPathComponent().appendingPathComponent("journal-\(UUID().uuidString)"))
try! engine.apply(KasterVault.change("Give copied cards their own permanent ID", writes: fixes.map { CardWrite(url: $0.url, text: $0.newText, original: $0.original) }, moves: []))
let repaired = LibraryIndex(snapshot: LibrarySnapshot.load(folder: root)!, root: root)
precondition(repaired.duplicateUIDs.isEmpty && UIDRepair.fixes(index: repaired, created: [:], modified: [:]).isEmpty)

// A copy edited after the fix was planned is left alone (the guarded write refuses).
write("Zettel/Late.md", "---\nuid: other567\n---\n# Late\n")
let late = UIDRepair.fixes(index: LibraryIndex(snapshot: LibrarySnapshot.load(folder: root)!, root: root), created: ["Zettel/Other": now.addingTimeInterval(-500), "Zettel/Late": now], modified: [:])
write("Zettel/Late.md", "---\nuid: other567\n---\n# Late, edited in Obsidian\n")
precondition((try? engine.apply(KasterVault.change("Fix", writes: late.map { CardWrite(url: $0.url, text: $0.newText, original: $0.original) }, moves: []))) == nil)
precondition((try! String(contentsOf: root.appendingPathComponent("Zettel/Late.md"), encoding: .utf8)).contains("edited in Obsidian"), "An outside edit is never overwritten")
// Copy-like names lose even when the copy keeps the original's dates (Finder can).
precondition(UIDRepair.looksLikeCopy(URL(fileURLWithPath: "/v/Canon copy.md")) && UIDRepair.looksLikeCopy(URL(fileURLWithPath: "/v/Copy of Canon.md"))
             && UIDRepair.looksLikeCopy(URL(fileURLWithPath: "/v/Canon copy 2.md")) && UIDRepair.looksLikeCopy(URL(fileURLWithPath: "/v/Canon 2.md")))
precondition(!UIDRepair.looksLikeCopy(URL(fileURLWithPath: "/v/2-1a-Copying is storage.md")) && !UIDRepair.looksLikeCopy(URL(fileURLWithPath: "/v/21-3a2-Canon.md"))
             && !UIDRepair.looksLikeCopy(URL(fileURLWithPath: "/v/Canon.md")), "Luhmann IDs ending in digits are not copies")
write("Zettel/Twin.md", "---\nuid: twin2345\n---\n# Twin\n")
write("Zettel/Twin copy.md", "---\nuid: twin2345\n---\n# Twin\n")
let sameDate = Date()
let twins = UIDRepair.fixes(index: LibraryIndex(snapshot: LibrarySnapshot.load(folder: root)!, root: root),
                            created: ["Zettel/Twin": sameDate, "Zettel/Twin copy": sameDate.addingTimeInterval(-60)], modified: [:])
precondition(twins.contains { $0.url.lastPathComponent == "Twin copy.md" } && !twins.contains { $0.url.lastPathComponent == "Twin.md" }, "The copy-named file gets the new uid, even though it looks older")
print("Unique uids: duplicates found, the oldest keeps its uid, copies get new ones, outside edits are never overwritten passed")
