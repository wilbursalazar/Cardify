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
precondition(register.printPages(index: index()).count == 1 && register.printPages(index: index())[0].contains("**Church history**"))

// Printed addresses: a Zettel card prints its Luhmann ID (findable in the box), others a short title.
let printed = register.printPages(index: index())[0]
precondition(printed.contains("**Authority** — 21") && printed.contains("**Church history** — Church history"), printed)
precondition(KeywordRegister.address(of: nil, link: "Gone/A very long card title that goes on and on|Alias") == "Alias")
precondition(KeywordRegister.address(of: nil, link: "A very long card title that goes on and on forever") == "A very long card title that go…")

// Broken entries: a missing card and an ambiguous name are flagged; Choose Card fixes the link.
try! manager.createDirectory(at: root.appendingPathComponent("Quick"), withIntermediateDirectories: true)
try! Data("# Twin\n".utf8).write(to: root.appendingPathComponent("Zettel/Twin.md"))
try! Data("# Twin\n".utf8).write(to: root.appendingPathComponent("Quick/Twin.md"))
_ = register.update(openWithUnsavedEdits: false) { KeywordRegister.adding("Gone card", to: "Lost", in: KeywordRegister.adding("Twin", to: "Double", in: $0)) }
precondition(RegisterService.state(of: "Gone card", index: index()) == .missing)
guard case .ambiguous(let twins) = RegisterService.state(of: "Twin", index: index()), twins.count == 2 else { preconditionFailure("ambiguous") }
if case .card = RegisterService.state(of: "21-Apostolic succession", index: index()) {} else { preconditionFailure("resolves") }
precondition(Set(register.brokenEntries(index: index()).map(\.keyword)) == ["Double", "Lost"])
let quickTwin = index().cards.first { $0.path == "Quick/Twin" }!
precondition(register.choose(quickTwin, for: "Twin", in: "Double", index: index(), openWithUnsavedEdits: false) == .written)
precondition(register.entries().first { $0.keyword == "Double" }?.links == ["Quick/Twin"], "\(register.entries())")
precondition(register.choose(card, for: "Gone card", in: "Lost", index: index(), openWithUnsavedEdits: false) == .written)
precondition(register.brokenEntries(index: index()).isEmpty && register.entries().first { $0.keyword == "Lost" }?.links == ["21-Apostolic succession"])
precondition(KeywordRegister.replacing("A", with: "B", in: "K", text: "- K: [[A]], [[B]]") == "- K: [[B]]", "Choosing a card already listed doesn't duplicate it")

// Index cards know which keywords reach them.
let history = index().cards.first { $0.title == "Church history" }!
precondition(register.keywords(pointingTo: history, index: index()) == ["Church history"])
precondition(register.keywords(pointingTo: card, index: index()).sorted() == ["Authority", "Lost"])
print("Register service: creation, unsaved-edit guard, entry cards, index-card import, printed IDs, broken entries and Choose Card passed")
