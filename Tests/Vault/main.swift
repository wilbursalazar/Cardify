import Foundation

// Kaster vault rules: Luhmann IDs, filenames, link rewriting, Research sources, migration.
@main struct Test {
 static func main() {
  // IDs
  let ids: Set<String> = ["1", "2", "3", "3a", "21", "21/1", "21/2", "21/1a", "20251118-001"]
  precondition(LuhmannIDs.nextTopLevel(existing: ids) == "22", "Next top-level follows the highest number, ignoring timestamps")
  precondition(LuhmannIDs.nextTopLevel(existing: []) == "1")
  precondition(try! LuhmannIDs.continuation(of: "21", existing: ids) == "21/3", "Top-level follow-ups use a slash")
  precondition(try! LuhmannIDs.branch(of: "4", existing: ids) == "4/1", "First branch of a top-level card uses a slash")
  precondition(try! LuhmannIDs.continuation(of: "21/1", existing: ids) == "21/3" || (try! LuhmannIDs.continuation(of: "21/1", existing: ids)).hasPrefix("21/"), "Sub-sequence continues")
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
 }
}
