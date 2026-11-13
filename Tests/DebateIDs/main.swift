import Foundation

func check(_ result: @autoclosure () -> Bool, _ message: String) {
    if !result() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
check(DebateIDs.suggest(role: .aff, existing: []) == "AFF-01", "first AFF")
check(DebateIDs.suggest(role: .def, existing: ["aff-99"]) == "DEF-01", "series are separate")
check(DebateIDs.suggest(role: .aff, existing: ["aff-01", "AFF-03", "AFF-02a"]) == "AFF-04", "case-insensitive monotonic sequence without renumbering")
check(DebateIDs.suggest(role: .def, existing: ["def-1", "DEF-0002"]) == "DEF-03", "equivalent numeric labels are reserved")
check(DebateIDs.suggest(role: .aff, existing: ["AFF-01a"]) == "AFF-02", "a branch reserves its parent serial")
check(DebateIDs.suggest(role: .project, existing: []) == nil && DebateIDs.suggest(role: .evidence, existing: []) == nil, "only major points get these IDs")
let newAff = "# Idea\n\n<!-- cardify:debate=aff -->\n"
let prepared = DebateIDs.prepare(newAff, existing: ["AFF-01"])!
check(CardMetadata.parse(prepared).id == "AFF-02" && prepared.contains(newAff), "new parent gets generated ID and retains text")
let explicit = "---\r\ncard_id: Custom-12\r\n---\r\n# Existing\r\n<!-- cardify:debate=def -->\r\n"
check(DebateIDs.prepare(explicit, existing: ["DEF-01"]) == explicit, "existing ID and CRLF are untouched")
let child = "# Evidence\n<!-- cardify:debate=evidence -->\n"
check(DebateIDs.prepare(child, existing: []) == child, "child receives no parent ID")
let project = "# Resolution\n<!-- cardify:debate=project -->\n"
check(DebateIDs.prepare(project, existing: []) == project, "resolution receives no parent ID")
let invalid = "---\ncard_id: \"unterminated\n---\n# Title\n<!-- cardify:debate=aff -->\n"
check(DebateIDs.prepare(invalid, existing: []) == nil, "malformed IDs fail safely")
check(DebateIDs.prepare("---\n# unterminated metadata\n", existing: []) == nil, "unfinished metadata fails safely")
let root = FileManager.default.temporaryDirectory.appendingPathComponent("cardify-debate-ids-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
try "# no frontmatter\n".write(to: root.appendingPathComponent("AFF-01 Imported.md"), atomically: true, encoding: .utf8)
try "---\r\ncard_id: DEF-09\r\n---\r\n# Point\r\n".write(to: root.appendingPathComponent("Any name.md"), atomically: true, encoding: .utf8)
let renamed = root.appendingPathComponent("aff-03 Renamed.md")
try "---\ncard_id: Other-42\n---\n# Renamed\n".write(to: renamed, atomically: true, encoding: .utf8)
let records = try CardIDIndex.ids(in: root)
check(records.contains { $0.0.caseInsensitiveCompare("AFF-01") == .orderedSame }, "filename-only label reaches save-time duplicate check")
check(records.contains { $0.0.caseInsensitiveCompare("AFF-03") == .orderedSame } && records.contains { $0.0 == "Other-42" }, "renamed file contributes distinct filename and metadata IDs")
let excluding = try CardIDIndex.ids(in: root, excluding: renamed)
check(!excluding.contains { $0.1.standardizedFileURL == renamed.standardizedFileURL }, "the existing save target is excluded, including filename and metadata")
let existing = try DebateIDs.existing(in: [root])
check(DebateIDs.suggest(role: .aff, existing: existing) == "AFF-04", "filename-only and renamed labels are detected")
check(DebateIDs.suggest(role: .def, existing: existing) == "DEF-10", "CRLF metadata ID detected")
let alias = root.deletingLastPathComponent().appendingPathComponent("cardify-debate-ids-alias-" + UUID().uuidString)
try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
defer { try? FileManager.default.removeItem(at: alias) }
let aliasExisting = try DebateIDs.existing(in: [alias])
check(DebateIDs.suggest(role: .aff, existing: aliasExisting) == "AFF-04", "a symlinked notes folder is resolved safely")
try "---\ncard_id: \"unterminated\n---\n".write(to: root.appendingPathComponent("bad.md"), atomically: true, encoding: .utf8)
do { _ = try DebateIDs.existing(in: [root]); fatalError("Unreadable ID metadata must fail closed") } catch {}
do { _ = try DebateIDs.existing(in: []); fatalError("Missing folder must fail closed") } catch {}
do { _ = try DebateIDs.existing(in: [root.appendingPathComponent("missing")]); fatalError("Unreadable folder must fail closed") } catch {}
print("Debate AFF/DEF ID sequencing, filename collisions, imported metadata and safe scanning passed")
