import SwiftUI
import AppKit

struct WorkflowSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("newCardWorkflow") private var storedWorkflow = WorkflowPreference.configured.rawValue
    @AppStorage("dotGrid") private var dotGrid = false
    @AppStorage(EditorTextScale.key) private var editorScale = 1.0
    @AppStorage(ZoteroStyle.key) private var zoteroStyle = ""
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
                Picker("Editor text size", selection: $editorScale) {
                    ForEach(EditorTextScale.steps, id: \.self) { step in Text(EditorTextScale.label(step)).tag(step) }
                }
                .help("Makes the writing area easier to read on a large screen. Printed cards keep their own text size.")
                Text("Shortcuts: ⌘+ bigger, ⌘− smaller, ⌘0 normal. Printed cards are not affected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Zotero") {
                let styles = ZoteroStyle.installed()
                Picker("Citation style", selection: Binding(get: { ZoteroStyle.current(stored: zoteroStyle, installed: styles) }, set: { zoteroStyle = $0 })) {
                    ForEach(styles) { style in Text(style.title).tag(style.id) }
                    if styles.isEmpty { Text("Chicago Manual of Style (notes)").tag("chicago-notes-bibliography") }
                }
                Text("Research cards cite Zotero sources inline in this style, from the styles installed in Zotero. Changing it applies to sources you add from now on.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            } header: { Text("Workspaces") }
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
