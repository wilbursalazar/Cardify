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
    @AppStorage("kasterThemes") private var themesEnabled = false
    @AppStorage("kasterArtifactFolder.habits") private var habitsFolder = ""
    @AppStorage("kasterArtifactFolder.todos") private var todosFolder = ""
    @AppStorage("kasterArtifactFolder.debates") private var debatesFolder = ""

    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("saveFolder") private var saveFolder = ""

    private func artifactBinding(_ artifact: KasterArtifact) -> Binding<String> {
        switch artifact {
        case .habits: return $habitsFolder
        case .todos: return $todosFolder
        case .debates: return $debatesFolder
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabView {
                general.tabItem { Label("General", systemImage: "gearshape") }
                cards.tabItem { Label("Cards", systemImage: "rectangle.stack") }
                folders.tabItem { Label("Folders", systemImage: "folder") }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 600, height: 520)
    }

    // MARK: Tabs

    private var general: some View {
        Form {
            Section("Appearance") {
                AppearanceSettings()
                AccentColorSetting()
                Toggle("Dot grid on cards", isOn: $dotGrid)
                    .help("Show a light dot grid in the preview and on printed cards.")
            }
            Section("Typesetting") {
                Picker("Engine", selection: $typesetEngine) {
                    ForEach(TypesetEngine.allCases) { engine in
                        Text(engine.title + (KasterTypesetter.isAvailable(engine) ? "" : " — not installed")).tag(engine.rawValue)
                    }
                }
                Text(TypesetEngine.stored(typesetEngine) == .typst
                     ? "Previews and printed cards are typeset by Typst, built into Kaster. Write tables with | pipes | and math as $x^2$ or $$…$$."
                     : "Uses your installed Pandoc and XeLaTeX (MacTeX). Slower to preview; same Markdown and $math$ syntax.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var cards: some View {
        Form {
            Section("Card types") {
                Text("Research · Zettel · Quick · Bibliography. ⌘N makes a new card of the type you used last; it saves itself into its folder once it has a title.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Themes") {
                Toggle("Themes", isOn: $themesEnabled)
                Text("Each card's first #tag becomes its theme: printed in the card's top-left corner, with a Themes list in the sidebar to gather, reorder and print a theme's cards.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var folders: some View {
        Form {
            Section {
                folderRow("Notes folder", systemImage: "books.vertical", path: $notesFolder,
                          empty: "Not set — ~/Documents/Kaster is used",
                          help: "Your slip box: Kaster reads and organizes cards here (Research, Zettel, Quick, Bibliography).", clearable: false)
                folderRow("Default save folder", systemImage: "square.and.arrow.down", path: $saveFolder,
                          empty: "Same as the notes folder",
                          help: "Offered when you export a PDF or use Save As.", clearable: true)
            } header: { Text("Slip box") }
            Section {
                ForEach(KasterArtifact.allCases) { artifact in
                    folderRow(artifact.title, systemImage: artifact.systemImage, path: artifactBinding(artifact),
                              empty: "Asked the first time you make one",
                              help: "Where \(artifact.title) files are kept.", clearable: true)
                }
            } header: { Text("Artifacts") }
        }
        .formStyle(.grouped)
    }

    private func folderRow(_ title: String, systemImage: String, path: Binding<String>, empty: String, help: String, clearable: Bool) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage).frame(width: 170, alignment: .leading)
            Text(path.wrappedValue.isEmpty ? empty : (path.wrappedValue as NSString).abbreviatingWithTildeInPath)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path.wrappedValue.isEmpty ? help : path.wrappedValue)
            if !path.wrappedValue.isEmpty {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.wrappedValue, isDirectory: true)]) } label: { Image(systemName: "arrow.right.circle") }
                    .buttonStyle(.borderless).help("Show in Finder")
                if clearable {
                    Button { path.wrappedValue = "" } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).help("Clear")
                }
            }
            Button("Choose…") { choose(title, path: path) }
        }
        .help(help)
    }

    private func choose(_ title: String, path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"; panel.message = "Choose the \(title.lowercased())."
        if !path.wrappedValue.isEmpty { panel.directoryURL = URL(fileURLWithPath: path.wrappedValue, isDirectory: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path.wrappedValue = url.path
    }
}
