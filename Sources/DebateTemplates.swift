import Foundation

// These are ordinary Markdown paragraphs. The shared Title field adds a single
// heading only when the user enters a title; role and relationship metadata are
// applied separately by DebateNotes.
enum DebateTemplates {
    static func body(for role: DebateRole?) -> String {
        switch role {
        case .project: return ""
        case .aff: return "Argument:\n\nReasons:\n\nSource:\n\n"
        case .def: return "Defense:\n\nReasons:\n\nSource:\n\n"
        case .evidence: return "Evidence:\n\nSource:\n\n"
        case .objection: return "Objection:\n\nResponse:\n\nSource:\n\n"
        case .argument: return "Argument:\n\nReasoning:\n\nSource:\n\n"
        case .reply: return "Reply:\n\nSource:\n\n"
        case nil: return ""
        }
    }
}
