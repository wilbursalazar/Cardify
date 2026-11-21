import SwiftUI
import AppKit
import PDFKit

/// A chosen source: what goes into the card and the page typed in the picker.
struct ZoteroPick { let source: ZoteroSource; let location: String }

struct ZoteroPicker: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (ZoteroPick) -> Void
    @AppStorage(ZoteroStyle.key) private var storedStyle = ""
    @State private var collections: [ZoteroCollection] = []
    @State private var collectionKey = ""
    @State private var adding = false
    @State private var query = ""
    @State private var location = ""
    @State private var items: [ZoteroItem] = []
    @State private var selection: String?
    @State private var libraries: [ZoteroLibrary] = [.personal]
    @State private var libraryID = "personal"
    @State private var fullText = false
    @State private var message = "Connecting to Zotero…"
    @State private var searching = false
    @State private var hasMore = false
    @State private var requestID = UUID()
    @State private var refreshID = UUID()
    private var currentLibrary: ZoteroLibrary { libraries.first { $0.id == libraryID } ?? .personal }
    private var searchKey: String { "\(libraryID)|\(collectionKey)|\(fullText)|\(query)|\(refreshID)" }
    private var style: String { ZoteroStyle.current(stored: storedStyle) }
    /// Collections as an indented outline (projects and their sub-collections).
    private var collectionRows: [(ZoteroCollection, Int)] {
        var rows: [(ZoteroCollection, Int)] = []
        func add(parent: String?, depth: Int) {
            for collection in collections.filter({ $0.parent == parent }).sorted(by: { $0.data.name.localizedStandardCompare($1.data.name) == .orderedAscending }) {
                rows.append((collection, depth)); add(parent: collection.key, depth: depth + 1)
            }
        }
        add(parent: nil, depth: 0)
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Zotero source").font(.title2.bold())
            HStack {
                Picker("Library", selection: $libraryID) {
                    ForEach(libraries) { library in Text(library.name).tag(library.id) }
                }.frame(maxWidth: 230)
                Picker("Collection", selection: $collectionKey) {
                    Text("All items").tag("")
                    ForEach(collectionRows, id: \.0.key) { row in
                        Text(String(repeating: "   ", count: row.1) + row.0.data.name).tag(row.0.key)
                    }
                }.frame(maxWidth: 240).help("Limit the search to one project collection")
                Spacer()
                Button("Refresh") { refreshID = UUID(); loadGroups() }
            }
            HStack {
                TextField("Search title, author, or year", text: $query)
                if !query.isEmpty { Button("Clear") { query = "" } }
            }
            Toggle("Search all fields and full text", isOn: $fullText)
            Text(message).font(.caption).foregroundStyle(.secondary)
            List(items, selection: $selection) { item in
                VStack(alignment: .leading) {
                    Text(item.title).fontWeight(.medium)
                    Text([item.authors, ZoteroItem.clean(item.data.date ?? "")].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }.tag(item.key)
            }.frame(minHeight: 200)
            if hasMore {
                HStack { Spacer(); Button("Load More") { Task { await search(append: true) } }.disabled(searching); Spacer() }
            }
            TextField("Page or location (optional), e.g. p. 42", text: $location)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(adding ? "Adding…" : "Add source") {
                    if let item = items.first(where: { $0.key == selection }) { Task { await add(item) } }
                }.disabled(selection == nil || adding).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 640, height: 520)
        .task { loadGroups(); loadCollections() }
        .onChange(of: libraryID) { _ in collectionKey = ""; loadCollections() }
        .task(id: searchKey) {
            // Invalidate earlier requests immediately, even during the debounce period.
            requestID = UUID()
            selection = nil
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            await search(append: false)
        }
    }
    private func loadCollections() {
        let library = currentLibrary
        Task { @MainActor in
            let found = await ZoteroService().collections(in: library)
            if library == currentLibrary { collections = found }
        }
    }

    /// Looks up the item's PDF so the page can open in Zotero's reader, then hands back the source.
    @MainActor private func add(_ item: ZoteroItem) async {
        adding = true
        let source = await ZoteroService().source(for: item, in: currentLibrary)
        adding = false
        onPick(ZoteroPick(source: source, location: location))
        dismiss()
    }

    private func loadGroups() {
        Task { @MainActor in libraries = await ZoteroService().libraries() }
    }
    @MainActor private func search(append: Bool) async {
        let id = UUID(); requestID = id
        let library = currentLibrary
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = append ? items.count : 0
        if !append { items = []; selection = nil; hasMore = false }
        searching = true; message = term.isEmpty ? "Loading recently modified sources…" : "Searching Zotero…"
        do {
            let found = try await ZoteroService().search(library: library, query: term, fullText: fullText, start: start, collection: collectionKey.isEmpty ? nil : collectionKey, style: style)
            guard requestID == id, !Task.isCancelled else { return }
            if append { items.append(contentsOf: found) } else { items = found }
            hasMore = found.count == 100
            searching = false
            message = items.isEmpty ? (term.isEmpty ? "No sources found in this library." : "No matches. Try fewer words or enable full-text search.") : "\(items.count) sources shown\(hasMore ? "; more available" : "")."
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            searching = false; hasMore = false
            switch error as? ZoteroService.Failure {
            case .refused(let reason): message = reason
            case .unreadable: message = "Unexpected response from Zotero."
            default: message = "Can't connect to Zotero. Open it and enable Settings → Advanced → Allow other applications on this computer to communicate with Zotero."
            }
        }
    }
}

// MARK: Sources (Zotero is the system of record; citations live in each card's footnotes)
