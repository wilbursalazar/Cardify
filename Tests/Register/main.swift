@testable import KasterCore
import Foundation

var text = ""
text = KeywordRegister.adding("Zettel/1-1-Atomic", to: "Atomicity", in: text)
precondition(text == KeywordRegister.template + "- Atomicity: [[Zettel/1-1-Atomic]]\n", text.debugDescription)
text = KeywordRegister.adding("One idea", to: "atomicity", in: text)
text = KeywordRegister.adding("One idea", to: "ATOMICITY", in: text)
precondition(KeywordRegister.entries(in: text) == [.init(keyword: "Atomicity", links: ["Zettel/1-1-Atomic", "One idea"])], "Case-insensitive keyword, no duplicate link")
text = KeywordRegister.adding("Canon", to: "Bible", in: text)
text = KeywordRegister.adding("Box", to: "Archive", in: text)
text = KeywordRegister.adding("Writing", to: "Zettelkasten", in: text)
let keywords = text.components(separatedBy: "\n").compactMap { KeywordRegister.entry(in: $0)?.keyword }
precondition(keywords == ["Archive", "Atomicity", "Bible", "Zettelkasten"], "Entries stay alphabetical in the file: \(keywords)")
let withNote = text.replacingOccurrences(of: "# Register\n", with: "# Register\n\nMy own note stays.\n")
precondition(KeywordRegister.adding("X", to: "Method", in: withNote).contains("My own note stays."), "Other lines are kept")
text = KeywordRegister.removing("One idea", from: "atomicity", in: text)
precondition(KeywordRegister.entries(in: text).first { $0.keyword == "Atomicity" }?.links == ["Zettel/1-1-Atomic"])
text = KeywordRegister.removing(nil, from: "Bible", in: text)
precondition(!KeywordRegister.entries(in: text).contains { $0.keyword == "Bible" })
precondition(KeywordRegister.entry(in: "- [[Not]]: a keyword") == nil && KeywordRegister.entry(in: "plain: text") == nil)
precondition(KeywordRegister.entries(in: "- Crlf: [[A]]\r\n- Beta: [[B]], [[C|alias]]\r\n").map(\.keyword) == ["Beta", "Crlf"])
let cards = KeywordRegister.printCards((0..<20).map { KeywordRegister.Entry(keyword: String(UnicodeScalar(65 + $0)!) + "word", links: ["Zettel/Card \($0)"]) })
precondition(cards.count == 3 && cards[0].hasPrefix("# Register A–I\n\n**Aword** — Card 0  \n"), cards[0])
print("Keyword register: entries, alphabetical order, duplicates, removal, kept lines and print cards passed")
