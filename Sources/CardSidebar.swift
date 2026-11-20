import SwiftUI
import AppKit

enum SidebarSelection: Hashable {
    case all, recent, favorites, unprinted
    case folder(String)
}

enum NoteListSort: String, CaseIterable {
    case modified, id, title
    var title: String {
        switch self {
        case .modified: return "Date Modified"
        case .id: return "Card ID"
        case .title: return "Title"
        }
    }
}

// Kaster's two left columns: the Library (smart lists and folders) and the
// note list for the current selection. The sidebar never writes files itself;
// every change goes through the editor's guarded handlers.
struct CardSidebar: View {
    @ObservedObject var store: LibraryStore
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
    let onPrint: ([URL], String) -> Void
    let lastPrint: Date

    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    @AppStorage("kasterFavorites") private var favorites = ""
    @AppStorage("kasterRecents") private var recents = ""
    @AppStorage("kasterNoteSort") private var storedSort = NoteListSort.modified.rawValue
    @State private var selection: SidebarSelection = .all
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var expandedFolders: Set<String> = []
    @State private var selectedPaths: Set<String> = []

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var accent: Color { AppearancePreference.accent(for: appearance) ?? AppearancePreference.kasterPurple }
    private var selectionFill: Color {
        AppearancePreference.foreground(for: appearance) == nil ? AppearancePreference.kasterSelection : accent.opacity(0.22)
    }
    private var sort: NoteListSort { NoteListSort(rawValue: storedSort) ?? .modified }

    var body: some View {
        HStack(spacing: 0) {
            libraryColumn
                .frame(width: 196)
                .background(AppearancePreference.foreground(for: appearance) == nil ? Color.primary.opacity(0.035) : Color.clear)
            Divider()
            noteListColumn
                .frame(width: 238)
                .background(AppearancePreference.foreground(for: appearance) == nil ? Color(nsColor: .textBackgroundColor) : Color.white.opacity(0.03))
        }
        .frame(maxHeight: .infinity)
        .onAppear(perform: scan)
        .onChange(of: folder) { _ in selection = .all; selectedPaths = []; scan() }
        .onChange(of: selection) { _ in selectedPaths = [] }
        .onChange(of: refreshToken) { _ in scan() }
        .onChange(of: currentURL) { url in
            revealCurrentCard()
            if let url, store.card(for: url) != nil { recents = KasterPathList.pushRecent(url, into: recents) }
        }
        .onDisappear { store.cancel() }
    }

    // MARK: Library column

