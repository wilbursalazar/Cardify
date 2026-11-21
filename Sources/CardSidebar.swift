import SwiftUI
import AppKit

enum SidebarSelection: Hashable {
    case all, recent, favorites, unprinted
    case theme(String)
    case tags([String])
    case folder(String)
}

enum NoteListSort: String, CaseIterable {
    case manual, modified, id, title
    var title: String {
        switch self {
        case .manual: return "Manual (drag to reorder)"
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
    @State private var listCache = DerivedCache<[LibraryCard]>()
    @State private var favoriteCache = DerivedCache<Set<String>>()
    @State private var tagsExpanded = false
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
    let onNewFolder: (String) -> Void
    let onRenameFolder: (String) -> Void
    let onNewCardIn: (String) -> Void
    let onNewFolderInFinder: (String) -> Void
    let onReorder: ([URL]) -> Void

    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    @AppStorage("kasterFavorites") private var favorites = ""
    @AppStorage("kasterRecents") private var recents = ""
    @AppStorage("kasterNoteSort") private var storedSort = NoteListSort.modified.rawValue
    @AppStorage("kasterThemes") private var themesEnabled = false
    @AppStorage("kasterLibraryWidth") private var libraryWidth = 196.0
    @AppStorage("kasterNoteListWidth") private var listWidth = 238.0
    @State private var selection: SidebarSelection = .all
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var expandedFolders: Set<String> = []
    @State private var selectedPaths: Set<String> = []

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var accent: Color { AppearancePreference.accent(for: appearance) ?? AppearancePreference.kasterPurple }
    @AppStorage(AppearancePreference.accentKey) private var accentHex = ""
    private var selectionFill: Color { AppearancePreference.selectionFill(for: appearance) }
    private var sort: NoteListSort { NoteListSort(rawValue: storedSort) ?? .modified }

    var body: some View {
        HStack(spacing: 0) {
            libraryColumn
                .frame(width: libraryWidth)
                .background(AppearancePreference.foreground(for: appearance) == nil ? Color.primary.opacity(0.035) : Color.clear)
            PaneResizeHandle(width: $libraryWidth, range: 150...340)
            noteListColumn
                .frame(width: listWidth)
                .background(AppearancePreference.foreground(for: appearance) == nil ? Color(nsColor: .textBackgroundColor) : Color.white.opacity(0.03))
            PaneResizeHandle(width: $listWidth, range: 180...460)
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
                    if themesEnabled {
                        Text("Themes").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
                        let themes = store.themes.keys.sorted()
                        if themes.isEmpty {
                            Text("Add a #tag to a card; its first tag is its theme.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
                        }
                        ForEach(themes, id: \.self) { theme in
                            navRow("#" + theme, systemImage: "tag", count: store.themes[theme]?.count ?? 0, target: .theme(theme))
                        }
                    }
                    tagsSection
                    HStack {
                        Text("Folders").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { onNewFolderInFinder(selectedFolderPath ?? "") } label: { Image(systemName: "folder.badge.plus").font(.system(size: 11)) }
                            .buttonStyle(.borderless).help("Open a Finder panel to make or pick a folder" + (selectedFolderPath.map { " inside \(($0 as NSString).lastPathComponent)" } ?? ""))
                            .disabled(folder.isEmpty)
                    }
                    .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
                    .contentShape(Rectangle())
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        // Dropping on "Folders" moves a card or folder to the top of the vault.
                        dropItems(providers, into: "")
                    }
                    .help("Drop cards or folders here to move them to the top of your notes folder")
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

    /// Every #tag with its count. Click to list a tag's cards; ⌘-click to add or remove tags,
    /// narrowing to cards that carry all of the chosen ones.
    @ViewBuilder private var tagsSection: some View {
        let tags = store.index.tags
        if !tags.isEmpty {
            HStack {
                Text("Tags").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if case .tags = selection { Button("Clear") { selection = .all }.font(.system(size: 11)).buttonStyle(.borderless) }
            }
            .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
            let chosen: [String] = { if case .tags(let names) = selection { return names } else { return [] } }()
            ForEach(tags.prefix(tagsExpanded ? tags.count : 12), id: \.name) { tag in
                let isChosen = chosen.contains { $0.caseInsensitiveCompare(tag.name) == .orderedSame }
                Button {
                    searching = false; query = ""
                    if NSEvent.modifierFlags.contains(.command) {
                        var names = chosen.filter { $0.caseInsensitiveCompare(tag.name) != .orderedSame }
                        if !isChosen { names.append(tag.name) }
                        selection = names.isEmpty ? .all : .tags(names)
                    } else {
                        selection = isChosen && chosen.count == 1 ? .all : .tags([tag.name])
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "number").foregroundStyle(isChosen ? accent : .secondary).frame(width: 18)
                        Text(tag.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text("\(tag.count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(isChosen && !searching ? selectionFill : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show cards tagged #\(tag.name). ⌘-click to combine tags.")
            }
            if tags.count > 12 {
                Button(tagsExpanded ? "Show Fewer" : "Show All \(tags.count) Tags") { tagsExpanded.toggle() }
                    .font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 10)
            }
        }
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

    private var selectedFolderPath: String? {
        if case .folder(let path) = selection { return path }
        return nil
    }

    private func dropItems(_ providers: [NSItemProvider], into path: String) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL else { return }
            DispatchQueue.main.async {
                guard !folder.isEmpty else { return }
                let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
                onMove(url, path.isEmpty ? root : root.appendingPathComponent(path, isDirectory: true))
            }
        }
        return true
    }

    private func folderURL(_ path: String) -> URL? {
        guard !folder.isEmpty else { return nil }
        return URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(path, isDirectory: true)
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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in dropItems(providers, into: row.path) }
        .onDrag { NSItemProvider(object: (folderURL(row.path) ?? URL(fileURLWithPath: "/")) as NSURL) }
        .help(row.path)
        .contextMenu {
            Button { onNewCardIn(row.path) } label: { Label("New Card Here", systemImage: "square.and.pencil") }
            Button { onNewFolder(row.path) } label: { Label("New Folder Inside", systemImage: "folder.badge.plus") }
            Button { onRenameFolder(row.path) } label: { Label("Rename Folder…", systemImage: "pencil") }
            Button { if let url = folderURL(row.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) } } label: { Label("Show in Finder", systemImage: "folder") }
            Divider()
            // Counted from the index; the sorted list is built only when the button is used.
            let count = store.index.count(inFolder: row.path)
            Button {
                let cards = store.snapshot.cards.filter { $0.path.hasPrefix(row.path + "/") }
                    .sorted { ($0.cardID ?? "~" + $0.title).localizedStandardCompare($1.cardID ?? "~" + $1.title) == .orderedAscending }
                onPrint(cards.map(\.url), "in \(row.name)")
            } label: { Label("Print All Cards in \(row.name) (\(count))", systemImage: "printer") }
                .disabled(count == 0)
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
        case .theme(let theme): return "#" + theme
        case .tags(let names): return names.map { "#" + $0 }.joined(separator: " ")
        case .folder(let path): return (path as NSString).lastPathComponent
        }
    }

    private var unprintedCards: [LibraryCard] {
        store.snapshot.cards.filter { (store.modified[$0.path] ?? .distantPast) > lastPrint }
    }

    private var recentCards: [LibraryCard] {
        KasterPathList.decode(recents).compactMap { store.index.card(for: URL(fileURLWithPath: $0)) }
    }
    private var favoriteCards: [LibraryCard] {
        let keys = Set(KasterPathList.decode(favorites).compactMap { store.index.card(for: URL(fileURLWithPath: $0))?.path })
        return store.snapshot.cards.filter { keys.contains($0.path) }
    }

    private var listedCards: [LibraryCard] {
        let key = "\(store.generation)|\(selection)|\(sort)|\(searching)|\(query)|\(recents)|\(favorites)|\(lastPrint.timeIntervalSince1970)"
        return listCache.value(for: key) { computeListedCards() }
    }

    private func computeListedCards() -> [LibraryCard] {
        let base: [LibraryCard]
        if searching {
            base = store.index.search(query)
        } else {
            switch selection {
            case .all: base = store.snapshot.cards
            case .recent: return recentCards
            case .favorites: base = favoriteCards
            case .unprinted: base = unprintedCards
            case .theme(let theme):
                let paths = Set(store.themes[theme] ?? [])
                base = store.snapshot.cards.filter { paths.contains($0.path) }
            case .tags(let names): base = store.index.cards(taggedWithAll: names)
            case .folder(let path): base = store.snapshot.cards.filter { $0.path.hasPrefix(path + "/") }
            }
        }
        switch sort {
        case .manual:
            // Manual position comes from each card's `order:` frontmatter, read once per scan.
            return store.index.sortedByOrder(base)
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
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button { onNewCardIn(selectedFolderPath ?? "") } label: { Label("New Card Here", systemImage: "square.and.pencil") }
                    Button { onNewFolder(selectedFolderPath ?? "") } label: { Label("New Folder Here", systemImage: "folder.badge.plus") }
                }
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
        case .theme: return "tag"
        case .tags: return "number"
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

    private func cardType(_ card: LibraryCard) -> KasterMode? {
        guard let first = card.path.split(separator: "/").first, card.path.contains("/") else { return nil }
        return KasterMode.allCases.first { $0.folder.caseInsensitiveCompare(String(first)) == .orderedSame }
    }

    // Rows draw while scrolling: compare cached path strings, never ask the file system.
    private var favoritePaths: Set<String> {
        favoriteCache.value(for: "\(store.generation)|\(favorites)") {
            Set(KasterPathList.decode(favorites).compactMap { store.index.card(for: URL(fileURLWithPath: $0))?.path })
        }
    }
    private var currentPath: String? { currentURL.flatMap { store.index.card(for: $0)?.path } }
    private var openPaths: Set<String> { Set(openURLs.compactMap { store.index.card(for: $0)?.path }) }
    private func isFavorite(_ card: LibraryCard) -> Bool { favoritePaths.contains(card.path) }

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
                HStack(spacing: 4) {
                    if let mode = cardType(card) { Image(systemName: mode.systemImage).font(.system(size: 9, weight: .semibold)).foregroundStyle(accent.opacity(0.8)).help(mode.title) }
                    Text(subtitle(for: card)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(current ? selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: selected ? 1.5 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // Dropping a card onto another card places it just before that card (manual order).
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let dragged = object as? URL else { return }
                DispatchQueue.main.async { reorder(dragged, before: card) }
            }
            return true
        }
        .contextMenu {
            Button { open(card) } label: { Label("Open", systemImage: "doc.text") }.disabled(current)
            Button { onNewCardIn((card.path as NSString).deletingLastPathComponent) } label: { Label("New Card Here", systemImage: "square.and.pencil") }
            Button { onNewFolder((card.path as NSString).deletingLastPathComponent) } label: { Label("New Folder Here", systemImage: "folder.badge.plus") }
            Menu {
                Button("Notes Folder (top level)") { if let root = folderURL("") { onMove(card.url, root) } }
                ForEach(store.folderPaths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { path in
                    Button(path) { if let url = folderURL(path) { onMove(card.url, url) } }
                        .disabled((card.path as NSString).deletingLastPathComponent == path)
                }
            } label: { Label("Move to", systemImage: "folder") }
            Divider()
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

    /// Moves `dragged` just before `target` in the visible list and saves the new manual order.
    private func reorder(_ dragged: URL, before target: LibraryCard) {
        let key = KasterPathList.key(dragged)
        guard key != KasterPathList.key(target.url) else { return }
        var urls = listedCards.map(\.url)
        let fromAnotherFolder = !urls.contains { KasterPathList.key($0) == key }
        if fromAnotherFolder {
            // A card from elsewhere first moves into this card's folder, then takes its place.
            onMove(dragged, target.url.deletingLastPathComponent())
            return
        }
        urls.removeAll { KasterPathList.key($0) == key }
        let index = urls.firstIndex { KasterPathList.key($0) == KasterPathList.key(target.url) } ?? urls.count
        urls.insert(dragged, at: index)
        storedSort = NoteListSort.manual.rawValue
        onReorder(urls)
    }

    private func startSearch() {
        searching = true
        DispatchQueue.main.async { searchFocused = true }
    }
    private func endSearch() { searching = false; query = ""; searchFocused = false }

    private func revealCurrentCard() {
        guard let card = store.card(for: currentURL) else { return }
        expandedFolders.formUnion(SidebarFolders.ancestors(of: card.path))
    }

    private func isCurrent(_ card: LibraryCard) -> Bool { currentPath == card.path }

    private func isOpen(_ card: LibraryCard) -> Bool { openPaths.contains(card.path) }

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
        store.watch(folder: folder)
        store.scan(folder: folder) { rootChanged in
            if rootChanged { expandedFolders = [] }
            revealCurrentCard()
            // Expand top-level folders on first load so the tree isn't empty-looking.
            if expandedFolders.isEmpty { expandedFolders = Set(store.folderPaths.filter { !$0.contains("/") }) }
        }
    }
}


/// A thin divider you can drag to resize the pane on its left. Double-click resets nothing;
/// widths are remembered between launches.
struct PaneResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var start: Double?
    var body: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
            .overlay(Color.clear.frame(width: 8).contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = start ?? width
                        if start == nil { start = width }
                        width = min(max(base + value.translation.width, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in start = nil }))
            .accessibilityLabel("Resize pane")
    }
}
