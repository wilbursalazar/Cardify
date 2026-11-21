@testable import KasterCore
import Foundation

// Following links: the folder links resolve in, reading a linked card for a side tab, and the
// Quick card a link to a missing card creates.
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("kaster-navigation-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
try! manager.createDirectory(at: root.appendingPathComponent("Zettel"), withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }

precondition(CardNavigation.linkFolder(notesFolder: "/notes", saveFolder: "/save") == "/notes")
precondition(CardNavigation.linkFolder(notesFolder: "", saveFolder: "/save") == "/save")
precondition(CardNavigation.linkFolder(notesFolder: "", saveFolder: "", debateFile: URL(fileURLWithPath: "/d/AFF.md")) == "/d")
precondition(CardNavigation.linkFolder(notesFolder: "", saveFolder: "") == "")

let card = root.appendingPathComponent("Zettel/Canon.md")
try! Data("# Canon\n\n## Councils\n\nText.\n".utf8).write(to: card)
precondition(try! CardNavigation.readLinked(card, vault: root.path, fragment: "Councils").get().hasPrefix("# Canon"))
precondition(CardNavigation.readLinked(card, vault: root.path, fragment: "Missing") == .failure(.init("The linked heading was not found.")))
precondition(CardNavigation.readLinked(card, vault: "", fragment: nil) == .failure(.init("This linked note is no longer available in the selected notes folder.")))
precondition(CardNavigation.readLinked(URL(fileURLWithPath: "/etc/hosts"), vault: root.path, fragment: nil) == .failure(.init("This linked note is no longer available in the selected notes folder.")), "Only cards inside the vault open")
try! Data([0xff]).write(to: root.appendingPathComponent("Zettel/Bad.md"))
guard case .failure(let bad) = CardNavigation.readLinked(root.appendingPathComponent("Zettel/Bad.md"), vault: root.path, fragment: nil), bad.message.hasPrefix("Could not open linked note") else { preconditionFailure("bad utf-8") }

let missing = CardNavigation.cardForMissingLink("Folder/Apostolic succession#Origins|see this", root: root)!
precondition(missing.title == "Apostolic succession" && missing.url == root.appendingPathComponent("Quick/Apostolic succession.md") && !missing.exists)
try! CardNavigation.createQuickCard(at: missing.url, title: missing.title)
let written = try! String(contentsOf: missing.url, encoding: .utf8)
precondition(written.contains("# Apostolic succession\n") && KasterFrontmatter.value("uid", in: written) != nil)
precondition(CardNavigation.cardForMissingLink("Apostolic succession", root: root)!.exists)
precondition((try? CardNavigation.createQuickCard(at: missing.url, title: "Other")) == nil, "An existing card is never overwritten")
precondition(CardNavigation.cardForMissingLink("  |alias", root: root) == nil)
print("Card navigation: link folders, linked cards, missing-link Quick cards passed")
