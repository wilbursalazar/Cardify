import Foundation
import AppKit
import CoreServices
import Combine

// One read-only scan of the notes folder, shared by the sidebar, the note list,
// and the inspector's backlinks. Scanning never writes files.
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @Published private(set) var folderPaths: [String] = []
    @Published private(set) var modified: [String: Date] = [:]
    @Published private(set) var created: [String: Date] = [:]
    /// Holiday–Greene themes: each card's first #tag → the card paths carrying it.
    @Published private(set) var themes: [String: [String]] = [:]
    @Published private(set) var loading = false
    @Published var message = "Choose a notes folder."
    @Published private(set) var loadedFolder = ""
    /// Lookups (card by path, backlinks, order, type) built off the main thread with each snapshot.
    @Published private(set) var index = LibraryIndex.empty
    /// Bumped whenever the cards or their dates change, so views can cache what they derive.
    @Published private(set) var generation = 0
    private var scanID = UUID()
    // Scans and incremental refreshes run in order on one queue, each building on the last result.
    private let queue = DispatchQueue(label: "kaster.library", qos: .userInitiated)
    private var queueSnapshot: (root: URL, snapshot: LibrarySnapshot)?

    func cancel() { scanID = UUID() }

    // MARK: Watching the folder
    /// Markdown files changed outside Kaster (Finder, Obsidian…), delivered after a short pause.
    @Published private(set) var externalChange: (id: UUID, files: [URL])?
    private var stream: FSEventStreamRef?
    private var watchedFolder = ""
    private var pendingFiles: Set<URL> = []
    private var pendingStructure = false
    private var flushWork: DispatchWorkItem?
    // FSEvents calls back on this queue with a pointer to `watchTarget`, which refers to the store
    // only weakly; stopping drains the queue, so no callback can outlive a closed window's store.
    private let watchQueue = DispatchQueue(label: "kaster.library.watch", qos: .utility)
    private var watchTarget: WatchTarget?
    private final class WatchTarget {
        weak var store: LibraryStore?
        init(_ store: LibraryStore) { self.store = store }
    }

    deinit { stopWatching() }

    /// Starts (or moves) the folder watch. Kaster's own writes come back as events too; refreshing
    /// them again is harmless because a refresh only re-reads what changed.
    func watch(folder: String) {
        guard folder != watchedFolder else { return }
        stopWatching()
        watchedFolder = folder
        guard !folder.isEmpty else { return }
        let target = WatchTarget(self)
        watchTarget = target
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(target).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info, let store = Unmanaged<WatchTarget>.fromOpaque(info).takeUnretainedValue().store else { return }
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let flagList = Array(UnsafeBufferPointer(start: flags, count: count))
            DispatchQueue.main.async { [weak store] in store?.received(paths: list, flags: flagList) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let created = FSEventStreamCreate(nil, callback, &context, [folder] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, watchQueue)
        FSEventStreamStart(created)
    }

    func stopWatching() {
        if let stream {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream)
            watchQueue.sync {}   // let a callback already in progress finish before its target goes away
            FSEventStreamRelease(stream)
        }
        stream = nil; watchTarget = nil; watchedFolder = ""
        flushWork?.cancel(); flushWork = nil
    }

    private func received(paths: [String], flags: [FSEventStreamEventFlags]) {
        for (path, flag) in zip(paths, flags) {
            let isDirectory = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            let hidden = path.split(separator: "/").contains { $0.hasPrefix(".") }
            if hidden { continue }
            if isDirectory {
                if flag & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed) != 0 { pendingStructure = true }
            } else if path.lowercased().hasSuffix(".md") {
                pendingFiles.insert(URL(fileURLWithPath: path))
            }
            if flag & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 { pendingStructure = true }
        }
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushChanges() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func flushChanges() {
        let folder = watchedFolder, files = Array(pendingFiles), structure = pendingStructure
        pendingFiles = []; pendingStructure = false
        guard !folder.isEmpty else { return }
        if structure { scan(folder: folder) } else if !files.isEmpty { refresh(files: files, folder: folder) }
        if !files.isEmpty { externalChange = (UUID(), files) }
    }

    private static func extras(for cards: [LibraryCard]) -> (modified: [String: Date], created: [String: Date], themes: [String: [String]]) {
        var modified: [String: Date] = [:], created: [String: Date] = [:], themes: [String: [String]] = [:]
        for card in cards {
            if let theme = KasterTypesetter.firstTag(in: card.content) { themes[theme.lowercased(), default: []].append(card.path) }
            let values = try? card.url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            modified[card.path] = values?.contentModificationDate
            created[card.path] = values?.creationDate
        }
        return (modified, created, themes)
    }

    /// Updates the library for files Kaster just wrote, moved or deleted, without rescanning
    /// the folder. Falls back to a full scan if no scan has finished yet.
    func refresh(files: [URL], folder: String) {
        guard !folder.isEmpty, !files.isEmpty else { return }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard root.path == loadedFolder else { scan(folder: folder); return }
        let id = scanID
        queue.async {
            guard let base = self.queueSnapshot, base.root == root else {
                DispatchQueue.main.async { if self.scanID == id { self.scan(folder: folder) } }
                return
            }
            let updated = base.snapshot.updating(files, root: root)
            self.queueSnapshot = (root, updated)
            let index = LibraryIndex(snapshot: updated, root: root)
            // Dates and themes change only for the touched cards; refresh just those.
            let touchedPaths = Set(files.compactMap { file -> String? in
                updated.cards.first(where: { $0.url.standardizedFileURL.path == file.standardizedFileURL.path })?.path
            })
            let touched = updated.cards.filter { touchedPaths.contains($0.path) }
            let partial = Self.extras(for: touched)
            let livePaths = Set(updated.cards.map(\.path))
            DispatchQueue.main.async {
                guard self.scanID == id, self.loadedFolder == root.path else { return }
                var modified = self.modified.filter { livePaths.contains($0.key) }, created = self.created.filter { livePaths.contains($0.key) }
                for (path, date) in partial.modified { modified[path] = date }
                for (path, date) in partial.created { created[path] = date }
                var themes = self.themes.mapValues { $0.filter { livePaths.contains($0) && !touchedPaths.contains($0) } }.filter { !$0.value.isEmpty }
                for (theme, paths) in partial.themes { themes[theme, default: []].append(contentsOf: paths) }
                self.snapshot = updated; self.index = index; self.generation += 1
                self.modified = modified; self.created = created; self.themes = themes
                self.message = updated.unreadable > 0 ? "Some notes could not be read." : ""
            }
        }
    }

    func scan(folder: String, completion: @escaping (_ rootChanged: Bool) -> Void = { _ in }) {
        let id = UUID(); scanID = id
        guard !folder.isEmpty else {
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
            folderPaths = []; modified = [:]; created = [:]; loadedFolder = ""; loading = false; index = .empty
            message = "Choose a notes folder."
            return
        }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let rootChanged = root.path != loadedFolder
        if rootChanged {
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
            folderPaths = []; modified = [:]; created = [:]; index = .empty
        }
        loading = true; message = ""
        queue.async {
            // A first scan of this folder shows the saved library at once, then scans for real.
            if rootChanged, let cached = LibraryCache.load(root: root) {
                let index = LibraryIndex(snapshot: cached.snapshot, root: root)
                let folders = SidebarFolders.paths(in: root)
                DispatchQueue.main.async {
                    guard self.scanID == id, self.snapshot.cards.isEmpty else { return }
                    self.snapshot = cached.snapshot; self.index = index; self.generation += 1
                    self.folderPaths = folders; self.modified = cached.modified; self.created = cached.created
                    self.loadedFolder = root.path
                }
            }
            let found = LibrarySnapshot.load(folder: root)
            self.queueSnapshot = found.map { (root, $0) }
            let folders = found == nil ? [] : SidebarFolders.paths(in: root)
            let extras = Self.extras(for: found?.cards ?? [])
            let modified = extras.modified, created = extras.created, themes = extras.themes
            let index = found.map { LibraryIndex(snapshot: $0, root: root) } ?? .empty
            if let found { LibraryCache.save(found, modified: modified, created: created, root: root) }
            DispatchQueue.main.async {
                guard self.scanID == id else { return }
                self.loading = false
                guard let found else {
                    self.snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
                    self.folderPaths = []; self.modified = [:]; self.created = [:]; self.loadedFolder = ""; self.index = .empty
                    self.message = "Can't read this folder. Choose it again."
                    return
                }
                self.snapshot = found; self.index = index; self.generation += 1; self.folderPaths = folders; self.modified = modified; self.created = created; self.themes = themes
                self.loadedFolder = root.path
                self.message = found.unreadable > 0 ? "Some notes could not be read." : ""
                completion(rootChanged)
            }
        }
    }

    func card(for url: URL?) -> LibraryCard? { index.card(for: url) }
    func backlinks(for url: URL?) -> [LibraryCard] { index.backlinks(for: url) }
    func outgoing(for url: URL?) -> [LibraryCard] { index.outgoing(for: url) }
}

