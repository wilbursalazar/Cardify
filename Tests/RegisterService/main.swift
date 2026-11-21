@testable import KasterCore
import Foundation

// The register service: creating Register.md, refusing while it has unsaved edits, adding entry
// cards by their shortest name, and turning unreached index cards into keywords.
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("kaster-register-service-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
try! manager.createDirectory(at: root.appendingPathComponent("Zettel"), withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
try! Data("# Apostolic succession\n\n#authority\n".utf8).write(to: root.appendingPathComponent("Zettel/21-Apostolic succession.md"))
try! Data("---\ncardify_index: true\n---\n# Church history\n".utf8).write(to: root.appendingPathComponent("Zettel/Church history.md"))
func index() -> LibraryIndex { LibraryIndex(snapshot: LibrarySnapshot.load(folder: root)!, root: root) }

let register = RegisterService(root: root)
precondition(register.entries().isEmpty && register.text().isEmpty)
register.ensureFile()
precondition(register.text() == KeywordRegister.template)
register.ensureFile()   // never replaces an existing register
precondition(register.text() == KeywordRegister.template)

let card = index().cards.first { $0.title == "Apostolic succession" }!
precondition(RegisterService.suggestedKeyword(for: card) == "authority", "A card's first #tag is the suggested keyword")
precondition(register.add(card, keyword: "Authority", index: index(), openWithUnsavedEdits: true) == .refused("Register.md has unsaved edits; it saves in a moment, then try again."))
precondition(register.entries().isEmpty, "Unsaved edits in Register.md are never overwritten")
precondition(register.add(card, keyword: "Authority", index: index(), openWithUnsavedEdits: false) == .written)
precondition(register.entries().map(\.keyword) == ["Authority"] && register.entries()[0].links == ["21-Apostolic succession"] && register.entryCount("authority") == 1)
precondition(register.add(card, keyword: "Authority", index: index(), openWithUnsavedEdits: false) == .unchanged, "Adding the same card twice changes nothing")

precondition(register.indexCardsNotInRegister(index: index()).map(\.title) == ["Church history"])
let imported = register.importIndexCards(index: index(), openWithUnsavedEdits: false)
precondition(imported.update == .written && imported.count == 1)
precondition(register.entries().map(\.keyword) == ["Authority", "Church history"] && register.indexCardsNotInRegister(index: index()).isEmpty)
precondition(register.printPages().count == 1 && register.printPages()[0].contains("**Church history**"))
print("Register service: creation, unsaved-edit guard, entry cards and index-card import passed")
