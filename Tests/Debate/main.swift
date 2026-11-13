import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
for role in [DebateRole.evidence, .objection, .argument, .reply] {
 let original = "# Connected note\n"
 let marked = DebateNotes.setRole(role, in: original)!
 check(DebateNotes.parse(marked).role == role && marked.hasPrefix(original), "Typed connected notes retain their Markdown")
}
let note = "# A claim\n\nResearch and evidence.\n"
let aff = DebateNotes.setRole(.aff, in: note)!
check(aff.hasPrefix(note), "setting a role preserves existing text")
check(DebateNotes.parse(aff).role == .aff && DebateNotes.parse(aff).valid, "AFF parent is recognized")
let changed = DebateNotes.setRole(.def, in: aff)!
check(DebateNotes.parse(changed).role == .def && !changed.contains("debate=aff"), "role can be changed without duplicate marker")
let project1 = DebateNotes.addProject("Debates/First", in: changed)!
let project2 = DebateNotes.addProject("Debates/Second", in: project1)!
check(DebateNotes.parse(project2).projects.map(\.path) == ["Debates/First", "Debates/Second"], "a point can belong to multiple projects")
check(DebateNotes.addProject("debates/FIRST", in: project2) == nil, "duplicate project links are refused")
check(DebateNotes.removeProject("Debates/First", in: project2) == project1.replacingOccurrences(of: "Debate project: [[Debates/First]]\n", with: "") + "Debate project: [[Debates/Second]]\n", "only selected project removed")
let child = "# Evidence\n\nOne source, several arguments.\n"
let primary = DebateNotes.setPrimary("Claims/AFF-01", explanation: "supports premise 1", in: child)!
let linked = DebateNotes.addRelated("Claims/AFF-03", explanation: "context", in: primary)!
let info = DebateNotes.parse(linked)
check(info.valid && info.primary == DebateRelation(path: "Claims/AFF-01", explanation: "supports premise 1"), "one primary parent and explanation")
check(info.related == [DebateRelation(path: "Claims/AFF-03", explanation: "context")], "related parent and explanation")
check(DebateNotes.addRelated("claims/aff-01", explanation: "duplicate", in: linked) == nil, "primary cannot also be a related parent")
check(DebateNotes.addRelated("CLAIMS/aff-03", explanation: "duplicate", in: linked) == nil, "duplicate related parents refused")
check(DebateNotes.setPrimary("Claims/AFF-03", explanation: "", in: linked) == nil, "cannot silently discard an existing related connection")
let reassigned = DebateNotes.setPrimary("Claims/DEF-01", explanation: "responds to", in: linked)!
check(DebateNotes.parse(reassigned).primary?.path == "Claims/DEF-01" && DebateNotes.parse(reassigned).related.count == 1, "reassign primary without altering related parents")
check(DebateNotes.setPrimary(nil, explanation: "", in: reassigned) == nil, "primary cannot be removed while secondary links remain")
let removedRelated = DebateNotes.removeRelated("Claims/AFF-03", in: reassigned)!
check(DebateNotes.setPrimary(nil, explanation: "", in: removedRelated) == child, "removing relationships preserves note")
check(DebateNotes.addRelated("Claims/AFF-03", explanation: "", in: child) == nil, "related parent requires a primary")
check(DebateNotes.setPrimary("Claims/AFF-01", explanation: "<!-- unfinished", in: child) == nil, "description cannot create an unfinished HTML comment")
check(DebateNotes.setPrimary(nil, explanation: "", in: "Primary parent: [[A]]\n---\nplain text\n") == nil, "removing first line cannot create unfinished frontmatter")
let orphan = child + "Related parent: [[Claims/AFF-03]] — context\n"
check(DebateNotes.parse(orphan).valid && DebateNotes.removeRelated("Claims/AFF-03", in: orphan) == child, "orphan secondary link can be removed")
check(DebateNotes.setPrimary("Claims/AFF-01", explanation: "", in: orphan) != nil, "orphan secondary link can be repaired by assigning a primary")
for path in ["", "../outside", "a/../secret", "/absolute", "a//b", "bad#heading", "bad|alias", "bad]bracket", "bad\\path", "bad\npath"] {
 check(!DebateNotes.validPath(path) && DebateNotes.addRelated(path, explanation: "", in: child) == nil, "unsafe path is rejected: \(path)")
}
for unsafe in [
 "<!-- cardify:debate=aff -->\n<!-- cardify:debate=def -->\n",
 "Primary parent: [[A]]\nPrimary parent: [[B]]\n",
 "Primary parent: [[A]]\nRelated parent: [[a]]\n",
 "Related parent: [[A]]\nRelated parent: [[a]]\n",
 "Debate project: [[Project]]\nDebate project: [[project]]\n",
 "Primary parent: broken link\n",
 "<!-- cardify:debate=unknown -->\n"
] {
 check(!DebateNotes.parse(unsafe).valid, "duplicate or malformed recognized syntax is unsafe")
 check(DebateNotes.setRole(.aff, in: unsafe) == nil, "unsafe note is left untouched")
}
let fenced = "# Note\n\n```md\n<!-- cardify:debate=def -->\nPrimary parent: [[Not a parent]]\n```\n\n    <!-- cardify:debate=aff -->\n"
let fencedInfo = DebateNotes.parse(fenced)
check(fencedInfo.valid && fencedInfo.role == nil && fencedInfo.primary == nil, "fenced and indented examples are not treated as metadata")
check(DebateNotes.setRole(.aff, in: "# note\n\n```\nunfinished\n") == nil, "do not append inside unfinished fence")
let commented = "# Note\n<!--\nPrimary parent: [[Not a parent]]\n<!-- cardify:debate=def -->\n-->\n"
check(DebateNotes.parse(commented).primary == nil && DebateNotes.parse(commented).role == nil, "HTML comments are not relationships")
check(DebateNotes.setRole(.aff, in: "# note\n<!-- unfinished\n") == nil, "do not append inside unfinished HTML comment")
check(DebateNotes.setRole(.aff, in: "# note\n<!-- closed --> <!-- unfinished\n") == nil, "do not append after second unfinished HTML comment")
let frontmatter = "\u{FEFF}---\r\n# comment\r\nsummary: |\r\n  ---\r\n  Primary parent: [[Not a parent]]\r\nPrimary parent: [[YAML value]]\r\n---\r\n# Title\r\nBody Cafe\u{301}\r\n"
let frontInfo = DebateNotes.parse(frontmatter)
check(frontInfo.valid && frontInfo.primary == nil, "YAML frontmatter is ignored, including scalar and top-level lines")
let withParent = DebateNotes.setPrimary("Claims/A", explanation: "supports", in: frontmatter)!
check(Data(withParent.utf8).starts(with: Data(frontmatter.utf8)), "BOM, decomposed Unicode, existing text and CRLF bytes are preserved")
check(!withParent.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "new lines follow CRLF")
check(DebateNotes.setRole(.aff, in: "---\r\n# not finished\r\n") == nil, "unfinished frontmatter refuses editing")
let bomFirst = "\u{FEFF}Primary parent: [[Claims/A]]\r\n# Body\r\n"
check(DebateNotes.setPrimary(nil, explanation: "", in: bomFirst) == "\u{FEFF}# Body\r\n", "removing first relation preserves BOM")
let mixed = "# Title\r\nBody\nRelated parent: [[Claims/A]] — proof\r\nOther\n"
check(DebateNotes.removeRelated("Claims/A", in: mixed) == "# Title\r\nBody\nOther\n", "unrelated mixed line endings remain unchanged")
// Relationship direction belongs to the primary edge, not the note's kind.
for role in [DebateRole.objection, .evidence, .argument, .reply] {
 let legacy = DebateNotes.setPrimary("Claims/A", explanation: "", in: DebateNotes.setRole(role, in: "# Old note\n")!)!
 let before = DebateNotes.parse(legacy)
 check(before.valid && before.explicitStance == nil && before.primaryStance == nil, "legacy role never implies link stance")
 check(DebateNotes.setStance(nil, in: legacy) == legacy, "reading an unclassified legacy note never rewrites it")
 for stance in [DebateStance.supports, .challenges] {
  let updated = DebateNotes.setStance(stance, in: legacy)!
  let info = DebateNotes.parse(updated)
  check(info.valid && info.role == role && info.primary == before.primary && info.explicitStance == stance && info.primaryStance == stance, "explicit stance is independent of the card type")
  check(DebateNotes.setStance(nil, in: updated) == legacy, "clearing a stance preserves the original legacy note")
 }
}
let crlfNote = "\u{FEFF}---\r\ncard_id: A\r\n---\r\n# Title\r\nPrimary parent: [[Claims/A]]\r\n"
let support = DebateNotes.setStance(.supports, in: crlfNote)!
check(support.hasPrefix(crlfNote) && !support.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "stance preserves BOM and CRLF")
let changedStance = DebateNotes.setStance(.challenges, in: support)!
check(DebateNotes.parse(changedStance).primaryStance == .challenges && !changedStance.contains("stance=supports"), "stance changes without duplicate markers")
let sameParent = DebateNotes.setPrimary("claims/a", explanation: "updated reason", in: support)!
check(DebateNotes.parse(sameParent).primaryStance == .supports, "same parent keeps its stance")
let differentParent = DebateNotes.setPrimary("Claims/B", explanation: "", in: support)!
check(DebateNotes.parse(differentParent).primaryStance == nil && !differentParent.contains("cardify:stance="), "reparenting clears old edge stance")
let removedParent = DebateNotes.setPrimary(nil, explanation: "", in: support)!
check(DebateNotes.parse(removedParent).primary == nil && !removedParent.contains("cardify:stance="), "removing a parent clears its stance")
let fencedStance = "# Example\n\n```md\n<!-- cardify:stance=supports -->\n```\n"
check(DebateNotes.parse(fencedStance).valid && DebateNotes.parse(fencedStance).explicitStance == nil, "stance examples in code are ignored")
let commentedStance = "# Example\n<!--\n<!-- cardify:stance=supports -->\n-->\n"
check(DebateNotes.parse(commentedStance).explicitStance == nil, "stance examples in comments are ignored")
for invalidStance in ["<!-- cardify:stance=unknown -->\n", "<!-- cardify:stance=supports -->\n<!-- cardify:stance=challenges -->\n", "<!-- cardify:stance=supports\n"] {
 check(!DebateNotes.parse(invalidStance).valid && DebateNotes.setStance(.supports, in: invalidStance) == nil, "malformed stance metadata is left intact")
}
check(DebateNotes.setStance(.supports, in: "# Unconnected\n") == nil, "cannot assign a stance without a primary parent")
let noParent = "# Unconnected\n<!-- cardify:stance=supports -->\n"
check(DebateNotes.parse(noParent).explicitStance == .supports && DebateNotes.parse(noParent).primaryStance == nil, "an orphan marker does not classify a missing primary relation")
let attached = DebateNotes.setPrimary("Claims/New", explanation: "", in: noParent)!
check(DebateNotes.parse(attached).primaryStance == nil && !attached.contains("cardify:stance="), "an orphan marker is cleared before classifying a new primary edge")
print("Debate Markdown roles, multiple projects, primary and related links, safe edits and CRLF passed")
