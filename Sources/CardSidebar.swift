import SwiftUI
import AppKit

// A read-only view of the chosen notes folder. Opening a note goes through
// the editor's existing unsaved-draft guard; the sidebar never writes files.
struct CardSidebar: View {
    let currentURL: URL?
    let openURLs: [URL]
    let draftTitle: String
    let draftID: String?
    let notesFolder: String
    let saveFolder: String
    let refreshToken: UUID
    let onOpen: (URL) -> Bool
    let onOpenParallel: (URL) -> Void
    let onReveal: (URL) -> Void
    let onDuplicate: (URL) -> Void
    let onRename: (URL) -> Void
    let onTrash: (URL) -> Void
    let onCopyPath: (URL) -> Void
    let onMove: (URL, URL) -> Void
    let onNew: () -> Void
    let onChooseFolder: () -> Void
    let onGraph: () -> Void
    let onSettings: () -> Void

    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    @State private var query = ""
    @State private var selectedFolder: String?
    @State private var selectedSection = "Library"
    @AppStorage("kasterFavoritePaths") private var favoriteStorage = ""
    @FocusState private var searchFocused: Bool
    @State private var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @State private var loading = false
    @State private var message = "Choose a notes folder."
    @State private var scanID = UUID()
    @State private var loadedFolder = ""
    @State private var folderPaths: [String] = []
    @State private var expandedFolders: Set<String> = []

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var favorites: Set<String> { Set(favoriteStorage.split(separator: "\n").map(String.init)) }
    private var matches: [LibraryCard] {
        var results = snapshot.cards.filter { LibrarySearch.matches($0, query: query) }
        if let selectedFolder {
            results = results.filter { $0.path.hasPrefix(selectedFolder + "/") }
        }
        if selectedSection == "Favorites" {
            results = results.filter { favorites.contains($0.path) }
        } else if selectedSection == "Recent" {
            results.sort {
                let a = (try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let b = (try? $1.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return a > b
            }
            results = Array(results.prefix(50))
        }
        return results
    }
    private var folderRows: [SidebarFolders.Row] {
        SidebarFolders.rows(folders: folderPaths, cards: [], expanded: expandedFolders, query: "")
    }
    private var selectionTitle: String {
        if let selectedFolder { return (selectedFolder as NSString).lastPathComponent }
        return selectedSection == "Library" ? "All Cards" : selectedSection
    }
    private func setSection(_ name: String) {
        selectedSection = name
        selectedFolder = nil
        if name == "Search" { searchFocused = true }
    }
    private func toggleFavorite(_ path: String) {
        var next = favorites
        if next.contains(path) { next.remove(path) } else { next.insert(path) }
        favoriteStorage = next.sorted().joined(separator: "\n")
    }
    private func navigationRow(_ name: String, icon: String, count: Int? = nil) -> some View {
        let active = selectedSection == name && selectedFolder == nil
        return Button {
            if name == "Graph" { onGraph() }
            else { setSection(name) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 15)
                Text(name).lineLimit(1)
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: active ? .semibold : .regular))
            .padding(.horizontal, 7).padding(.vertical, 6)
            .background(active ? Color(red: 0.89, green: 0.83, blue: 0.96) : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }


    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 5) {
                navigationRow("Library", icon: "rectangle.stack")
                navigationRow("All Cards", icon: "square.grid.2x2", count: snapshot.cards.count)
                navigationRow("Recent", icon: "clock", count: min(50, snapshot.cards.count))
                navigationRow("Favorites", icon: "star", count: favorites.count)
                navigationRow("Graph", icon: "point.3.connected.trianglepath.dotted")
                navigationRow("Search", icon: "magnifyingglass")
                Divider().padding(.vertical, 6)
                HStack {
                    Text("FOLDERS").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onChooseFolder) { Image(systemName: "folder.badge.plus") }
                        .help("Choose Notes Folder")
                }.buttonStyle(.borderless).padding(.horizontal, 6)
                if folder.isEmpty {
                    Text("Choose your notes folder").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(folderRows) { row in
                                folderRow(row)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Button(action: onNew) { Image(systemName: "plus") }
                        .help("New Card")
                    Spacer()
                    Button(action: onSettings) { Image(systemName: "gearshape") }
                        .help("Settings")
                }
                .buttonStyle(.borderless).padding(.horizontal, 6)
            }
            .padding(9)
            .frame(minWidth: 120, idealWidth: 135, maxWidth: 185,
                   maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.955, green: 0.951, blue: 0.965))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(selectionTitle).font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(action: onNew) { Image(systemName: "plus") }
                        .help("New Card")
                    Button(action: scan) { Image(systemName: "arrow.up.arrow.down") }
                        .help("Refresh Cards")
                        .disabled(folder.isEmpty || loading)
                }
                .buttonStyle(.borderless).padding(.horizontal, 10).frame(height: 34)
                Divider()
                TextField("Search cards", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(.horizontal, 8).padding(.vertical, 7)
                if loading {
                    ProgressView().controlSize(.small).padding(8)
                } else if !message.isEmpty && snapshot.cards.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .padding(8)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if currentURL == nil {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(draftTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                Text(draftID.map { "\($0) · Draft" } ?? "Unsaved draft")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.90, green: 0.85, blue: 0.96),
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        ForEach(matches) { card in noteRow(card, depth: 0) }
                    }.padding(.horizontal, 6)
                }
                if !loading && matches.isEmpty && currentURL != nil {
                    Text("No matching cards").font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
            .frame(minWidth: 155, idealWidth: 182, maxWidth: .infinity,
                   maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 440, maxHeight: .infinity)
        .onAppear(perform: scan)
        .onChange(of: folder) { _ in selectedFolder = nil; scan() }
        .onChange(of: refreshToken) { _ in scan() }
        .onChange(of: currentURL) { _ in revealCurrentCard() }
        .onDisappear { scanID = UUID() }
    }

    private func folderRow(_ row: SidebarFolders.Row) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            selectedFolder = row.path
            selectedSection = "Folders"
            if expandedFolders.contains(row.path) { expandedFolders.remove(row.path) }
            else { expandedFolders.insert(row.path) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: row.expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 10)
                Image(systemName: row.expanded ? "folder.fill" : "folder").foregroundStyle(.secondary)
                Text(row.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11)).padding(.horizontal, 4).padding(.vertical, 5)
            .padding(.leading, CGFloat(min(row.depth, 16)) * 8)
            .background(selectedFolder == row.path ? Color(red: 0.89, green: 0.83, blue: 0.96) : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(searching)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async {
                    guard !folder.isEmpty else { return }
                    let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                    let destination = root.appendingPathComponent(row.path, isDirectory: true)
                    onMove(url, destination)
                }
            }
            return true
        }
        .help(searching ? "Clear search to collapse folders." : row.path)
        .accessibilityLabel("Folder \(row.name), \(row.expanded ? "expanded" : "collapsed")")
    }

    private func noteRow(_ card: LibraryCard, depth: Int) -> some View {
        Button { open(card) } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "doc.text").foregroundStyle(.secondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let id = card.cardID, !id.isEmpty {
                        Text(id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .padding(.leading, CGFloat(min(depth, 16)) * 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent(card) ? Color(red: 0.90, green: 0.85, blue: 0.96) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(favorites.contains(card.path) ? "Remove from Favorites" : "Add to Favorites") { toggleFavorite(card.path) }
            Divider()
            Button { open(card) } label: { Label("Open", systemImage: "doc.text") }.disabled(isCurrent(card))
            Button { perform(onOpenParallel, for: card) } label: { Label("Open Beside Current Card", systemImage: "rectangle.split.2x1") }
            Divider()
            Button { perform(onReveal, for: card) } label: { Label("Show in Finder", systemImage: "folder") }
            Button { perform(onCopyPath, for: card) } label: { Label("Copy Path", systemImage: "doc.on.doc") }
            Divider()
            Button { perform(onDuplicate, for: card) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { perform(onRename, for: card) } label: { Label("Rename File…", systemImage: "pencil") }
                .disabled(isOpen(card) && !isCurrent(card))
                .help(isOpen(card) && !isCurrent(card) ? "This file is open in another workspace." : "Change the filename, not the note heading.")
            Button(role: .destructive) { perform(onTrash, for: card) } label: { Label("Move to Trash", systemImage: "trash") }
                .disabled(isOpen(card) && !isCurrent(card))
                .help(isOpen(card) && !isCurrent(card) ? "This file is open in another workspace." : "Move this file to Trash.")
        }
        .help(card.path)
        .onDrag { NSItemProvider(object: card.url as NSURL) }
        .accessibilityLabel(card.cardID.map { "\(card.title), ID \($0)" } ?? card.title)
    }

    private func revealCurrentCard() {
        guard let currentURL, let card = snapshot.cards.first(where: { $0.url.standardizedFileURL == currentURL.standardizedFileURL }) else { return }
        expandedFolders.formUnion(SidebarFolders.ancestors(of: card.path))
    }

    private func isCurrent(_ card: LibraryCard) -> Bool {
        guard let currentURL else { return false }
        return currentURL.resolvingSymlinksInPath().standardizedFileURL == card.url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func isOpen(_ card: LibraryCard) -> Bool {
        let url = card.url.resolvingSymlinksInPath().standardizedFileURL
        return openURLs.contains { $0.resolvingSymlinksInPath().standardizedFileURL == url }
    }

    private func open(_ card: LibraryCard) {
        guard !folder.isEmpty else { return }
        if isCurrent(card) { return }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard CardGraph.canOpen(card.url, in: root) else {
            message = "This note is no longer available. Refresh and try again."
            return
        }
        _ = onOpen(card.url)
    }

    // The library is an asynchronous snapshot. Recheck its root and target
    // before dispatching any context action on a potentially stale row.
    private func perform(_ action: (URL) -> Void, for card: LibraryCard) {
        guard !folder.isEmpty else { return }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard CardGraph.canOpen(card.url, in: root) else {
            message = "This note is no longer available. Refresh and try again."
            return
        }
        action(card.url)
    }

    private func scan() {
        let id = UUID(); scanID = id
        guard !folder.isEmpty else {
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
            folderPaths = []; expandedFolders = []; loadedFolder = ""; loading = false; message = "Choose a notes folder."; return
        }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let rootChanged = root.path != loadedFolder
        if rootChanged {
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
            folderPaths = []; expandedFolders = []
        }
        loading = true; message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LibrarySnapshot.load(folder: root)
            let folders = found == nil ? [] : SidebarFolders.paths(in: root)
            DispatchQueue.main.async {
                guard scanID == id else { return }
                loading = false
                guard let found else {
                    snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
                    folderPaths = []
                    loadedFolder = ""
                    message = "Can't read this folder. Choose it again."
                    return
                }
                let currentWasKnown = currentURL.map { url in
                    snapshot.cards.contains { $0.url.standardizedFileURL == url.standardizedFileURL }
                } ?? false
                snapshot = found; folderPaths = folders; loadedFolder = root.path
                if rootChanged || !currentWasKnown { revealCurrentCard() }
                message = found.unreadable > 0 ? "Some notes could not be read." : ""
            }
        }
    }
}
