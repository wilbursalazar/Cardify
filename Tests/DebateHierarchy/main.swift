import Foundation

// Minimal fixture types matching the production snapshot; the model and parser
// themselves are compiled from their real source files.
struct LibraryCard {
    let url: URL
    let path: String
    let title: String
    let cardID: String?
    let content: String
}
struct LibrarySnapshot { let cards: [LibraryCard]; let unreadable: Int }
func card(_ path: String, _ text: String) -> LibraryCard {
    LibraryCard(url: URL(fileURLWithPath: "/test/\(path).md"), path: path, title: (path as NSString).lastPathComponent, cardID: nil, content: text)
}
func check(_ result: @autoclosure () -> Bool, _ message: String) {
    if !result() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let nameURL = URL(fileURLWithPath: "/test/note.md")
func named(_ title: String, _ id: String?) -> LibraryCard {
    LibraryCard(url: nameURL, path: "note", title: title, cardID: id, content: "")
}
check(DebateHierarchy.displayName(named("A readable point", "AFF-01")) == "AFF-01 · A readable point", "IDs accompany readable titles")
check(DebateHierarchy.displayName(named("AFF-01 A readable point", "AFF-01")) == "AFF-01 A readable point", "filename titles do not repeat their IDs")
check(DebateHierarchy.displayName(named("aff-01", "AFF-01")) == "AFF-01", "ID-only filenames are not doubled")
check(DebateHierarchy.displayName(named("Readable without ID", nil)) == "Readable without ID", "titles without IDs remain readable")
check(DebateHierarchy.displayName(named("", "DEF-01")) == "DEF-01", "untitled cards retain their ID")

let project1 = card("Debates/Resolution", "# Resolution\n<!-- cardify:debate=project -->\n")
let project2 = card("Debates/Other", "# Other\n<!-- cardify:debate=project -->\n")
let aff = card("Points/AFF", "# Affirmative\n<!-- cardify:debate=aff -->\nDebate project: [[Debates/Resolution]]\nDebate project: [[Debates/Other]]\n")
let def = card("Points/DEF", "# Defensive\n<!-- cardify:debate=def -->\nDebate project: [[Debates/Resolution]]\n")
let unused = card("Points/Unassigned", "# Independent\n<!-- cardify:debate=aff -->\n")
let evidence = card("Research/Evidence", "# Evidence\n<!-- cardify:debate=evidence -->\nPrimary parent: [[Points/AFF]] — supports\nRelated parent: [[Points/DEF]] — responds\n")
let argument = card("Research/Argument", "# Argument\nPrimary parent: [[Points/DEF]]\n")
let unrelated = card("Research/Unrelated", "# Another note\n")
let orphan = card("Research/Orphan", "# Orphan\nRelated parent: [[Points/DEF]]\n")
let missing = card("Research/Missing", "# Missing\nPrimary parent: [[Points/No longer here]]\nRelated parent: [[Points/DEF]]\n")
let invalid = card("Research/Invalid", "Primary parent: [[Points/AFF]]\nPrimary parent: [[Points/DEF]]\n")
let snapshot = LibrarySnapshot(cards: [project1, project2, aff, def, unused, evidence, argument, unrelated, orphan, missing, invalid], unreadable: 0)
let projects = DebateHierarchy.projects(in: snapshot)
check(projects.map(\.path) == ["Debates/Other", "Debates/Resolution"], "projects are discoverable and sorted")
let graph = DebateHierarchy.build(snapshot: snapshot, projectPath: project1.path)
check(graph.project?.path == project1.path, "selected project is the root")
check(graph.aff.map(\.parent.path) == [aff.path] && graph.def.map(\.parent.path) == [def.path], "only AFF and DEF belonging to the resolution appear")
check(graph.aff[0].primary.map(\.path) == [evidence.path], "primary card appears under its home")
check(graph.def[0].primary.map(\.path) == [argument.path], "different parents have independent cards")
check(graph.def[0].related.map(\.path) == [evidence.path], "same note is visible as related without duplicating contents")
check(graph.unresolved >= 3, "orphan, missing primary and malformed relationships are flagged")
let other = DebateHierarchy.build(snapshot: snapshot, projectPath: project2.path)
check(other.aff.map(\.parent.path) == [aff.path] && other.def.isEmpty, "a parent can be reused in multiple projects")
let unassigned = DebateHierarchy.build(snapshot: snapshot, projectPath: nil)
check(unassigned.project == nil && unassigned.aff.map(\.parent.path) == [unused.path], "unassigned parent remains available")
let gone = DebateHierarchy.build(snapshot: snapshot, projectPath: "Debates/Gone")
check(gone.project == nil && gone.aff.isEmpty && gone.def.isEmpty && gone.unresolved > 0, "a missing selected resolution cannot show a different project")
let dup = card("Other/AFF", "# Collision\n")
let ambiguous = card("Research/Ambiguous", "# Ambiguous\nPrimary parent: [[AFF]]\n")
let collisions = LibrarySnapshot(cards: [project1, aff, dup, ambiguous], unreadable: 0)
let collisionGraph = DebateHierarchy.build(snapshot: collisions, projectPath: project1.path)
check(collisionGraph.aff.first?.primary.isEmpty == true && collisionGraph.unresolved > 0, "ambiguous bare names never resolve to an arbitrary file")
let incomplete = LibrarySnapshot(cards: [project1, aff, card("Research/Bare", "# Bare\nPrimary parent: [[AFF]]\n")], unreadable: 1)
let incompleteGraph = DebateHierarchy.build(snapshot: incomplete, projectPath: project1.path)
check(incompleteGraph.unreadable == 1 && incompleteGraph.aff.first?.primary.isEmpty == true, "incomplete scans cannot assume bare names are unique")
let brokenAncestry = card("Points/Broken", "# Broken\nPrimary parent: [[No such parent]]\n")
let malformedParent = card("Points/Malformed", "Primary parent: [[Points/AFF]]\nPrimary parent: [[Points/DEF]]\n")
let unsafeSnapshot = LibrarySnapshot(cards: [project1, aff, def, brokenAncestry, malformedParent], unreadable: 0)
check(!DebateHierarchy.canSetPrimary(snapshot: unsafeSnapshot, currentURL: aff.url, proposedParent: brokenAncestry), "missing ancestry cannot be assigned")
check(!DebateHierarchy.canSetPrimary(snapshot: unsafeSnapshot, currentURL: aff.url, proposedParent: malformedParent), "malformed ancestry cannot be assigned")
check(DebateHierarchy.projectsForCard(snapshot: unsafeSnapshot, cardPath: brokenAncestry.path).isEmpty, "missing ancestry has no inferred resolution")
check(!DebateHierarchy.canSetPrimary(snapshot: collisions, currentURL: aff.url, proposedParent: ambiguous), "ambiguous path in ancestry cannot be used")
// A connected card may itself be the parent of an objection, reply, and
// evidence. Related edges do not recurse or duplicate note contents.
let objection = card("Research/Objection", "# Objection\n<!-- cardify:debate=objection -->\nPrimary parent: [[Research/Evidence]]\n")
let reply = card("Research/Reply", "# Reply\n<!-- cardify:debate=reply -->\nPrimary parent: [[Research/Objection]]\nRelated parent: [[Points/DEF]]\n")
let followup = card("Research/Followup", "# Further evidence\n<!-- cardify:debate=evidence -->\nPrimary parent: [[Research/Reply]]\n")
let nestedSnapshot = LibrarySnapshot(cards: snapshot.cards + [objection, reply, followup], unreadable: 0)
let nested = DebateHierarchy.build(snapshot: nestedSnapshot, projectPath: project1.path)
let first = nested.aff[0].primaryBranches.first!
check(first.parent.path == evidence.path, "first child retains the same original card")
let second = first.primaryBranches.first!
let third = second.primaryBranches.first!
let fourth = third.primaryBranches.first!
check(second.parent.path == objection.path && third.parent.path == reply.path && fourth.parent.path == followup.path, "primary branches preserve arbitrary nested relationships")
check(nested.def[0].related.map(\.path).contains(reply.path), "deep cards can have separate related parents")
check(fourth.primaryBranches.isEmpty, "leaf does not invent children")
let visible = nested.visibleCards.map(\.path)
check(visible.contains(followup.path) && visible.filter { $0 == evidence.path }.count == 1, "search includes deep descendants and coalesces related references")
check(DebateHierarchy.projectsForCard(snapshot: nestedSnapshot, cardPath: reply.path) == [project2.path, project1.path], "deep reply resolves all parent projects")
check(DebateHierarchy.projectsForCard(snapshot: nestedSnapshot, cardPath: project1.path) == [project1.path], "resolution resolves itself")
check(DebateHierarchy.projectsForCard(snapshot: nestedSnapshot, cardPath: aff.path) == [project2.path, project1.path], "parent resolves its projects")
check(DebateHierarchy.canSetPrimary(snapshot: nestedSnapshot, currentURL: objection.url, proposedParent: def), "an existing card can move to a safe sibling branch")
check(!DebateHierarchy.canSetPrimary(snapshot: nestedSnapshot, currentURL: objection.url, proposedParent: objection), "self-parenting is refused")
check(!DebateHierarchy.canSetPrimary(snapshot: nestedSnapshot, currentURL: evidence.url, proposedParent: followup), "a descendant cannot become the primary parent of its ancestor")
check(DebateHierarchy.canSetPrimary(snapshot: nestedSnapshot, currentURL: def.url, proposedParent: reply), "related cross-links do not count as ancestry")
check(DebateHierarchy.canSetPrimary(snapshot: nestedSnapshot, currentURL: nil, proposedParent: objection), "a new draft can choose a parent with a valid ancestry")
check(!DebateHierarchy.canSetPrimary(snapshot: nestedSnapshot, currentURL: nil, proposedParent: missing), "missing ancestry is refused even for a new draft")

let cycleA = card("Cycle/A", "# A\n<!-- cardify:debate=aff -->\nDebate project: [[Debates/Resolution]]\nPrimary parent: [[Cycle/B]]\n")
let cycleB = card("Cycle/B", "# B\n<!-- cardify:debate=objection -->\nPrimary parent: [[Cycle/A]]\n")
let selfCycle = card("Cycle/Self", "# Self\nPrimary parent: [[Cycle/Self]]\n")
let cycleGraph = DebateHierarchy.build(snapshot: LibrarySnapshot(cards: [project1, cycleA, cycleB, selfCycle], unreadable: 0), projectPath: project1.path)
check(cycleGraph.aff.count == 1 && cycleGraph.aff[0].primaryBranches.isEmpty, "cyclic edges do not recurse or duplicate cards")
check(cycleGraph.unresolved >= 3, "cycle and self-references are flagged")
let cycleSnapshot = LibrarySnapshot(cards: [project1, cycleA, cycleB, selfCycle], unreadable: 0)
check(!DebateHierarchy.canSetPrimary(snapshot: cycleSnapshot, currentURL: nil, proposedParent: cycleA), "an existing cycle cannot become a parent")
check(!DebateHierarchy.canSetPrimary(snapshot: cycleSnapshot, currentURL: nil, proposedParent: selfCycle), "an existing self-cycle cannot become a parent")
check(DebateHierarchy.projectsForCard(snapshot: cycleSnapshot, cardPath: cycleB.path) == [], "cyclic ancestry cannot select a project")

// A vault selected via a symlink can supply an alias URL for the open card,
// while the browser snapshot contains canonical URLs.
let fm = FileManager.default
let temporary = fm.temporaryDirectory.appendingPathComponent("cardify-debate-alias-" + UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
let realVault = temporary.appendingPathComponent("vault", isDirectory: true)
let aliasVault = temporary.appendingPathComponent("alias", isDirectory: true)
try fm.createDirectory(at: realVault, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: temporary) }
let parentURL = realVault.appendingPathComponent("Parent.md"), childURL = realVault.appendingPathComponent("Child.md")
try "# Parent".write(to: parentURL, atomically: true, encoding: .utf8)
try "# Child".write(to: childURL, atomically: true, encoding: .utf8)
try fm.createSymbolicLink(at: aliasVault, withDestinationURL: realVault)
let parentCard = LibraryCard(url: parentURL, path: "Parent", title: "Parent", cardID: nil, content: "# Parent\n")
let childCard = LibraryCard(url: childURL, path: "Child", title: "Child", cardID: nil, content: "# Child\n")
let aliasSnapshot = LibrarySnapshot(cards: [parentCard, childCard], unreadable: 0)
check(DebateHierarchy.canSetPrimary(snapshot: aliasSnapshot, currentURL: aliasVault.appendingPathComponent("Child.md"), proposedParent: parentCard), "vault aliases resolve to the same current card")
check(!DebateHierarchy.canSetPrimary(snapshot: aliasSnapshot, currentURL: aliasVault.appendingPathComponent("Parent.md"), proposedParent: parentCard), "a vault alias cannot bypass the self-parent check")

let depth = 256
var longCards = [project1, aff]
var previous = aff.path
for index in 0..<depth {
    let path = "Deep/Card\(index)"
    longCards.append(card(path, "# Card \(index)\nPrimary parent: [[\(previous)]]\n"))
    previous = path
}
var deep = DebateHierarchy.build(snapshot: LibrarySnapshot(cards: longCards, unreadable: 0), projectPath: project1.path).aff[0]
for index in 0..<depth {
    check(deep.primaryBranches.count == 1 && deep.primaryBranches[0].parent.path == "Deep/Card\(index)", "long chains remain in order")
    deep = deep.primaryBranches[0]
}
check(deep.primaryBranches.isEmpty, "long chain has a leaf")
print("Debate hierarchy: multiple projects, nested parents, related links, cycles, ambiguity and incomplete scans passed")