    private var libraryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    sectionHeader("Library", systemImage: "books.vertical.fill", highlighted: true)
                    navRow("All Cards", systemImage: "square.stack", count: store.snapshot.cards.count, target: .all)
                    navRow("Recent", systemImage: "clock", count: recentCards.count, target: .recent)
                    navRow("Favorites", systemImage: "star", count: favoriteCards.count, target: .favorites)
                    navRow("Unprinted", systemImage: "printer", count: unprintedCards.count, target: .unprinted)
                        .help("Cards created or changed since your last print — keep the paper box in step")
                    actionRow("Graph", systemImage: "point.3.connected.trianglepath.dotted", action: onGraph)
                    actionRow("Search", systemImage: "magnifyingglass", shortcut: "⌘F") { startSearch() }
                        .keyboardShortcut("f", modifiers: .command)
                    HStack {
                        Text("Folders").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button(action: onChooseFolder) { Image(systemName: "folder.badge.plus").font(.system(size: 11)) }
                            .buttonStyle(.borderless).help("Choose Notes Folder")
                    }
                    .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
                    if folder.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose a folder of Markdown notes, such as an Obsidian vault.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Choose Notes Folder", action: onChooseFolder)
                        }.padding(.horizontal, 10)
                    } else {
                        ForEach(folderRows) { row in folderRow(row) }
                    }
                }
                .padding(.horizontal, 8).padding(.top, 10)
            }
            Divider()
            HStack(spacing: 14) {
                Button(action: onNew) { Image(systemName: "plus") }.help("New Card")
                Spacer()
                Button(action: scan) { Image(systemName: "arrow.clockwise") }.help("Refresh Notes").disabled(folder.isEmpty || store.loading)
                Button(action: onSettings) { Image(systemName: "gearshape") }.help("Settings")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String, highlighted: Bool) -> some View {
        Button { selection = .all } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(accent).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(highlighted ? selectionFill : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.bottom, 4)
    }

    private func navRow(_ title: String, systemImage: String, count: Int, target: SidebarSelection) -> some View {
        Button { selection = target; searching = false; query = "" } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
                Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selection == target && !searching ? selectionFill : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ title: String, systemImage: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 11)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(title == "Search" && searching ? selectionFill : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var folderRows: [SidebarFolders.Row] {
        SidebarFolders.rows(folders: store.folderPaths, cards: [], expanded: expandedFolders, query: "")
    }

    private func hasSubfolders(_ path: String) -> Bool {
        store.folderPaths.contains { ($0 as NSString).deletingLastPathComponent == path }
    }

    private func folderRow(_ row: SidebarFolders.Row) -> some View {
        let selected = selection == .folder(row.path) && !searching
        return HStack(spacing: 4) {
            Button {
                if expandedFolders.contains(row.path) { expandedFolders.remove(row.path) } else { expandedFolders.insert(row.path) }
            } label: {
                Image(systemName: row.expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 12, height: 16).contentShape(Rectangle())
                    .opacity(hasSubfolders(row.path) ? 1 : 0)
            }
            .buttonStyle(.plain).disabled(!hasSubfolders(row.path))
            Button { selection = .folder(row.path); searching = false; query = "" } label: {
                HStack(spacing: 6) {
                    Image(systemName: selected ? "folder.fill" : "folder").foregroundStyle(selected ? accent : .secondary)
                    Text(row.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .padding(.leading, CGFloat(min(row.depth, 12)) * 12)
        .background(selected ? selectionFill : .clear, in: RoundedRectangle(cornerRadius: 7))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async {
                    guard !folder.isEmpty else { return }
                    let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                    onMove(url, root.appendingPathComponent(row.path, isDirectory: true))
                }
            }
            return true
        }
        .help(row.path)
        .contextMenu {
            let cards = store.snapshot.cards.filter { $0.path.hasPrefix(row.path + "/") }
                .sorted { ($0.cardID ?? "~" + $0.title).localizedStandardCompare($1.cardID ?? "~" + $1.title) == .orderedAscending }
            Button { onPrint(cards.map(\.url), "in \(row.name)") } label: { Label("Print All Cards in \(row.name) (\(cards.count))", systemImage: "printer") }
                .disabled(cards.isEmpty)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Folder \(row.name)")
    }

    // MARK: Note list column

    private var listTitle: String {
        if searching { return "Search" }
        switch selection {
        case .all: return "All Cards"
        case .recent: return "Recent"
        case .favorites: return "Favorites"
        case .unprinted: return "Unprinted"
        case .folder(let path): return (path as NSString).lastPathComponent
        }
    }

    private var unprintedCards: [LibraryCard] {
        store.snapshot.cards.filter { (store.modified[$0.path] ?? .distantPast) > lastPrint }
    }

    private var recentCards: [LibraryCard] {
        let byKey = Dictionary(store.snapshot.cards.map { (KasterPathList.key($0.url), $0) }, uniquingKeysWith: { first, _ in first })
        return KasterPathList.decode(recents).compactMap { byKey[$0] }
    }
    private var favoriteCards: [LibraryCard] {
        let keys = Set(KasterPathList.decode(favorites))
        return store.snapshot.cards.filter { keys.contains(KasterPathList.key($0.url)) }
    }

    private var listedCards: [LibraryCard] {
        let base: [LibraryCard]
        if searching {
            base = store.snapshot.cards.filter { LibrarySearch.matches($0, query: query) }
        } else {
            switch selection {
            case .all: base = store.snapshot.cards
            case .recent: return recentCards
            case .favorites: base = favoriteCards
            case .unprinted: base = unprintedCards
            case .folder(let path): base = store.snapshot.cards.filter { $0.path.hasPrefix(path + "/") }
            }
        }
        switch sort {
        case .modified:
            return base.sorted { (store.modified[$0.path] ?? .distantPast) > (store.modified[$1.path] ?? .distantPast) }
        case .id:
            return base.sorted { ($0.cardID ?? "~" + $0.title).localizedStandardCompare($1.cardID ?? "~" + $1.title) == .orderedAscending }
        case .title:
            return base.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private var noteListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: searching ? "magnifyingglass" : selectionIcon).foregroundStyle(.secondary)
                Text(listTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    .foregroundColor(AppearancePreference.foreground(for: appearance))
                Spacer(minLength: 0)
                Button(action: onNew) { Image(systemName: "plus") }.help("New Card")
                Button { onPrint(listedCards.map(\.url), "from \(listTitle)") } label: { Image(systemName: "printer") }
                    .help("Print every card in this list").disabled(listedCards.isEmpty)
                Menu {
                    Picker("Sort By", selection: $storedSort) {
                        ForEach(NoteListSort.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.inline)
                } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Sort cards")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 10)
            if searching {
                HStack(spacing: 6) {
                    TextField("Search titles, IDs, and text", text: $query)
                        .textFieldStyle(.roundedBorder).focused($searchFocused)
                        .onExitCommand { endSearch() }
                    Button { endSearch() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("End search")
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
            Divider()
            if store.loading && store.snapshot.cards.isEmpty {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Loading notes") }
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }
            if !store.message.isEmpty && !folder.isEmpty {
                Text(store.message).font(.caption).foregroundStyle(.secondary).padding(12)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if currentURL == nil { draftRow }
                    let cards = listedCards
                    ForEach(cards) { card in noteRow(card) }
                    if cards.isEmpty && !store.loading && !folder.isEmpty {
                        Text(emptyMessage).font(.caption).foregroundStyle(.secondary).padding(10)
                    }
                }
                .padding(6)
            }
            if !selectedPaths.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Text("\(selectedPaths.count) selected").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { onPrint(selectedCards.map(\.url), "selected") } label: { Label("Print", systemImage: "printer") }
                        .controlSize(.small)
                    Button { selectedPaths = [] } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear selection")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    // Selected cards print in the order they appear in the list.
    private var selectedCards: [LibraryCard] { listedCards.filter { selectedPaths.contains($0.path) } }

    private var selectionIcon: String {
        switch selection {
        case .all: return "square.stack"
        case .recent: return "clock"
        case .favorites: return "star"
        case .unprinted: return "printer"
        case .folder: return "folder"
        }
    }

    private var emptyMessage: String {
        if searching { return query.trimmingCharacters(in: .whitespaces).isEmpty ? "Type to search every card." : "No matching cards." }
        switch selection {
        case .favorites: return "Right-click a card and choose Add to Favorites."
        case .recent: return "Cards you open appear here."
        case .unprinted: return "Every card has been printed since it last changed."
        default: return "No Markdown cards here yet."
        }
    }

    private var draftRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(draftTitle).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Text(draftID.map { "\($0) · Draft" } ?? "Unsaved draft").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current unsaved draft, \(draftTitle)")
        .accessibilityAddTraits(.isSelected)
    }

    private func subtitle(for card: LibraryCard) -> String {
        let date = KasterDates.relative(store.modified[card.path])
        let id = card.cardID ?? ""
        if id.isEmpty { return date }
        return date.isEmpty ? id : "\(id) · \(date)"
    }

    private func isFavorite(_ card: LibraryCard) -> Bool { KasterPathList.decode(favorites).contains(KasterPathList.key(card.url)) }

    private func noteRow(_ card: LibraryCard) -> some View {
        let current = isCurrent(card)
        let selected = selectedPaths.contains(card.path)
        return Button {
            // ⌘-click builds a selection for batch printing; a plain click opens the card.
            if NSEvent.modifierFlags.contains(.command) {
                if selected { selectedPaths.remove(card.path) } else { selectedPaths.insert(card.path) }
            } else {
                selectedPaths = []
                open(card)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(card.title).font(.system(size: 13, weight: current ? .semibold : .medium)).lineLimit(2)
                    if isFavorite(card) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(accent) }
                }
                Text(subtitle(for: card)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(current ? selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: selected ? 1.5 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { open(card) } label: { Label("Open", systemImage: "doc.text") }.disabled(current)
            Button { perform(onOpenParallel, for: card) } label: { Label("Open Beside Current Card", systemImage: "rectangle.split.2x1") }
            Divider()
            Button { onPrint([card.url], "") } label: { Label("Print Card", systemImage: "printer") }
            if card.cardID != nil {
                let branch = KasterSequence.branch(of: card, in: store.snapshot.cards)
                Button { onPrint(branch.map(\.url), "in the \(card.cardID ?? "") branch") } label: {
                    Label("Print Card and Its Branch (\(branch.count))", systemImage: "arrow.triangle.branch")
                }
            }
            if selectedPaths.count > 1 && selected {
                Button { onPrint(selectedCards.map(\.url), "selected") } label: { Label("Print \(selectedPaths.count) Selected Cards", systemImage: "printer.dotmatrix") }
            }
            Divider()
            Button { favorites = KasterPathList.toggle(card.url, in: favorites) } label: {
                Label(isFavorite(card) ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite(card) ? "star.slash" : "star")
            }
            Divider()
            Button { perform(onReveal, for: card) } label: { Label("Show in Finder", systemImage: "folder") }
            Button { perform(onCopyPath, for: card) } label: { Label("Copy Path", systemImage: "doc.on.doc") }
            Divider()
            Button { perform(onDuplicate, for: card) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { perform(onRename, for: card) } label: { Label("Rename File…", systemImage: "pencil") }
                .disabled(isOpen(card) && !current)
                .help(isOpen(card) && !current ? "This file is open in another workspace." : "Change the filename, not the note heading.")
            Button(role: .destructive) { perform(onTrash, for: card) } label: { Label("Move to Trash", systemImage: "trash") }
                .disabled(isOpen(card) && !current)
                .help(isOpen(card) && !current ? "This file is open in another workspace." : "Move this file to Trash.")
        }
        .help(card.path)
        .onDrag { NSItemProvider(object: card.url as NSURL) }
        .accessibilityLabel(card.cardID.map { "\(card.title), ID \($0)" } ?? card.title)
    }

    // MARK: Actions

    private func startSearch() {
        searching = true
        DispatchQueue.main.async { searchFocused = true }
    }
    private func endSearch() { searching = false; query = ""; searchFocused = false }

    private func revealCurrentCard() {
        guard let card = store.card(for: currentURL) else { return }
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
        guard !folder.isEmpty, !isCurrent(card) else { return }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard CardGraph.canOpen(card.url, in: root) else {
            store.message = "This note is no longer available. Refresh and try again."
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
            store.message = "This note is no longer available. Refresh and try again."
            return
        }
        action(card.url)
    }

    private func scan() {
        store.scan(folder: folder) { rootChanged in
            if rootChanged { expandedFolders = [] }
            revealCurrentCard()
            // Expand top-level folders on first load so the tree isn't empty-looking.
            if expandedFolders.isEmpty { expandedFolders = Set(store.folderPaths.filter { !$0.contains("/") }) }
        }
    }
}
