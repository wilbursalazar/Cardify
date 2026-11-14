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
    let onReveal: (URL) -> Void
    let onDuplicate: (URL) -> Void
    let onRename: (URL) -> Void
    let onTrash: (URL) -> Void
    let onCopyPath: (URL) -> Void
    let onNew: () -> Void
    let onChooseFolder: () -> Void

    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    @State private var query = ""
    @State private var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @State private var loading = false
    @State private var message = "Choose a notes folder."
    @State private var scanID = UUID()
    @State private var loadedFolder = ""
    @State private var folderPaths: [String] = []
    @State private var expandedFolders: Set<String> = []

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var matches: [LibraryCard] {
        snapshot.cards.filter { LibrarySearch.matches($0, query: query) }
    }
    private var treeRows: [SidebarFolders.Row] {
        SidebarFolders.rows(folders: folderPaths, cards: matches.map(\.path), expanded: expandedFolders, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Notes").font(.headline)
                    .foregroundColor(AppearancePreference.foreground(for: appearance))
                Spacer(minLength: 0)
                Button(action: onChooseFolder) { Image(systemName: "folder") }
                    .help("Choose Notes Folder").accessibilityLabel("Choose Notes Folder")
                Button(action: scan) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh Notes").accessibilityLabel("Refresh Notes").disabled(folder.isEmpty || loading)
            }
            .buttonStyle(.borderless)
            Button("New Card", action: onNew)
                .frame(maxWidth: .infinity, alignment: .leading)
            if currentURL == nil {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draftTitle).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(draftID.map { "Draft · \($0)" } ?? "Draft").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((AppearancePreference.accent(for: appearance) ?? Color.accentColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current unsaved draft, \(draftTitle)")
                .accessibilityAddTraits(.isSelected)
            }
            if folder.isEmpty {
                Text("Choose a notes folder to see your cards here.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Choose Notes Folder", action: onChooseFolder)
            } else {
                Label(URL(fileURLWithPath: folder, isDirectory: true).lastPathComponent, systemImage: "folder.fill")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(folder)
                TextField("Search notes", text: $query)
                    .textFieldStyle(.roundedBorder)
                if loading {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Loading notes") }
                        .font(.caption).foregroundStyle(.secondary)
                } else if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let rows = treeRows
                if !rows.isEmpty {
                    let cardsByPath = Dictionary(snapshot.cards.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(rows) { row in
                                if row.kind == .folder {
                                    folderRow(row)
                                } else if let card = cardsByPath[row.path] {
                                    noteRow(card, depth: row.depth)
                                }
                            }
                        }
                    }
                } else if !loading && message.isEmpty {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Markdown notes in this folder." : "No matching notes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .onAppear(perform: scan)
        .onChange(of: folder) { _ in scan() }
        .onChange(of: refreshToken) { _ in scan() }
        .onChange(of: currentURL) { _ in revealCurrentCard() }
        .onDisappear { scanID = UUID() }
    }

    private func folderRow(_ row: SidebarFolders.Row) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            if expandedFolders.contains(row.path) { expandedFolders.remove(row.path) }
            else { expandedFolders.insert(row.path) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: row.expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 10)
                Image(systemName: row.expanded ? "folder.fill" : "folder").foregroundStyle(.secondary)
                Text(row.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13)).padding(.horizontal, 5).padding(.vertical, 5)
            .padding(.leading, CGFloat(min(row.depth, 16)) * 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(searching)
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
            .background(isCurrent(card) ? (AppearancePreference.accent(for: appearance) ?? Color.accentColor).opacity(0.22) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { open(card) } label: { Label("Open", systemImage: "doc.text") }.disabled(isCurrent(card))
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
