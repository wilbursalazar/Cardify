import Foundation
import AppKit

struct WorkflowDefaults {
    let idMode: IDMode
    let template: InlineTemplate?
}

enum WorkflowPreference: String, CaseIterable, Identifiable {
    case configured = "configured"
    case luhmann = "luhmann"
    case eco = "eco"
    case obsidian = "obsidian"
    var id: String { rawValue }

    var name: String {
        switch self {
        case .configured: return "As configured"
        case .luhmann: return "Luhmann-inspired"
        case .eco: return "Eco-inspired"
        case .obsidian: return "Obsidian-style"
        }
    }
    var description: String {
        switch self {
        case .configured: return "Start with a blank Markdown card and keep your current ID style."
        case .luhmann: return "Start with the Idea template and a Luhmann-style ID."
        case .eco: return "Start with the Reading template and a title-only filename."
        case .obsidian: return "Start with a blank Markdown card and a title-only filename."
        }
    }

    // An unset or unrecognized preference keeps the behavior of existing installations.
    static func defaults(for stored: String) -> WorkflowDefaults? {
        switch WorkflowPreference(rawValue: stored) ?? .configured {
        case .configured: return nil
        case .luhmann: return WorkflowDefaults(idMode: .luhmann, template: .idea)
        case .eco: return WorkflowDefaults(idMode: .titleOnly, template: .reading)
        case .obsidian: return WorkflowDefaults(idMode: .titleOnly, template: nil)
        }
    }
}
