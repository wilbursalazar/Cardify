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
check(DebateIDs.suggest(role: .aff, existing: ["AFF-01-OB-01-RE-01"]) == "AFF-02", "descendants reserve root numbers")
check(DebateIDs.suggest(role: .aff, existing: ["AFF-01a-OB-01"]) == "AFF-02", "descendants of a lettered root reserve its number")
let roleCodes: [(DebateRole?, String)] = [(.objection, "OB"), (.evidence, "EV"), (.argument, "AR"), (.reply, "RE"), (nil, "NT")]
for (role, code) in roleCodes {
    check(DebateIDs.suggestChild(parentID: "AFF-01", role: role, existing: []) == "AFF-01-\(code)-01", "child code \(code)")
}
check(DebateIDs.suggestChild(parentID: "AFF-01", role: .objection, existing: ["aff-01-ob-01", "AFF-01-OB-03-RE-01", "AFF-01-EV-50"]) == "AFF-01-OB-04", "child sequence is case-insensitive, type-specific, and reserves descendants")
check(DebateIDs.suggestChild(parentID: "AFF-01-OB-01", role: .reply, existing: []) == "AFF-01-OB-01-RE-01", "nested child keeps its full parent ID")
check(DebateIDs.suggestChild(parentID: "1.2", role: .evidence, existing: ["1x2-EV-09"]) == "1.2-EV-01", "parent ID is escaped in regex")
check(DebateIDs.suggestChild(parentID: "", role: .reply, existing: []) == nil && DebateIDs.suggestChild(parentID: "bad\nID", role: .reply, existing: []) == nil && DebateIDs.suggestChild(parentID: "AFF-01", role: .aff, existing: []) == nil, "invalid parent IDs and parent roles are rejected")
check(DebateIDs.suggestChild(parentID: "AFF-01", role: .reply, existing: ["AFF-01-RE-999999999999999999999999"]) == nil, "overflow fails closed")
let linked = DebateNotes.setPrimary("AFF-01 Argument", explanation: "", in: DebateNotes.setRole(.objection, in: "Point\n")!)!
let linkedPrepared = DebateIDs.prepareChild(linked, parentID: "AFF-01", existing: ["AFF-01-OB-01"])!
check(CardMetadata.parse(linkedPrepared).id == "AFF-01-OB-02" && DebateNotes.parse(linkedPrepared).primary != nil, "child gets ID and retains primary parent")
check(DebateIDs.prepareChild("# no parent\n", parentID: "AFF-01", existing: []) == nil, "unlinked child fails safely")
let withCustomID = NoteEditing.addID("Custom", to: linked)!
check(DebateIDs.prepareChild(withCustomID, parentID: "AFF-01", existing: []) == withCustomID, "existing child ID is never rewritten")
let root = FileManager.default.temporaryDirectory.appendingPathComponent("cardify-debate-ids-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
try "# no frontmatter\n".write(to: root.appendingPathComponent("AFF-01 Imported.md"), atomically: true, encoding: .utf8)
try "---\r\ncard_id: DEF-09\r\n---\r\n# Point\r\n".write(to: root.appendingPathComponent("Any name.md"), atomically: true, encoding: .utf8)
let renamed = root.appendingPathComponent("aff-03 Renamed.md")
try "---\ncard_id: Other-42\n---\n# Renamed\n".write(to: renamed, atomically: true, encoding: .utf8)
let nested = root.appendingPathComponent("AFF-01-OB-01-RE-01 Nested.md")
try "# Nested\n".write(to: nested, atomically: true, encoding: .utf8)
let renamedChild = root.appendingPathComponent("aff-01-ob-02 Renamed child.md")
try "---\ncard_id: Other-Child\n---\n# Child\n".write(to: renamedChild, atomically: true, encoding: .utf8)
check(BranchIDs.debateFilenameID(for: nested) == "AFF-01-OB-01-RE-01", "full nested ID is parsed from filename")
check(DebateIDs.parentID(in: "# imported\n", at: nested) == "AFF-01-OB-01-RE-01", "filename-only parent supplies its full ID")
check(DebateIDs.parentID(in: "---\ncard_id: Other-Child\n---\n", at: renamedChild) == "Other-Child", "metadata ID takes priority over filename")
let records = try CardIDIndex.ids(in: root)
check(records.contains { $0.0.caseInsensitiveCompare("AFF-01") == .orderedSame }, "filename-only label reaches save-time duplicate check")
check(records.contains { $0.0.caseInsensitiveCompare("AFF-03") == .orderedSame } && records.contains { $0.0 == "Other-42" }, "renamed file contributes distinct filename and metadata IDs")
check(records.contains { $0.0 == "AFF-01-OB-01-RE-01" } && records.contains { $0.0 == "aff-01-ob-02" } && records.contains { $0.0 == "Other-Child" }, "nested filenames and distinct metadata reach duplicate detection")
let excluding = try CardIDIndex.ids(in: root, excluding: renamed)
check(!excluding.contains { $0.1.standardizedFileURL == renamed.standardizedFileURL }, "the existing save target is excluded, including filename and metadata")
let existing = try DebateIDs.existing(in: [root])
check(DebateIDs.suggest(role: .aff, existing: existing) == "AFF-04", "filename-only and renamed labels are detected")
check(DebateIDs.suggestChild(parentID: "AFF-01", role: .objection, existing: existing) == "AFF-01-OB-03", "vault scan reserves filename-only children and descendants")
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
