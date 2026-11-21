import SwiftUI
import AppKit

struct CardLibrary: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("saveFolder") private var saveFolder = ""
    let currentURL: URL?
    let allowInsert: Bool
    let onOpen: (URL) -> Void
    let onInsert: (String) -> Void
    @State private var query = ""
    @State private var explanation = ""
    @State private var selected: String?
    @State private var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @State private var message = "Choose a notes folder to get started."
    @State private var scanID = UUID()
    @State private var tab = "cards"

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var matches: [LibraryCard] {
        snapshot.cards.filter { LibrarySearch.matches($0, query: query) }
    }
    private var current: LibraryCard? { snapshot.cards.first { $0.path == selected } }
    private func card(_ path: String) -> LibraryCard? { snapshot.cards.first { $0.path == path } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Library").font(.title2.bold())
                Spacer()
                Button("Choose Folder…", action: chooseFolder)
                Button("Refresh", action: scan).disabled(folder.isEmpty)
            }
            Text(folder.isEmpty ? "No notes folder selected" : folder).font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Picker("Library view", selection: $tab) { Text("Cards").tag("cards"); Text("Index").tag("index") }.pickerStyle(.segmented).frame(width: 190)
            if tab == "index" {
                CuratedIndexView(cards: snapshot.cards, onOpen: { url in
                    if let note = snapshot.cards.first(where: { $0.url == url }) { query = ""; selected = note.path; tab = "cards" }
                }, onRefresh: scan)
            } else {
                TextField("Search titles, IDs, filenames, or note text", text: $query)
                Text(message).font(.caption).foregroundStyle(.secondary)
                HSplitView {
                    List(matches, selection: $selected) { note in
                        VStack(alignment: .leading) {
                            Text(note.title).fontWeight(.medium).lineLimit(1)
                            Text([note.cardID, note.path].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.tag(note.path)
                    }.frame(minWidth: 220)
                    ScrollView {
                        if let note = current {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(note.title).font(.headline)
                                Text(note.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let id = note.cardID { Text("ID: \(id)").font(.caption) }
                                HStack {
                                    Button("Open Card") { onOpen(note.url); dismiss() }
                                    Button("Insert Link") {
                                        let context = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                                        onInsert(CardifyNote(path: note.path).wikiLink(among: snapshot.cards.map(\.path)) + (context.isEmpty ? "" : " — " + context)); dismiss()
                                    }.disabled(!note.canLink || !allowInsert)
                                }
                                if allowInsert {
                                    TextField("Why is this card related? (optional)", text: $explanation)
                                } else {
                                    Text("Switch to Research to insert a link into a draft.").font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                                connectionSection("Links to", paths: snapshot.outgoing[note.path] ?? [])
                                connectionSection("Linked from", paths: snapshot.incoming[note.path] ?? [])
                                let sequence = LibrarySequence.hints(for: note, in: snapshot.cards)
                                if !sequence.isEmpty {
                                    Text("Nearby IDs").font(.subheadline.bold())
                                    Text("Inferred from addresses; not necessarily an intentional relationship.").font(.caption).foregroundStyle(.secondary)
                                    ForEach(Array(sequence.enumerated()), id: \.offset) { _, item in
                                        Button("\(item.0): \(item.1.cardID ?? "") · \(item.1.title)") { query = ""; selected = item.1.path }.buttonStyle(.link)
                                    }
                                }
                                Divider()
                                Text("Note text").font(.subheadline.bold())
                                Text(CardMetadata.parse(note.content).body).font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        } else {
                            Text("Select a card to see its connections.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
                        }
                    }.frame(minWidth: 300)
                }
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(22).frame(minWidth: 760, minHeight: 520)
        .onAppear { if !folder.isEmpty { scan() } }
        .onChange(of: selected) { _ in explanation = "" }
    }
    @ViewBuilder private func connectionSection(_ title: String, paths: [String]) -> some View {
        Text("\(title) (\(paths.count))").font(.subheadline.bold())
        if paths.isEmpty { Text("None found").font(.caption).foregroundStyle(.secondary) }
        ForEach(paths, id: \.self) { path in
            if let target = card(path) {
                Button(target.title) { query = ""; selected = target.path }.buttonStyle(.link)
            }
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            notesFolder = url.path; selected = nil
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
            scan()
        }
    }
    private func scan() {
        guard !folder.isEmpty else { message = "Choose a notes folder to get started."; return }
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let id = UUID(); scanID = id; message = "Searching for cards…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = LibrarySnapshot.load(folder: url)
            DispatchQueue.main.async {
                guard id == scanID else { return }
                guard let result else {
                    snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0); selected = nil
                    message = "Could not read the notes folder. Choose it again."; return
                }
                snapshot = result
                if let selected, !result.cards.contains(where: { $0.path == selected }) { self.selected = nil }
                if self.selected == nil, let currentURL, let card = result.cards.first(where: { $0.url.standardizedFileURL == currentURL.standardizedFileURL }) { self.selected = card.path }
                message = "\(result.cards.count) Markdown cards" + (result.unreadable > 0 ? "; \(result.unreadable) could not be read." : ".")
            }
        }
    }
}