// Favorites and recents are stored as standardized absolute paths, one per line.
enum KasterPathList {
    static func decode(_ stored: String) -> [String] { stored.split(separator: "\n").map(String.init) }
    static func encode(_ paths: [String]) -> String { paths.joined(separator: "\n") }
    static func key(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    static func pushRecent(_ url: URL, into stored: String, limit: Int = 30) -> String {
        let path = key(url)
        var list = decode(stored).filter { $0 != path }
        list.insert(path, at: 0)
        return encode(Array(list.prefix(limit)))
    }
    static func toggle(_ url: URL, in stored: String) -> String {
        let path = key(url)
        var list = decode(stored)
        if let index = list.firstIndex(of: path) { list.remove(at: index) } else { list.append(path) }
        return encode(list)
    }
}

enum KasterDates {
    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy")
        return formatter.string(from: date)
    }
    static func full(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum KasterText {
    static func wordCount(_ text: String) -> Int {
        var body = text
        let metadata = CardMetadata.parse(text)
        if metadata.id != nil { body = metadata.body }
        return body.split { $0.isWhitespace || $0.isNewline }.filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }
    static func tags(_ text: String) -> [String] { CardSyntax.tags(in: text) }
}

// Luhmann sequences: 21 → 21/1 → 21/1a → 21/1a1. A descendant extends the parent's ID
// with a separator ("/" or ",") or with a component of the opposite kind (digit ↔ letter).
enum KasterSequence {
    static func isDescendant(_ id: String, of parent: String) -> Bool {
        let child = id.lowercased(), base = parent.lowercased()
        guard !base.isEmpty, child.count > base.count, child.hasPrefix(base), let last = base.last else { return false }
        let next = child[child.index(child.startIndex, offsetBy: base.count)]
        if next == "/" || next == "," || next == "." { return true }
        if last == "/" || last == "," || last == "." { return true }
        return last.isNumber ? next.isLetter : next.isNumber
    }

    /// The card and all its descendants, in sequence order.
    static func branch(of card: LibraryCard, in cards: [LibraryCard]) -> [LibraryCard] {
        guard let id = card.cardID, !id.isEmpty else { return [card] }
        let descendants = cards.filter { other in other.cardID.map { isDescendant($0, of: id) } ?? false }
        return [card] + descendants.sorted { ($0.cardID ?? "").localizedStandardCompare($1.cardID ?? "") == .orderedAscending }
    }
}

/// Remembers one derived value per key, so a view can skip recomputing it on unrelated redraws
/// (the sidebar's sorted card list while you type in the editor).
final class DerivedCache<Value> {
    private var key: String?
    private var value: Value?
    func value(for key: String, compute: () -> Value) -> Value {
        if key == self.key, let value { return value }
        let fresh = compute()
        self.key = key; self.value = fresh
        return fresh
    }
}
