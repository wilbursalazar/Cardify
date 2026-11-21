import Foundation
import AppKit

// Library data is read-only: filenames and note contents are never changed by browsing.
struct LibraryCard: Identifiable {
    let url: URL
    let path: String
    let title: String
    let cardID: String?
    let content: String
    var id: String { path }
    var canLink: Bool { CardifyNote(path: path).canLink }
}

struct LibrarySnapshot {
    let cards: [LibraryCard]
    let outgoing: [String: [String]]
    let incoming: [String: [String]]
    let unreadable: Int

    static func load(folder: URL) -> LibrarySnapshot? {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var unreadable = 0
        guard manager.isReadableFile(atPath: folder.path),
              let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in unreadable += 1; return true }) else { return nil }
        let root = folder.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var cards: [LibraryCard] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { unreadable += 1; continue }
            if values.isSymbolicLink == true { if values.isDirectory == true { enumerator.skipDescendants() }; continue }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            let fullPath = url.standardizedFileURL.path
            guard fullPath.hasPrefix(prefix) else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { unreadable += 1; continue }
            let relative = String(fullPath.dropFirst(prefix.count))
            let path = String(relative.dropLast(url.pathExtension.count + 1))
            let title = KasterVault.displayTitle(for: url, text: content)
            let cardID = CardMetadata.parse(content).id ?? BranchIDs.filenameID(for: url) ?? BranchIDs.luhmannFilenameID(for: url) ?? BranchIDs.debateFilenameID(for: url)
            cards.append(LibraryCard(url: url, path: path, title: title, cardID: cardID, content: content))
        }
        cards.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let links = LibraryLinks.build(cards: cards)
        return LibrarySnapshot(cards: cards, outgoing: links.outgoing, incoming: links.incoming, unreadable: unreadable)
    }
}

enum LibrarySearch {
    static func matches(_ card: LibraryCard, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || card.path.localizedCaseInsensitiveContains(q) || card.title.localizedCaseInsensitiveContains(q) || (card.cardID?.localizedCaseInsensitiveContains(q) ?? false) || card.content.localizedCaseInsensitiveContains(q)
    }
}

enum LibraryLinks {
    // Resolve only unambiguous paths or names. Ambiguous links are not presented as backlinks.
    static func build(cards: [LibraryCard], sources: [LibraryCard]? = nil) -> (outgoing: [String: [String]], incoming: [String: [String]]) {
        var byPath: [String: [String]] = [:]
        var byName: [String: [String]] = [:]
        for card in cards {
            byPath[card.path.lowercased(), default: []].append(card.path)
            byName[(card.path as NSString).lastPathComponent.lowercased(), default: []].append(card.path)
        }
        var outgoing: [String: [String]] = [:]
        var incoming: [String: [String]] = [:]
        for source in sources ?? cards {
            var seen: Set<String> = []
            for link in CardSyntax.wikiLinks(in: source.content) {
                let target = link.target.path
                guard !target.isEmpty else { continue }
                // An unqualified name shared by multiple files is ambiguous,
                // even when one happens to live at the vault root.
                if !target.contains("/"), (byName[target.lowercased()]?.count ?? 0) > 1 { continue }
                var matches = byPath[target.lowercased()] ?? []
                if matches.isEmpty && (target.hasPrefix("./") || target.hasPrefix("../")) {
                    let folder = (source.path as NSString).deletingLastPathComponent
                    let joined = ("/" + folder + "/" + target as NSString).standardizingPath
                    matches = byPath[String(joined.dropFirst()).lowercased()] ?? []
                }
                if matches.isEmpty && !target.contains("/") { matches = byName[target.lowercased()] ?? [] }
                guard matches.count == 1, let resolved = matches.first, seen.insert(resolved).inserted else { continue }
                outgoing[source.path, default: []].append(resolved)
                incoming[resolved, default: []].append(source.path)
            }
        }
        return (outgoing, incoming)
    }
}

