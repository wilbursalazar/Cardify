import Foundation

struct GraphNode: Identifiable {
    let path: String
    let url: URL
    let title: String
    let cardID: String?
    // Number of distinct neighbors connected by explicit links in either direction.
    let degree: Int
    var id: String { path }
}

struct GraphEdge: Hashable {
    enum Kind: Hashable { case link, possibleBranch }
    let source: String
    let target: String
    let kind: Kind
}

// A read-only snapshot. The caller may load it on a background queue.
struct CardGraph {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let unreadableCount: Int
    let unresolvedCount: Int

    // The filesystem may change while the graph window is open. Never open a
    // stale node through a new symlink or outside the selected notes folder.
    static func canOpen(_ url: URL, in folder: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "md" else { return false }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let candidate = url.standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix),
              candidate.resolvingSymlinksInPath().standardizedFileURL == candidate,
              FileManager.default.isReadableFile(atPath: candidate.path) else { return false }
        var item = candidate
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        while item != root {
            guard item.path.hasPrefix(prefix), let values = try? item.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true, values.isHidden != true else { return false }
            if item == candidate { guard values.isRegularFile == true else { return false } }
            else { guard values.isDirectory == true else { return false } }
            item = item.deletingLastPathComponent()
        }
        return true
    }

    static func load(folder: URL) throws -> CardGraph {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        guard let snapshot = LibrarySnapshot.load(folder: root) else { throw CocoaError(.fileReadNoPermission) }
        let cards = snapshot.cards
        var byPath: [String: [LibraryCard]] = [:]
        var byName: [String: [LibraryCard]] = [:]
        for card in cards {
            byPath[card.path.lowercased(), default: []].append(card)
            byName[(card.path as NSString).lastPathComponent.lowercased(), default: []].append(card)
        }
        var links = Set<GraphEdge>()
        var unresolved = 0
        for source in cards {
            for link in CardLinkParser.links(in: maskComments(source.content)) {
                switch resolve(link.target, from: source, root: root, byPath: byPath, byName: byName, complete: snapshot.unreadable == 0) {
                case .note(let target):
                    if target.path != source.path { links.insert(GraphEdge(source: source.path, target: target.path, kind: .link)) }
                case .unresolved: unresolved += 1
                case .ignored: break
                }
            }
        }
        var neighbors: [String: Set<String>] = [:]
        for edge in links {
            neighbors[edge.source, default: []].insert(edge.target)
            neighbors[edge.target, default: []].insert(edge.source)
        }
        var byID: [String: [LibraryCard]] = [:]
        for card in cards {
            if let id = card.cardID, LibrarySequence.components(id) != nil {
                byID[id.lowercased(), default: []].append(card)
            }
        }
        var branches = Set<GraphEdge>()
        for child in cards where snapshot.unreadable == 0 {
            guard let id = child.cardID, let parts = LibrarySequence.components(id), !parts.prefix.isEmpty,
                  byID[id.lowercased()]?.count == 1,
                  let parents = byID[parts.prefix.lowercased()], parents.count == 1,
                  let parent = parents.first, parent.path != child.path else { continue }
            branches.insert(GraphEdge(source: parent.path, target: child.path, kind: .possibleBranch))
        }
        let nodes = cards.map { GraphNode(path: $0.path, url: $0.url, title: $0.title, cardID: $0.cardID, degree: neighbors[$0.path]?.count ?? 0) }
        let edges = (links.union(branches)).sorted {
            if $0.source != $1.source { return $0.source.localizedStandardCompare($1.source) == .orderedAscending }
            if $0.target != $1.target { return $0.target.localizedStandardCompare($1.target) == .orderedAscending }
            return $0.kind == .link && $1.kind == .possibleBranch
        }
        return CardGraph(nodes: nodes, edges: edges, unreadableCount: snapshot.unreadable, unresolvedCount: unresolved)
    }

    func neighborhood(of path: String, depth: Int, includeBranches: Bool) -> Set<String> {
        guard nodes.contains(where: { $0.path == path }) else { return [] }
        var adjacency: [String: Set<String>] = [:]
        for edge in edges where includeBranches || edge.kind == .link {
            adjacency[edge.source, default: []].insert(edge.target)
            adjacency[edge.target, default: []].insert(edge.source)
        }
        var seen: Set<String> = [path], frontier: Set<String> = [path]
        for _ in 0..<max(0, depth) {
            var next = Set<String>()
            for item in frontier { next.formUnion(adjacency[item] ?? []) }
            next.subtract(seen)
            if next.isEmpty { break }
            seen.formUnion(next); frontier = next
        }
        return seen
    }

    // Hide HTML and Obsidian comments without changing offsets or line breaks.
    // Comment delimiters in fenced or inline code are ordinary code text.
    private static func maskComments(_ text: String) -> String {
        let original = Array(text.utf16)
        var masked = original
        var lineStart = 0
        var fence: (marker: UInt16, count: Int)?
        var comment: String?
        func begins(_ sequence: [UInt16], at position: Int, before end: Int) -> Bool {
            position + sequence.count <= end && original[position..<(position + sequence.count)].elementsEqual(sequence)
        }
        func blank(_ range: Range<Int>) {
            for index in range where original[index] != 10 && original[index] != 13 { masked[index] = 32 }
        }
        while lineStart < original.count {
            var end = lineStart
            while end < original.count && original[end] != 10 && original[end] != 13 { end += 1 }
            var next = end
            if next < original.count && original[next] == 13 { next += 1 }
            if next < original.count && original[next] == 10 { next += 1 }
            var first = lineStart
            while first < end && original[first] == 32 && first - lineStart < 4 { first += 1 }
            if comment == nil {
                if first - lineStart <= 3 && first < end && (original[first] == 96 || original[first] == 126) {
                    let marker = original[first]
                    var after = first
                    while after < end && original[after] == marker { after += 1 }
                    let count = after - first
                    if count >= 3 {
                        if let open = fence {
                            if marker == open.marker && count >= open.count && original[after..<end].allSatisfy({ $0 == 32 || $0 == 9 }) { fence = nil }
                        } else { fence = (marker, count) }
                        lineStart = next; continue
                    }
                }
                if fence != nil || first - lineStart >= 4 || (lineStart < end && original[lineStart] == 9) {
                    lineStart = next; continue
                }
            }
            var position = lineStart
            while position < end {
                if let active = comment {
                    let close: [UInt16] = active == "html" ? [45, 45, 62] : [37, 37]
                    if begins(close, at: position, before: end) {
                        blank(position..<(position + close.count)); position += close.count; comment = nil
                    } else { blank(position..<(position + 1)); position += 1 }
                    continue
                }
                if original[position] == 92 { position = min(position + 2, end); continue }
                if original[position] == 96 {
                    var after = position
                    while after < end && original[after] == 96 { after += 1 }
                    let ticks = Array(original[position..<after])
                    var closing = after
                    while closing < end && !begins(ticks, at: closing, before: end) { closing += 1 }
                    position = closing < end ? closing + ticks.count : after
                    continue
                }
                if begins([60, 33, 45, 45], at: position, before: end) {
                    blank(position..<(position + 4)); position += 4; comment = "html"; continue
                }
                if begins([37, 37], at: position, before: end) {
                    blank(position..<(position + 2)); position += 2; comment = "obsidian"; continue
                }
                position += 1
            }
            lineStart = next
        }
        return String(decoding: masked, as: UTF16.self)
    }

    private enum Match { case note(LibraryCard), unresolved, ignored }

    // Match the navigation resolver while using a precomputed path/name index:
    // loading a graph must not rescan the entire vault for each link.
    private static func resolve(_ target: CardLinkTarget, from source: LibraryCard, root: URL,
                                byPath: [String: [LibraryCard]], byName: [String: [LibraryCard]], complete: Bool) -> Match {
        let raw: String
        let relativeToCurrent: Bool
        switch target {
        case .wiki(let value):
            raw = String(value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
            relativeToCurrent = false
        case .url(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let scheme = URLComponents(string: trimmed)?.scheme, !scheme.isEmpty { return .ignored }
            let pieces = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            guard let decodedPath = String(pieces[0]).removingPercentEncoding,
                  let decodedFragment = pieces.count == 2 ? String(pieces[1]).removingPercentEncoding : "" else { return .unresolved }
            guard decodedPath.isEmpty || (decodedPath as NSString).pathExtension.lowercased() == "md" else { return .ignored }
            raw = decodedPath + (pieces.count == 2 ? "#" + decodedFragment : "")
            relativeToCurrent = true
        }
        let pieces = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var path = String(pieces[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        if pieces.count > 1 {
            let fragment = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if fragment.isEmpty || fragment.hasPrefix("^") { return .unresolved }
        }
        if path.isEmpty { return .ignored } // Same-note heading, not a neighboring card.
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .unresolved }
        if (path as NSString).pathExtension.lowercased() == "md" { path = String(path.dropLast(3)) }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let containsParent = components.contains("..")
        guard (!containsParent || relativeToCurrent), !components.contains(where: { $0.isEmpty }) else { return .unresolved }
        let explicitRelative = components.first == "."
        if explicitRelative { path = components.dropFirst().joined(separator: "/") }
        guard !path.isEmpty else { return .unresolved }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var matches: [LibraryCard] = []
        if relativeToCurrent || explicitRelative {
            let parent = source.url.deletingLastPathComponent().standardizedFileURL
            guard parent.path == root.path || parent.path.hasPrefix(prefix) else { return .unresolved }
            let destination = parent.appendingPathComponent(path).standardizedFileURL.path
            guard destination.hasPrefix(prefix) else { return .unresolved }
            matches = byPath[String(destination.dropFirst(prefix.count)).lowercased()] ?? []
        }
        if matches.isEmpty && !explicitRelative && !containsParent {
            // If a note or folder could not be read, an unseen basename may be
            // a duplicate. Do not turn an uncertain link into a false edge.
            if !path.contains("/") && !complete { return .unresolved }
            matches = path.contains("/") ? (byPath[path.lowercased()] ?? []) : (byName[path.lowercased()] ?? [])
        }
        guard matches.count == 1, let note = matches.first else { return .unresolved }
        return .note(note)
    }
}
