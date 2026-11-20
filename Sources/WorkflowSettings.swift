import SwiftUI
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

struct WorkflowSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("newCardWorkflow") private var storedWorkflow = WorkflowPreference.configured.rawValue
    @AppStorage("dotGrid") private var dotGrid = false
    @AppStorage("timestampDateStyle") private var timestampDateStyle = TimestampDateStyle.sortable.rawValue
    @AppStorage("timestampIncludeTime") private var timestampIncludeTime = true
    @AppStorage("kasterTypesetEngine") private var typesetEngine = TypesetEngine.typst.rawValue
    @AppStorage("kasterArtifactFolder.habits") private var habitsFolder = ""
    @AppStorage("kasterArtifactFolder.todos") private var todosFolder = ""
    @AppStorage("kasterArtifactFolder.debates") private var debatesFolder = ""

    private func artifactPath(_ artifact: KasterArtifact) -> String {
        switch artifact {
        case .habits: return habitsFolder
        case .todos: return todosFolder
        case .debates: return debatesFolder
        }
    }

    private func chooseFolder(for artifact: KasterArtifact) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"; panel.message = "Where should \(artifact.title) files be kept?"
        let current = artifactPath(artifact)
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch artifact {
        case .habits: habitsFolder = url.path
        case .todos: todosFolder = url.path
        case .debates: debatesFolder = url.path
        }
    }
    private var preference: WorkflowPreference { WorkflowPreference(rawValue: storedWorkflow) ?? .configured }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2.bold())
            Text("Appearance").font(.headline)
            AppearanceSettings()
            Toggle("Dot grid on cards", isOn: $dotGrid)
                .help("Show a light dot grid in the preview and on printed cards.")
            Text("Typesetting").font(.headline)
            Picker("Engine", selection: $typesetEngine) {
                ForEach(TypesetEngine.allCases) { engine in
                    Text(engine.title + (KasterTypesetter.isAvailable(engine) ? "" : " — not installed")).tag(engine.rawValue)
                }
            }
            Text(TypesetEngine.stored(typesetEngine) == .typst
                 ? "Previews and printed cards are typeset by Typst, built into Kaster. Write tables with | pipes | and math as $x^2$ or $$…$$ in LaTeX notation."
                 : "Uses your installed Pandoc and XeLaTeX (MacTeX). Slower to preview; same Markdown and $math$ syntax.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Cards").font(.headline)
            Text("Research · Zettel · Quick · Bibliography. ⌘N makes a new card of the type you used last; it saves itself into its folder once it has a title.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Artifact folders").font(.headline)
            ForEach(KasterArtifact.allCases) { artifact in
                HStack {
                    Label(artifact.title, systemImage: artifact.systemImage).frame(width: 140, alignment: .leading)
                    Text(artifactPath(artifact).isEmpty ? "Asked the first time you make one" : (artifactPath(artifact) as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Change…") { chooseFolder(for: artifact) }
                }
            }
            Spacer()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 560, height: 580)
    }
}
