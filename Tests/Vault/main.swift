import Foundation

// Kaster vault rules: Luhmann IDs, filenames, link rewriting, Research sources, migration.
@main struct Test {
 static func main() {
  // IDs
  let ids: Set<String> = ["1", "2", "3", "3a", "21", "21/1", "21/2", "21/1a", "20251118-001"]
  precondition(LuhmannIDs.nextTopLevel(existing: ids) == "22", "Next top-level follows the highest number, ignoring timestamps")
  precondition(LuhmannIDs.nextTopLevel(existing: []) == "1")
  precondition(try! LuhmannIDs.continuation(of: "21", existing: ids) == "22", "Continue = next card at the same level: \(try! LuhmannIDs.continuation(of: "21", existing: ids))")
  precondition(try! LuhmannIDs.continuation(of: "3", existing: ids) == "4", "Continue from 3 → 4")
  precondition(try! LuhmannIDs.branch(of: "21", existing: ids) == "21/3", "Branch from a top-level card goes one level deeper with a slash")
  precondition(try! LuhmannIDs.branch(of: "4", existing: ids) == "4/1", "First branch of a top-level card uses a slash")
  precondition(try! LuhmannIDs.continuation(of: "21/1", existing: ids) == "21/3", "21/1 continues to the next free sibling (21/2 is taken): \(try! LuhmannIDs.continuation(of: "21/1", existing: ids))")
  precondition(try! LuhmannIDs.continuation(of: "21/1a", existing: ids) == "21/1b", "21/1a → 21/1b")
  precondition(try! LuhmannIDs.branch(of: "21/1", existing: ids) == "21/1b", "Branch adds a letter, skipping used ones")
  precondition(try! LuhmannIDs.branch(of: "21/1a", existing: ids) == "21/1a1", "Branch alternates letters and numbers")
  precondition(LuhmannIDs.isLuhmann("21/3a7") && LuhmannIDs.isLuhmann("3a") && !LuhmannIDs.isLuhmann("20251118-001"))

  // Filenames
  precondition(KasterVault.filename(mode: .zettel, id: "21/3a7", title: "Knowledge: a belief") == "21-3a7-Knowledge a belief.md")
  precondition(KasterVault.filename(mode: .quick, id: nil, title: "  Fitness Contract ") == "Fitness Contract.md")
  precondition(KasterVault.filename(mode: .research, id: nil, title: "") == nil, "No file until there is a title")

  // Links
  let text = "See [[1 Writing System]], [[1 Writing System|Eco]], [[1 writing system#Steps]] and [[Other]]."
  let rewritten = KasterVault.rewriteLinks(in: text, from: ["1 Writing System"], to: "1-Eco's Writing System")!
  precondition(rewritten == "See [[1-Eco's Writing System]], [[1-Eco's Writing System|Eco]], [[1-Eco's Writing System#Steps]] and [[Other]].", rewritten)
  precondition(KasterVault.rewriteLinks(in: "[[Other]]", from: ["Gone"], to: "New") == nil)

  // Research source line
  var research = KasterMode.research.template
  research = KasterVault.setSource(.init(link: "The Name of the Rose", page: "42"), in: research)
  precondition(research.contains("Source: [[The Name of the Rose]], p. 42"), research)
  precondition(KasterVault.source(in: research) == .init(link: "The Name of the Rose", page: "42"))
  research = KasterVault.setSource(.init(link: "How to Write a Thesis", page: nil), in: research)
  precondition(research.components(separatedBy: "Source:").count == 2 && research.contains("Source: [[How to Write a Thesis]]\n"), "Source line is replaced, not duplicated")

  // Mode inference
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-vault-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  precondition(KasterMode.infer(url: root.appendingPathComponent("Zettel/1-A.md"), root: root, text: "") == .zettel)
  precondition(KasterMode.infer(url: root.appendingPathComponent("Loose.md"), root: root, text: "---\ncard_id: \"3a\"\n---\n# A") == .zettel)
  precondition(KasterMode.infer(url: root.appendingPathComponent("Loose.md"), root: root, text: "# A") == .quick)

  // Migration on a vault shaped like a real Cardify folder
  let fm = FileManager.default
  try! fm.createDirectory(at: root.appendingPathComponent("Habit"), withIntermediateDirectories: true)
  try! fm.createDirectory(at: root.appendingPathComponent("Debate"), withIntermediateDirectories: true)
  func write(_ path: String, _ body: String) { try! body.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
  write("1 Writing System.md", "---\ncard_id: \"1\"\n---\n# Eco's Writing System\n\nSee [[3a The metaphor]].\n")
  write("3a The metaphor.md", "---\ncard_id: \"3a\"\n---\n\n# The metaphor of computer-brain\n\nBack to [[1 Writing System]].\n")
  write("Habit/5 Odyssey.md", "---\ncard_id: \"5\"\n---\n# The Odyssey Plan\n")
  write("Habit/Fitness Contract.md", "# Fitness Contract\n\nPush ups.\n")
  write("Channel Identity.md", "# Channel Identity\nCuriosity.\n")
  write("Debate/Weekly Habits - 11:13.md", "# Weekly habits\n\n| Habit | Mon | Tue | Wed | Thu | Fri | Sat | Sun |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n| Read |  |  |  |  |  |  |  |\n")
  let habits = root.appendingPathComponent("Artifacts/Habits")
  let artifactFolders: [KasterArtifact: URL] = [.habits: habits, .todos: root.appendingPathComponent("Artifacts/To-Dos"), .debates: root.appendingPathComponent("Artifacts/Debates")]
  let plan = KasterVault.migrationPlan(root: root, artifactFolders: artifactFolders)
  let moves = Dictionary(uniqueKeysWithValues: plan.steps.map { (KasterVault.relativePath(of: $0.from, in: root)!, $0.to.path.replacingOccurrences(of: root.path + "/", with: "")) })
  precondition(moves["1 Writing System.md"] == "Zettel/1-Eco's Writing System.md", "\(moves)")
  precondition(moves["3a The metaphor.md"] == "Zettel/3a-The metaphor of computer-brain.md", "\(moves)")
  precondition(moves["Habit/5 Odyssey.md"] == "Zettel/5-The Odyssey Plan.md", "\(moves)")
  precondition(moves["Habit/Fitness Contract.md"] == "Quick/Fitness Contract.md", "\(moves)")
  precondition(moves["Channel Identity.md"] == "Quick/Channel Identity.md", "\(moves)")
  precondition(moves["Debate/Weekly Habits - 11:13.md"] == "Artifacts/Habits/Weekly habits.md", "\(moves)")
  precondition(Set(plan.foldersToRemove.map(\.lastPathComponent)) == ["Habit", "Debate"], "Emptied folders are removed")

  try! KasterVault.applyMigration(plan, root: root)
  let eco = try! String(contentsOf: root.appendingPathComponent("Zettel/1-Eco's Writing System.md"), encoding: .utf8)
  precondition(eco.contains("[[3a-The metaphor of computer-brain]]"), "Links follow moved cards: \(eco)")
  let metaphor = try! String(contentsOf: root.appendingPathComponent("Zettel/3a-The metaphor of computer-brain.md"), encoding: .utf8)
  precondition(metaphor.contains("[[1-Eco's Writing System]]"), metaphor)
  precondition(!fm.fileExists(atPath: root.appendingPathComponent("Habit").path) && !fm.fileExists(atPath: root.appendingPathComponent("Debate").path))
  precondition(KasterVault.migrationPlan(root: root, artifactFolders: artifactFolders).steps.isEmpty, "Migration is idempotent")
  // Frontmatter fields
  let plain = "# Title\n\nBody."
  let withUID = KasterFrontmatter.ensuringUID(in: plain)
  precondition(withUID.hasPrefix("---\nuid: ") && withUID.hasSuffix("---\n# Title\n\nBody."), withUID)
  precondition(KasterFrontmatter.ensuringUID(in: withUID) == withUID, "uid is permanent")
  let zettel = "---\ncard_id: \"21/3a\"\n---\n# T\n"
  let ordered = KasterFrontmatter.setting("order", to: "30", in: zettel)!
  precondition(ordered == "---\ncard_id: \"21/3a\"\norder: 30\n---\n# T\n" && KasterFrontmatter.order(in: ordered) == 30)
  precondition(CardMetadata.parse(ordered).id == "21/3a", "Other fields are untouched")
  precondition(KasterFrontmatter.setting("order", to: nil, in: ordered) == zettel, "Removing a field restores the original")
  precondition(KasterFrontmatter.setting("order", to: "1", in: "---\nunterminated: yes\n# T") == nil, "Unterminated frontmatter is never edited")
  let crlf = KasterFrontmatter.setting("uid", to: "abc", in: "---\r\ncard_id: 1\r\n---\r\n# T")!
  precondition(crlf == "---\r\ncard_id: 1\r\nuid: abc\r\n---\r\n# T", "CRLF files keep CRLF")
  print("Vault: Luhmann IDs, filenames, links, sources, mode inference, migration passed")

  // Retitling (sidebar Rename) and titles taken from filenames (Quick cards, Promote)
  let vault = URL(fileURLWithPath: "/tmp/kaster-vault")
  let zettelFile = vault.appendingPathComponent("Zettel/21-3a7-Old idea.md")
  precondition(KasterVault.retitledFilename(for: zettelFile, root: vault, text: "---\ncard_id: \"21/3a7\"\n---\n# Old idea\n", title: "New: idea / here") == "21-3a7-New idea here.md", "Zettel keeps its ID scheme")
  precondition(KasterVault.retitledFilename(for: vault.appendingPathComponent("Quick/Old.md"), root: vault, text: "body", title: "Fresh") == "Fresh.md")
  precondition(KasterVault.retitledFilename(for: vault.appendingPathComponent("Notes/202611131437 Old.md"), root: vault, text: "", title: "New") == "202611131437 New.md", "Timestamp IDs stay")
  precondition(KasterVault.retitledFilename(for: vault.appendingPathComponent("Debates/AFF-1-OB-2 Old.md"), root: vault, text: "", title: "New") == "AFF-1-OB-2 New.md", "Debate IDs stay")
  precondition(KasterVault.retitledFilename(for: zettelFile, root: vault, text: "", title: "  ") == nil, "Empty titles are refused")
  precondition(KasterVault.displayTitle(for: vault.appendingPathComponent("Quick/A Pocket of Infinity.md"), text: "---\nuid: x\n---\n*Three equations.*") == "A Pocket of Infinity", "No heading: filename is the title")
  precondition(KasterVault.displayTitle(for: zettelFile, text: "---\ncard_id: \"21/3a7\"\n---\nno heading") == "Old idea", "Filename IDs are not part of the title")
  precondition(KasterVault.displayTitle(for: zettelFile, text: "# Heading wins\n") == "Heading wins")
  let retitled = NoteEditing.setTitle("Fresh", in: "---\nuid: x\n---\n*Body*")
  precondition(retitled == "---\nuid: x\n---\n# Fresh\n\n*Body*", "A heading is added after the frontmatter: \(retitled)")
  precondition(KasterVault.rewriteLinks(in: "See [[Old]] and [[Old|my label]] and [[Old#Part]].", from: ["Old"], to: "New") == "See [[New]] and [[New|my label]] and [[New#Part]].", "Labelled links keep their label")
  // The one-pass header reader agrees with the single-field reader.
  for sample in ["---\nuid: a1\norder: 30\ncard_id: \"21/3a\"\nzotero-cite: \"Lim, *T*\"\n---\n# T\n", "\u{feff}---\r\nuid: b\r\n---\r\nBody", "---\nuid: x\n# unterminated", "# No header\nuid: no", "---\n  nested: 1\nkey:\n---\n"] {
    let fields = KasterFrontmatter.fields(in: sample)
    for key in ["uid", "order", "card_id", "zotero-cite", "nested", "key"] {
      precondition(fields[key] == KasterFrontmatter.value(key, in: sample), "fields[\(key)] = \(String(describing: fields[key])) vs \(String(describing: KasterFrontmatter.value(key, in: sample))) in \(sample.debugDescription)")
    }
  }
  print("Vault: retitling, filename titles and labelled links passed")

  // Links: the card name alone unless another card shares it.
  let paths = ["Zettel/1-1-Atomic notes", "Research/Canon", "Zettel/Canon", "Quick/Idea"]
  precondition(CardifyNote.shortestLink(for: "Zettel/1-1-Atomic notes", among: paths) == "1-1-Atomic notes")
  precondition(CardifyNote.shortestLink(for: "Research/Canon", among: paths) == "Research/Canon", "Shared names keep their folder")
  precondition(CardifyNote(path: "Quick/Idea").wikiLink(among: paths) == "[[Idea]]")
  precondition(KasterTypesetter.rewriteWikiLinks("See [[Zettel/1-1-Atomic notes]], [[Research/Canon#Part]] and [[Zettel/Canon|the other]].", links: false) == "See 1-1-Atomic notes, Canon#Part and the other.", "Printed links show names, not folders")

  // Tags: sidebar list, ⌘-click narrowing (all tags), and #tag search.
  func libraryCard(_ path: String, _ text: String) -> LibraryCard {
    LibraryCard(url: URL(fileURLWithPath: "/vault/\(path).md"), path: path, title: (path as NSString).lastPathComponent, cardID: nil, content: text)
  }
  let tagCards = [libraryCard("Zettel/A", "# A\nOn #method and #Luhmann."), libraryCard("Zettel/B", "# B\n#method only, see https://x.org/#frag"),
                  libraryCard("Quick/C", "# C\nAbout #luhmann and boxes."), libraryCard("Quick/D", "# Heading\n## Not a tag\nplain")]
  let tagIndex = LibraryIndex(snapshot: LibrarySnapshot(cards: tagCards, outgoing: [:], incoming: [:], unreadable: 0), root: URL(fileURLWithPath: "/vault"))
  precondition(tagIndex.tags.map(\.name) == ["Luhmann", "method"] && tagIndex.tags.map(\.count) == [2, 2], "\(tagIndex.tags)")
  precondition(tagIndex.cards(taggedWithAll: ["luhmann"]).map(\.path) == ["Zettel/A", "Quick/C"])
  precondition(tagIndex.cards(taggedWithAll: ["luhmann", "METHOD"]).map(\.path) == ["Zettel/A"], "⌘-click narrows to cards with all tags")
  precondition(tagIndex.search("#method").map(\.path) == ["Zettel/A", "Zettel/B"])
  precondition(tagIndex.search("#luhmann boxes").map(\.path) == ["Quick/C"], "Tags and words combine")
  precondition(tagIndex.search("heading").map(\.path) == ["Quick/D"], "Plain words still search text")
  precondition(LibraryIndex.tags(in: "url https://a.b/#frag and C# and #ok") == ["ok"], "URL fragments are not tags")
  print("Vault: name-only links, printed link names, tags and #tag search passed")
 }
}
