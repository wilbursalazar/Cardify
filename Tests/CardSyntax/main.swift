@testable import KasterCore
import Foundation

// One definition of links, tags, frontmatter and titles: every reader agrees on the same card.
let card = """
---
uid: abc12345
...
# Canon

See [[Zettel/Apostolic succession#Origins|succession]] and ![[Diagram]] and \\[[escaped]].
Inline `[[not a link]]` stays code. A URL fragment https://x.org/#notatag is no tag; #canon is.

```
[[In a code block]] #alsotag
```

    [[Indented code]]
"""

// Wiki links: real ones only; embeds only when asked.
let links = CardSyntax.wikiLinks(in: card)
precondition(links.map(\.raw) == ["Zettel/Apostolic succession#Origins|succession"], "\(links.map(\.raw))")
precondition(CardSyntax.wikiLinks(in: card, includeEmbeds: true).map(\.raw) == ["Zettel/Apostolic succession#Origins|succession", "Diagram"])
let target = links[0].target
precondition(target.path == "Zettel/Apostolic succession" && target.fragment == "Origins" && target.alias == "succession" && target.name == "Apostolic succession" && target.label == "succession")
precondition(CardSyntax.WikiTarget(" /Folder/Card.md ").path == "Folder/Card" && CardSyntax.WikiTarget("Card#Part").label == "Card#Part" && CardSyntax.WikiTarget("#Part").path.isEmpty)

// The library's backlinks, rename, preview and register read the same links.
func libraryCard(_ path: String, _ content: String) -> LibraryCard { LibraryCard(url: URL(fileURLWithPath: "/v/\(path).md"), path: path, title: path, cardID: nil, content: content) }
let graph = LibraryLinks.build(cards: [libraryCard("Canon", card), libraryCard("Zettel/Apostolic succession", "# A"), libraryCard("In a code block", "# C"), libraryCard("Indented code", "# I")])
precondition(graph.outgoing["Canon"] == ["Zettel/Apostolic succession"], "Links inside code are not backlinks: \(String(describing: graph.outgoing["Canon"]))")
let renamed = KasterVault.rewriteLinks(in: card, from: ["Diagram", "In a code block"], to: "Figure")!
precondition(renamed.contains("![[Figure]]") && renamed.contains("[[In a code block]]"), "Rename follows embeds but never edits code")
let previewed = KasterTypesetter.rewriteWikiLinks(card, links: false)
precondition(previewed.contains("See succession and") && previewed.contains("[[In a code block]]") && previewed.contains("`[[not a link]]`"), previewed)
precondition(KeywordRegister.entry(in: "- Canon: [[A]], `[[code]]`, [[B|Bee]]")?.links == ["A", "B|Bee"])

// Tags: the same everywhere; a URL fragment is not a tag.
precondition(CardSyntax.tags(in: card) == ["canon", "alsotag"], "\(CardSyntax.tags(in: card))")
precondition(KasterText.tags(card) == CardSyntax.tags(in: card) && LibraryIndex.tags(in: card) == CardSyntax.tags(in: card))
precondition(CardSyntax.firstTag(in: card) == "canon" && KasterTypesetter.firstTag(in: card) == "canon")

// Frontmatter: `---` opens; `---` or `...` closes; every reader agrees.
precondition(KasterFrontmatter.fields(in: card)["uid"] == "abc12345" && KasterFrontmatter.value("uid", in: card) == "abc12345")
precondition(NoteEditing.title(in: card) == "Canon", "A '...' close ends the frontmatter for titles too")
precondition(KasterTypesetter.stripFrontmatter(card).hasPrefix("# Canon"))
precondition(MarkdownSource.lines(in: card).frontmatterEnd == 2)
let indented = " ---\nuid: x\n---\n# T"
precondition(KasterFrontmatter.fields(in: indented).isEmpty && MarkdownSource.lines(in: indented).frontmatterEnd == nil && KasterTypesetter.stripFrontmatter(indented) == indented, "An indented --- is not frontmatter anywhere")
precondition(CardSyntax.isFrontmatterOpening("\u{FEFF}---  ") && CardSyntax.isFrontmatterClosing("...\t") && !CardSyntax.isFrontmatterOpening("----x") && !CardSyntax.isFrontmatterClosing("…"))

// Titles: the heading, else the filename without its card ID, in the library and in rename alike.
let root = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-syntax-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
try! FileManager.default.createDirectory(at: root.appendingPathComponent("Zettel"), withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let untitled = root.appendingPathComponent("Zettel/21-Apostolic succession.md")
try! Data("---\ncard_id: \"21\"\n---\nNo heading here.\n".utf8).write(to: untitled)
let scanned = LibrarySnapshot.load(folder: root)!.cards[0]
precondition(scanned.title == "Apostolic succession" && scanned.title == KasterVault.displayTitle(for: untitled, text: scanned.content), scanned.title)
print("Card syntax: links, embeds, code, tags, frontmatter and titles agree everywhere passed")
