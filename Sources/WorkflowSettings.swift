import SwiftUI

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

struct WorkflowSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("newCardWorkflow") private var storedWorkflow = WorkflowPreference.configured.rawValue
    @AppStorage("dotGrid") private var dotGrid = false
    @AppStorage("timestampDateStyle") private var timestampDateStyle = TimestampDateStyle.sortable.rawValue
    @AppStorage("timestampIncludeTime") private var timestampIncludeTime = true
    private var preference: WorkflowPreference { WorkflowPreference(rawValue: storedWorkflow) ?? .configured }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2.bold())
            Text("Appearance").font(.headline)
            AppearanceSettings()
            Toggle("Dot grid on cards", isOn: $dotGrid)
                .help("Show a light dot grid in the preview and on printed cards.")
            Text("New Markdown cards").font(.headline)
            Picker("Starting workflow", selection: Binding(get: { preference }, set: { storedWorkflow = $0.rawValue })) {
                ForEach(WorkflowPreference.allCases) { choice in Text(choice.name).tag(choice) }
            }
            Text(preference.description).foregroundStyle(.secondary)
            Picker("Timestamp date", selection: Binding(get: { TimestampDateStyle(rawValue: timestampDateStyle) ?? .sortable }, set: { timestampDateStyle = $0.rawValue })) {
                ForEach(TimestampDateStyle.allCases) { choice in Text(choice.title).tag(choice) }
            }
            Toggle("Include hours and minutes in timestamp", isOn: $timestampIncludeTime)
            Text("Examples: 20261113, 13-11-26, or 11-13-26. Time adds hours and minutes. Existing IDs stay the same.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("These are starting defaults for New Card. You can still use any template, ID style, source, or link. Existing cards and the current draft are not changed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 540, height: 470)
    }
}
