import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let roles: [DebateRole] = [.project, .aff, .def, .evidence, .objection, .argument, .reply]
for role in roles {
    let body = DebateTemplates.body(for: role)
    check(!body.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.hasPrefix("#") }, "\(role) must not create empty or placeholder Markdown headings")
    guard let marked = DebateNotes.setRole(role, in: body) else { fatalError("Could not mark \(role)") }
    check(DebateNotes.parse(marked).role == role, "\(role) marker is retained")
    check(NoteEditing.title(in: marked).isEmpty, "\(role) has no phantom title")
    let titled = NoteEditing.setTitle("Test title", in: marked)
    check(NoteEditing.title(in: titled) == "Test title", "\(role) title is created when entered")
    check(titled.contains("# Test title") && DebateNotes.parse(titled).role == role, "\(role) title is ordinary Markdown and retains the role")
    check(!titled.contains("# \n"), "\(role) does not add an empty heading")
    if !body.isEmpty { check(titled.contains(body), "\(role) prompts survive title editing") }
}
check(DebateTemplates.body(for: nil).isEmpty, "untyped connected note has a blank body")
check(DebateTemplates.body(for: .objection).contains("Objection:") && DebateTemplates.body(for: .objection).contains("Response:"), "objection prompts")
check(DebateTemplates.body(for: .evidence).contains("Evidence:") && DebateTemplates.body(for: .evidence).contains("Source:"), "evidence prompts")
check(DebateTemplates.body(for: .argument).contains("Argument:") && DebateTemplates.body(for: .reply).contains("Reply:"), "argument and reply prompts")
let imported = "\u{FEFF}---\r\ncard_id: \"AFF-01\"\r\ntags: [research]\r\n---\r\n\r\nObjection:\r\n\r\n<!-- cardify:debate=objection -->\r\nPrimary parent: [[Debate/AFF-01]]\r\n"
let titled = NoteEditing.setTitle("An objection", in: imported)
check(titled == imported.replacingOccurrences(of: "---\r\n\r\nObjection:", with: "---\r\n# An objection\r\n\r\n\r\nObjection:"), "title insertion preserves CRLF, metadata, prompts, and parent link")
check(CardMetadata.parse(titled).id == "AFF-01" && DebateNotes.parse(titled).primary?.path == "Debate/AFF-01", "metadata and parent link remain readable")
print("Debate prompts, no phantom headings, title editing and CRLF preservation passed")
