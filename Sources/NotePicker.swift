import SwiftUI
import AppKit

struct CardifyNote: Identifiable, Hashable {
    let path: String
    var id: String { path }
    var title: String { URL(fileURLWithPath: path).lastPathComponent }
    // Obsidian treats these characters as link syntax rather than filename characters.
    var canLink: Bool { !path.contains("%%") && !path.contains(where: { "[]|#^:\n\r".contains($0) }) }
    var wikiLink: String { "[[\(path)]]" }
}

enum CardifyNoteIndex {
    static func scan(folder: URL) -> [CardifyNote]? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        let rootPath = folder.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var notes: [CardifyNote] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isHidden == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            let fullPath = url.standardizedFileURL.path
            guard fullPath.hasPrefix(prefix) else { continue }
            let relative = String(fullPath.dropFirst(prefix.count))
            let path = String(relative.dropLast(url.pathExtension.count + 1))
            notes.append(CardifyNote(path: path))
        }
        return notes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

struct NotePicker: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notesFolder") private var notesFolder = ""
    let onInsert: (String) -> Void
    @State private var query = ""
    @State private var selected: String?
    @State private var explanation = ""
    @State private var notes: [CardifyNote] = []
    @State private var message = "Choose your Obsidian vault or notes folder."
    @State private var scanID = UUID()
    private var matchingNotes: [CardifyNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? notes : notes.filter { $0.path.localizedStandardContains(trimmed) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link a note").font(.title2.bold())
            HStack {
                Text(notesFolder.isEmpty ? "No folder selected" : notesFolder)
                    .font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                Button("Choose Folder…", action: chooseFolder)
                Button("Refresh", action: scan).disabled(notesFolder.isEmpty)
            }
            TextField("Search note titles and paths", text: $query)
            Text(message).font(.caption).foregroundStyle(.secondary)
            List(matchingNotes, selection: $selected) { note in
                VStack(alignment: .leading) {
                    Text(note.title).fontWeight(.medium)
                    Text(note.path).font(.caption).foregroundStyle(.secondary)
                    if !note.canLink { Text("This filename contains characters that cannot form a wiki link.").font(.caption).foregroundStyle(.secondary) }
                }.tag(note.path)
            }.frame(minHeight: 200)
            TextField("Connection (optional)", text: $explanation)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Insert Link") {
                    if let note = notes.first(where: { $0.path == selected && $0.canLink }) {
                        let context = explanation.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        onInsert(note.wikiLink + (context.isEmpty ? "" : " — " + context))
                        dismiss()
                    }
                }.disabled(!notes.contains { $0.path == selected && $0.canLink }).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 560, height: 430)
        .onAppear { if !notesFolder.isEmpty { scan() } }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            notesFolder = url.path
            scan()
        }
    }
    private func scan() {
        let folder = URL(fileURLWithPath: notesFolder, isDirectory: true)
        let id = UUID(); scanID = id; selected = nil; notes = []; message = "Searching for notes…"
        DispatchQueue.global(qos: .userInitiated).async {
            let found = CardifyNoteIndex.scan(folder: folder)
            DispatchQueue.main.async {
                guard id == scanID else { return }
                guard let found else { message = "Could not open this folder. Choose it again."; return }
                notes = found
                message = found.isEmpty ? "No Markdown notes found in this folder." : "\(found.count) Markdown notes. Select one to insert a link."
            }
        }
    }
}
