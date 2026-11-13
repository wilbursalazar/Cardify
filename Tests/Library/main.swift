import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("cardify-library-test-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
func write(_ path: String, _ contents: String) throws {
    try contents.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
}
try write("Alpha.md", "---\ncard_id: 1a\n---\n# Alpha heading\nNeedle from source [[sub/Target#heading|alias]] [[Dup]] [[sub/Dup]]")
try write("sub/Target.MD", "---\ncard_id: 1a1\n---\n# Target\nA note")
try write("Dup.md", "# Duplicate at root")
try write("sub/Dup.md", "# Duplicate inside")
try write("Next.md", "---\ncard_id: 1b\n---\n# Next card")
try write("Timestamp.md", "---\ncard_id: 202611122145\n---\n# Time")
let first = LibrarySnapshot.load(folder: root)!
check(first.cards.count == 6, "loads nested and uppercase-extension Markdown")
let alpha = first.cards.first { $0.path == "Alpha" }!
check(LibrarySearch.matches(alpha, query: "needle"), "full-text case insensitive search")
check(LibrarySearch.matches(alpha, query: "ALPHA HEADING"), "heading search")
check(LibrarySearch.matches(alpha, query: "1a"), "ID search")
check(LibrarySearch.matches(alpha, query: "alpha"), "filename search")
check(!LibrarySearch.matches(alpha, query: "not present"), "nonmatch")
check(Set(first.outgoing["Alpha"] ?? []) == Set(["sub/Target", "sub/Dup"]), "alias, heading, explicit path and ambiguous name resolution")
check(first.incoming["sub/Target"] == ["Alpha"], "backlink")
check(first.incoming["Dup"] == nil, "ambiguous name creates no false backlink")
let hints = LibrarySequence.hints(for: alpha, in: first.cards)
check(hints.contains { $0.0 == "Next in sequence" && $0.1.path == "Next" }, "next sequence")
check(hints.contains { $0.0 == "Possible branch" && $0.1.path == "sub/Target" }, "branch hint")
let timestamp = first.cards.first { $0.path == "Timestamp" }!
check(LibrarySequence.hints(for: timestamp, in: first.cards).isEmpty, "timestamps excluded")
try write("Alpha.md", "# Alpha heading\nchanged text")
let second = LibrarySnapshot.load(folder: root)!
check(second.outgoing["Alpha"] == nil && second.incoming["sub/Target"] == nil, "refresh removes stale backlinks")
check(LibrarySearch.matches(second.cards.first { $0.path == "Alpha" }!, query: "changed text"), "refresh sees edited contents")
try write("AFF-07 Imported.md", "# Imported parent")
let imported = LibrarySnapshot.load(folder: root)!.cards.first { $0.path == "AFF-07 Imported" }
check(imported?.cardID == "AFF-07", "filename-only debate ID is visible to navigation")
print("Library search, nested files, unambiguous links/backlinks, sequence hints, timestamps, and refresh passed")
func fixture(_ path: String, _ id: String) -> LibraryCard {
    LibraryCard(url: root.appendingPathComponent(path + ".md"), path: path, title: path, cardID: id, content: "")
}
let roots = [fixture("one", "1"), fixture("two", "2")]
check(LibrarySequence.hints(for: roots[0], in: roots).contains { $0.1.path == "two" }, "numeric root sequence")
let historical = [fixture("first", "1/1"), fixture("next", "1/2"), fixture("branch", "1/1a")]
let historyHints = LibrarySequence.hints(for: historical[0], in: historical)
check(historyHints.contains { $0.1.path == "next" }, "slash-address sequence")
check(historyHints.contains { $0.1.path == "branch" && $0.0 == "Possible branch" }, "slash-address branch")
check(LibrarySequence.components("1,1a") != nil, "comma-address supported")
print("Root and historical address hints passed")
let withMarker = "---\ncardify_index: true\n---\n# Memory\nBody"
check(CardMetadata.parse(withMarker).body == "# Memory\nBody", "index marker omitted from printable text")
let horizontalRules = "---\nSome prose\n---\nMore prose"
check(CardMetadata.parse(horizontalRules).body == horizontalRules, "ordinary Markdown horizontal rules preserved")
check(LibrarySequence.components("1a1a1a1a1a1a1") != nil, "long historical branch addresses supported")
print("Index print metadata and ordinary Markdown preservation passed")
let proseBetweenRules = "---\nThis is ordinary prose\n---\n# A card\n"
check(IndexCardMetadata.marking(proseBetweenRules) == nil, "do not treat prose between rules as metadata")
check(CardMetadata.parse(proseBetweenRules).body == proseBetweenRules, "preserve ordinary prose for printing")
let unsafeMarked = "---\nThis is ordinary prose\ncardify_index: true\n---\n# A card\n"
check(!IndexCardMetadata.isIndex(unsafeMarked), "do not recognize a marker in invalid frontmatter")
check(CardMetadata.parse(unsafeMarked).body == unsafeMarked, "do not hide prose in invalid frontmatter")
let yaml = "---\n# comment\ntags:\n  - study\nsummary: |\n  First line\n  Second line\n---\n# Body\n"
let markedYAML = IndexCardMetadata.marking(yaml)!
check(IndexCardMetadata.isIndex(markedYAML) && CardMetadata.parse(markedYAML).body.contains("# Body"), "preserve valid nested YAML")
check(IndexCardMetadata.marking("---\nsummary: |\n  First line\n  ---\n  Last line\n---\n# Body") == nil, "reject ambiguous block delimiters")
print("Index and prose safety checks passed")
check(IndexCardMetadata.marking("---\n\"cardify_index\": false\n---\nBody") == nil, "avoid duplicate quoted index key")
