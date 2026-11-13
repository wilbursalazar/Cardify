import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let input = "---\r\n# Important metadata comment\r\ncard_id: 1a\r\ntags: [memory]\r\n---\r\n# Real title\r\nBody\r\n"
check(CardMetadata.parse(input).id == "1a", "CRLF unquoted ID")
check(NoteEditing.title(in: input) == "Real title", "CRLF title after frontmatter")
let renamed = NoteEditing.setTitle("New title", in: input)
check(renamed == input.replacingOccurrences(of: "# Real title", with: "# New title"), "title edit preserves metadata, all other bytes and CRLF")
let revisedID = NoteEditing.setID("1b", in: input)
check(revisedID == input.replacingOccurrences(of: "card_id: 1a", with: "card_id: \"1b\""), "ID edit preserves frontmatter and CRLF")
let noID = "---\r\n# metadata\r\ntags: [a]\r\n---\r\n# Title\r\nBody\r\n"
check(NoteEditing.addID("2a", to: noID) == noID.replacingOccurrences(of: "tags: [a]\r\n---", with: "tags: [a]\r\ncard_id: \"2a\"\r\n---"), "add ID to existing CRLF frontmatter without a second block")
let mixed = "---\r\n# comment\ntags: [a]\r\n---\r\n# Old title\nBody\r\n"
check(NoteEditing.setTitle("New title", in: mixed) == mixed.replacingOccurrences(of: "# Old title", with: "# New title"), "mixed line endings remain byte-for-byte unchanged outside title")
let bom = "\u{FEFF}---\r\ncard_id: 3a\r\n---\r\n# Title\r\nBody"
check(CardMetadata.parse(bom).id == "3a" && NoteEditing.title(in: bom) == "Title", "BOM and CRLF recognized")
check(NoteEditing.setTitle("Next", in: bom) == bom.replacingOccurrences(of: "# Title", with: "# Next"), "BOM retained")
let withComment = "---\r\ncard_id: 1a  # an ID comment\r\n---\r\n# Title\r\n"
check(NoteEditing.setID("1b", in: withComment) == withComment.replacingOccurrences(of: "1a  #", with: "\"1b\"  #"), "ID update retains inline comment")
let multiline = "---\r\ndescription: |\r\n  ---\r\n  # metadata content\r\ncard_id: 9a\r\n---\r\n# Real heading\r\n"
check(CardMetadata.parse(multiline).id == "9a", "indented YAML divider isn't a frontmatter close")
check(NoteEditing.title(in: multiline) == "Real heading", "indented YAML comment isn't a title")
check(NoteEditing.setTitle("Changed", in: multiline) == multiline.replacingOccurrences(of: "# Real heading", with: "# Changed"), "metadata block preserved")
check(CardMetadata.parse(NoteEditing.setID("1b", in: withComment)!).id == "1b", "edited quoted ID with comment remains readable")
let nested = "---\r\nsummary: |\r\n  card_id: not-the-id\r\ncard_id: actual\r\n---\r\n# Title\r\n"
check(CardMetadata.parse(nested).id == "actual", "nested card_id is not top-level metadata")
check(NoteEditing.setID("new", in: nested) == nested.replacingOccurrences(of: "card_id: actual", with: "card_id: \"new\""), "nested metadata isn't changed")
let decomposed = "# Cafe\u{301}\r\nOther Cafe\u{301}\r\n"
check(Data(NoteEditing.setTitle("New", in: decomposed).utf8) == Data("# New\r\nOther Cafe\u{301}\r\n".utf8), "unrelated Unicode bytes are preserved")
let incomplete = "---\r\n# metadata\r\ncard_id: 7\r\n"
check(NoteEditing.setTitle("Bad", in: incomplete) == incomplete, "incomplete frontmatter is not silently edited")
check(NoteEditing.addID("8", to: incomplete) == nil, "no second YAML block for malformed frontmatter")
let root = FileManager.default.temporaryDirectory.appendingPathComponent("cardify-crlf-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
try input.write(to: root.appendingPathComponent("Ordinary title.md"), atomically: true, encoding: .utf8)
let ids = try CardIDIndex.ids(in: root)
check(ids.contains { $0.0.caseInsensitiveCompare("1a") == .orderedSame }, "CRLF ID included in duplicate-ID scan")
let templateInput = "---\r\ncard_id: 5\r\n---\r\n# Parent\r\nBody\r\n"
let inserted = InlineTemplate.idea.inserting(in: templateInput, at: (templateInput as NSString).length).text
check(!inserted.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "template uses CRLF")
check(inserted.hasPrefix(templateInput), "template does not alter existing CRLF bytes")
let bomTemplate = InlineTemplate.idea.inserting(in: bom, at: 0).text
check(bomTemplate.hasPrefix("\u{FEFF}---\r\ncard_id: 3a\r\n---\r\n"), "template doesn't split BOM frontmatter")
check(InlineTemplate.idea.inserting(in: incomplete, at: 0).text == incomplete, "template leaves incomplete frontmatter untouched")
print("CRLF parsing, safe editing, duplicate IDs, BOM and templates passed")