// These are address-shape hints, not assertions about why two notes were created.
enum LibrarySequence {
    static func components(_ id: String) -> (prefix: String, suffix: String)? {
        guard !id.isEmpty,
              id.range(of: #"^[0-9]{12}"#, options: .regularExpression) == nil,
              id.range(of: #"^[0-9]+(?:[.,/][0-9]+)?(?:[A-Za-z]+[0-9]*)*$"#, options: .regularExpression) != nil else { return nil }
        let chars = Array(id)
        guard let last = chars.last else { return nil }
        let isNumber = last.isNumber
        var index = chars.count - 1
        while index > 0 && chars[index - 1].isNumber == isNumber { index -= 1 }
        return (String(chars[..<index]), String(chars[index...]))
    }
    static func hints(for card: LibraryCard, in cards: [LibraryCard]) -> [(String, LibraryCard)] {
        guard let id = card.cardID, let parts = components(id) else { return [] }
        // Duplicate IDs make any inferred address relationship unreliable.
        let counts = Dictionary(grouping: cards.compactMap { $0.cardID?.lowercased() }, by: { $0 }).mapValues { $0.count }
        guard counts[id.lowercased()] == 1 else { return [] }
        let eligible = cards.filter { $0.path != card.path && $0.cardID.map { counts[$0.lowercased()] == 1 && components($0) != nil } == true }
        var result: [(String, LibraryCard)] = []
        if !parts.prefix.isEmpty, let parent = eligible.first(where: { $0.cardID?.caseInsensitiveCompare(parts.prefix) == .orderedSame }) {
            result.append(("Possible parent", parent))
        }
        let siblings = eligible.filter { other in
            guard let otherID = other.cardID, let otherParts = components(otherID) else { return false }
            return otherParts.prefix.caseInsensitiveCompare(parts.prefix) == .orderedSame && otherParts.suffix.first?.isNumber == parts.suffix.first?.isNumber
        } + [card]
        let sorted = siblings.sorted { ($0.cardID ?? "").localizedStandardCompare($1.cardID ?? "") == .orderedAscending }
        if let index = sorted.firstIndex(where: { $0.path == card.path }) {
            if index > 0 { result.append(("Previous in sequence", sorted[index - 1])) }
            if index + 1 < sorted.count { result.append(("Next in sequence", sorted[index + 1])) }
        }
        for child in eligible where components(child.cardID!)?.prefix.caseInsensitiveCompare(id) == .orderedSame {
            result.append(("Possible branch", child))
        }
        return result
    }
}

extension LibrarySnapshot {
    /// The snapshot after some files changed on disk (saved, created, renamed or deleted),
    /// without rescanning the whole folder. Links are recomputed only for changed cards unless
    /// the set of card paths changed, which can alter how names resolve.
    func updating(_ files: [URL], root: URL) -> LibrarySnapshot {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        // Deleted files can't be resolved, and /private/var vs /var spellings differ; try both.
        func variants(_ path: String) -> [String] {
            path.hasPrefix("/private/") ? [path, String(path.dropFirst("/private".count))] : [path, "/private" + path]
        }
        let prefixes = variants(prefix)
        func relativePath(_ url: URL) -> String? {
            for candidate in [url.path, url.standardizedFileURL.path, url.resolvingSymlinksInPath().standardizedFileURL.path].flatMap(variants) {
                if let base = prefixes.first(where: { candidate.hasPrefix($0) }) {
                    return String(candidate.dropFirst(base.count).dropLast(url.pathExtension.count + 1))
                }
            }
            return nil
        }
        var byPath = Dictionary(cards.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var touched: Set<String> = []
        var pathsChanged = false
        var unreadable = self.unreadable
        for file in files where file.pathExtension.lowercased() == "md" {
            guard let path = relativePath(file) else { continue }
            touched.insert(path)
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let hidden = path.split(separator: "/").contains { $0.hasPrefix(".") }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true, !hidden,
                  let content = try? String(contentsOf: file, encoding: .utf8) else {
                if byPath.removeValue(forKey: path) != nil { pathsChanged = true }
                if values?.isRegularFile == true && !hidden && values?.isSymbolicLink != true { unreadable += 1 }
                continue
            }
            let url = URL(fileURLWithPath: prefix + path + "." + file.pathExtension)
            let title = KasterVault.displayTitle(for: url, text: content)
            let cardID = CardMetadata.parse(content).id ?? BranchIDs.filenameID(for: url) ?? BranchIDs.luhmannFilenameID(for: url) ?? BranchIDs.debateFilenameID(for: url)
            if byPath[path] == nil { pathsChanged = true }
            byPath[path] = LibraryCard(url: url, path: path, title: title, cardID: cardID, content: content)
        }
        guard !touched.isEmpty else { return self }
        let newCards = byPath.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        if pathsChanged {
            let links = LibraryLinks.build(cards: newCards)
            return LibrarySnapshot(cards: newCards, outgoing: links.outgoing, incoming: links.incoming, unreadable: unreadable)
        }
        // Same paths: only the changed cards' outgoing links can differ.
        var outgoing = self.outgoing, incoming = self.incoming
        for path in touched {
            for target in outgoing[path] ?? [] { incoming[target]?.removeAll { $0 == path }; if incoming[target]?.isEmpty == true { incoming[target] = nil } }
            outgoing[path] = nil
        }
        let changedCards = newCards.filter { touched.contains($0.path) }
        let partial = LibraryLinks.build(cards: newCards, sources: changedCards)
        for (path, targets) in partial.outgoing { outgoing[path] = targets }
        for (target, sources) in partial.incoming { incoming[target, default: []].append(contentsOf: sources) }
        return LibrarySnapshot(cards: newCards, outgoing: outgoing, incoming: incoming, unreadable: unreadable)
    }
}


/// The last library scan, saved so a large vault lists its cards the moment Kaster opens.
/// It is only a head start: a full scan always follows and replaces it.
enum LibraryCache {
    private struct Entry: Codable { let file: String; let title: String; let cardID: String?; let content: String; let modified: Date?; let created: Date? }
    private struct Stored: Codable { let version: Int; let root: String; let entries: [Entry] }
    private static let version = 1

    static func file(for root: URL) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let name = Data(root.path.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").prefix(80)
        let bundle = Bundle.main.bundleIdentifier ?? "kaster"
        return caches.appendingPathComponent(bundle).appendingPathComponent("library-\(name).plist")
    }

    static func save(_ snapshot: LibrarySnapshot, modified: [String: Date], created: [String: Date], root: URL) {
        guard let file = file(for: root) else { return }
        let rootPath = root.standardizedFileURL.path
        let entries = snapshot.cards.map { card -> Entry in
            let name = card.path + "." + card.url.pathExtension
            return Entry(file: name, title: card.title, cardID: card.cardID, content: card.content, modified: modified[card.path], created: created[card.path])
        }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        guard let data = try? encoder.encode(Stored(version: version, root: rootPath, entries: entries)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func load(root: URL) -> (snapshot: LibrarySnapshot, modified: [String: Date], created: [String: Date])? {
        guard let file = file(for: root), let data = try? Data(contentsOf: file),
              let stored = try? PropertyListDecoder().decode(Stored.self, from: data),
              stored.version == version, stored.root == root.standardizedFileURL.path else { return nil }
        var modified: [String: Date] = [:], created: [String: Date] = [:]
        let cards = stored.entries.map { entry -> LibraryCard in
            let path = (entry.file as NSString).deletingPathExtension
            modified[path] = entry.modified; created[path] = entry.created
            return LibraryCard(url: root.appendingPathComponent(entry.file), path: path, title: entry.title, cardID: entry.cardID, content: entry.content)
        }
        let links = LibraryLinks.build(cards: cards)
        return (LibrarySnapshot(cards: cards, outgoing: links.outgoing, incoming: links.incoming, unreadable: 0), modified, created)
    }
}
