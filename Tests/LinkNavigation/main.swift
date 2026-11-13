import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let manager = FileManager.default
let base = manager.temporaryDirectory.appendingPathComponent("cardify-link-tests-" + UUID().uuidString, isDirectory: true)
let root = base.appendingPathComponent("vault", isDirectory: true)
let outside = base.appendingPathComponent("outside", isDirectory: true)
try manager.createDirectory(at: root.appendingPathComponent("A"), withIntermediateDirectories: true)
try manager.createDirectory(at: root.appendingPathComponent("B"), withIntermediateDirectories: true)
try manager.createDirectory(at: outside, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: base) }
func write(_ path: String) throws -> URL {
    let url = root.appendingPathComponent(path)
    try "# Heading\ntext\n".write(to: url, atomically: true, encoding: .utf8)
    return url.resolvingSymlinksInPath().standardizedFileURL
}
let first = try write("First.md")
let other = try write("A/Other.MD")
let sibling = try write("B/With spaces.md")
let source = try write("A/Source.md")
_ = try write("A/Duplicate.md")
_ = try write("B/Duplicate.md")
try "private".write(to: outside.appendingPathComponent("secret.md"), atomically: true, encoding: .utf8)
try manager.createSymbolicLink(at: root.appendingPathComponent("alias.md"), withDestinationURL: outside.appendingPathComponent("secret.md"))
try manager.createSymbolicLink(at: root.appendingPathComponent("outside-dir"), withDestinationURL: outside)
func resolve(_ target: CardLinkTarget, _ file: URL? = nil, _ folder: URL? = root) -> CardLinkResolution {
    CardLinkNavigation.resolve(target, folder: folder, currentFile: file)
}
check(resolve(.wiki("First")) == .note(first, fragment: nil), "simple wiki link")
check(resolve(.wiki("A/Other|alias")) == .note(other, fragment: nil), "path, alias and uppercase extension")
check(resolve(.wiki("A/Other#Heading|alias")) == .note(other, fragment: "Heading"), "heading and alias")
check(resolve(.wiki("#Heading"), nil, nil) == .current(fragment: "Heading"), "unsaved current-note wiki heading")
check(resolve(.url("#Heading"), nil, nil) == .current(fragment: "Heading"), "unsaved current-note Markdown heading")
check(resolve(.url("../B/With%20spaces.md#Heading"), source) == .note(sibling, fragment: "Heading"), "safe Markdown parent link and percent encoding")
check(resolve(.url("Other.MD"), source) == .note(other, fragment: nil), "Markdown relative to current note")
if case .failure = resolve(.wiki("Duplicate")) {} else { check(false, "ambiguous unqualified name") }
if case .failure = resolve(.wiki("Missing")) {} else { check(false, "missing note") }
if case .failure = resolve(.wiki("First#^block")) {} else { check(false, "unsupported block") }
if case .failure = resolve(.url("../../outside/secret.md"), source) {} else { check(false, "outside vault traversal") }
if case .failure = resolve(.wiki("../outside/secret"), source) {} else { check(false, "wiki parent traversal") }
if case .failure = resolve(.wiki("alias")) {} else { check(false, "symlink file") }
if case .failure = resolve(.wiki("outside-dir/secret")) {} else { check(false, "symlink folder") }
if case .failure = resolve(.url("file:///private/file")) {} else { check(false, "file URL") }
if case .failure = resolve(.url("javascript:alert(1)")) {} else { check(false, "script URL") }
if case .external(let url) = resolve(.url("https://example.com/test")) { check(url.host == "example.com", "web URL") } else { check(false, "web URL") }
if case .external(let url) = resolve(.url("zotero://select/library/items/ABCD")) { check(url.scheme == "zotero", "Zotero URL") } else { check(false, "Zotero URL") }
let content = "---\n# Metadata comment\ntags: [test]\n---\n😀 Preface\n```\n# Not real\n```\n## Actual Heading ##\nbody"
let location = CardLinkNavigation.headingRange("Actual Heading", in: content)
check(location != nil && (content as NSString).substring(with: location!) == "Actual Heading", "UTF-16 heading location")
check(CardLinkNavigation.headingRange("Metadata comment", in: content) == nil, "ignore frontmatter comments")
check(CardLinkNavigation.headingRange("Not real", in: content) == nil, "ignore fenced code")
check(CardLinkNavigation.headingRange("Missing", in: content) == nil, "missing heading")
check(CardLinkNavigation.headingRange("^block", in: content) == nil, "block heading unsupported")
print("Link resolution, aliases, anchors, paths, duplicate names, symlinks, schemes, and UTF-16 headings passed")
