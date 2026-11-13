import Foundation
struct LibraryCard: Identifiable {
 let url: URL; let path: String; let title: String; let cardID: String?; let content: String
 var id: String { path }
}
@main struct Check {
 static func main() {
  let plain = "# Memory\n\n- [[Other]] — useful\n"
  let inserted = IndexCardMetadata.marking(plain)!
  precondition(inserted == "---\ncardify_index: true\n---\n" + plain)
  precondition(IndexCardMetadata.isIndex(inserted))
  precondition(IndexCardMetadata.marking(inserted) == inserted)
  let existing = "---\ncard_id: 1a\ntags: [memory, archive]\n---\n# Memory\n"
  let added = IndexCardMetadata.marking(existing)!
  precondition(added == "---\ncard_id: 1a\ntags: [memory, archive]\ncardify_index: true\n---\n# Memory\n")
  precondition(IndexCardMetadata.isIndex(added))
  let disabled = "---\ncardify_index: false # keep this\nother: yes\n---\nBody"
  precondition(IndexCardMetadata.marking(disabled) == "---\ncardify_index: true # keep this\nother: yes\n---\nBody")
  let crlf = "---\r\ncard_id: 1\r\n---\r\n# Hi\r\n"
  precondition(IndexCardMetadata.marking(crlf) == "---\r\ncard_id: 1\r\ncardify_index: true\r\n---\r\n# Hi\r\n")
  let mixed = "---\ncard_id: 1\n---\nBody\r\n"
  precondition(IndexCardMetadata.marking(mixed) == "---\ncard_id: 1\ncardify_index: true\n---\nBody\r\n")
  precondition(IndexCardMetadata.marking("\u{FEFF}---\nkey: value\n---\nBody") == nil)
  let cases = ["---\ncardify_index: true\ncardify_index: false\n---\n", "---\ncardify_index: quoted\n---\n", "---\ncardify_index: \"true\"\n---\n", "---\ncardify_index: 'true'\n---\n", "---\ncard_id: 1\n", "---\nnested:\n  cardify_index: true\n---\n"]
  for value in cases { precondition(IndexCardMetadata.marking(value) == nil); precondition(!IndexCardMetadata.isIndex(value)) }
  let padded = "---  \ncard_id: 1\n--- \n# Hi"
  precondition(IndexCardMetadata.marking(padded) == "---  \ncard_id: 1\ncardify_index: true\n--- \n# Hi")
  print("Index marker preserves existing metadata, line endings, comments and user text; refuses malformed, duplicate, nested and conflicting keys")
 }
}
