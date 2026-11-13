import Foundation

// A read-only view of saved Markdown relationships. A branch may display a
// related card that has its primary home under another parent; its note is not copied.
struct DebateBranch {
    let parent: LibraryCard
    let primary: [LibraryCard]
    let related: [LibraryCard]
    // Primary children can themselves have descendants. Related links are
    // non-recursive so cross-links do not create duplicate subtrees.
    let primaryBranches: [DebateBranch]
}

private struct DebateLookup {
    let cards: [LibraryCard]
    let info: [DebateInfo]
    let byPath: [String: [Int]]
    let byName: [String: [Int]]
    let incomplete: Bool

    init(_ snapshot: LibrarySnapshot) {
        cards = snapshot.cards
        info = snapshot.cards.map { DebateNotes.parse($0.content) }
        incomplete = snapshot.unreadable > 0
        var paths: [String: [Int]] = [:], names: [String: [Int]] = [:]
        for (index, card) in snapshot.cards.enumerated() {
            paths[card.path.lowercased(), default: []].append(index)
            names[(card.path as NSString).lastPathComponent.lowercased(), default: []].append(index)
        }
        byPath = paths; byName = names
    }
    func exact(_ path: String) -> Int? {
        guard let candidates = byPath[path.lowercased()], candidates.count == 1 else { return nil }
        return candidates[0]
    }
    func resolve(_ path: String) -> Int? {
        let key = path.lowercased()
        if !path.contains("/") {
            guard !incomplete, let matches = byName[key], matches.count == 1 else { return nil }
            return matches[0]
        }
        return exact(path)
    }
    func isParent(_ index: Int) -> Bool { info[index].valid && info[index].role != .project }
    func isProject(_ index: Int) -> Bool { info[index].valid && info[index].role == .project }
}

struct DebateHierarchy {
    // Show an address alongside the readable title without repeating an ID
    // already present in an imported filename or heading.
    static func displayName(_ card: LibraryCard) -> String {
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = card.cardID?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return title }
        guard !title.isEmpty, title.caseInsensitiveCompare(value) != .orderedSame else { return value }
        let lowered = title.lowercased(), prefix = value.lowercased()
        if lowered.hasPrefix(prefix + " ") || lowered.hasPrefix(prefix + " · ") || lowered.hasPrefix(prefix + " — ") { return title }
        return value + " · " + title
    }

    let project: LibraryCard?
    let aff: [DebateBranch]
    let def: [DebateBranch]
    // Unresolved or ambiguous relationships and malformed debate metadata in the snapshot.
    let unresolved: Int
    let unreadable: Int

    // Search/navigation must include descendants as well as related references.
    // A path occurs once even when several branches point to the same card.
    var visibleCards: [LibraryCard] {
        var result: [LibraryCard] = [], seen: Set<String> = []
        func append(_ card: LibraryCard) {
            if seen.insert(card.path).inserted { result.append(card) }
        }
        if let project { append(project) }
        var stack = Array((aff + def).reversed())
        while let branch = stack.popLast() {
            append(branch.parent)
            branch.related.forEach(append)
            stack.append(contentsOf: branch.primaryBranches.reversed())
        }
        return result
    }

    // Before changing a note's primary parent, follow only explicit primary
    // links. Cross-related links are not ancestry and cannot create a cycle.
    static func canSetPrimary(snapshot: LibrarySnapshot, currentURL: URL?, proposedParent: LibraryCard) -> Bool {
        let lookup = DebateLookup(snapshot)
        guard let parent = lookup.exact(proposedParent.path),
              lookup.cards[parent].url.resolvingSymlinksInPath().standardizedFileURL == proposedParent.url.resolvingSymlinksInPath().standardizedFileURL,
              lookup.isParent(parent) else { return false }
        let current: Int?
        if let currentURL {
            let canonicalCurrent = currentURL.resolvingSymlinksInPath().standardizedFileURL
            let matches = lookup.cards.indices.filter { lookup.cards[$0].url.resolvingSymlinksInPath().standardizedFileURL == canonicalCurrent }
            guard matches.count == 1 else { return false }
            current = matches[0]
        } else { current = nil }
        var seen: Set<Int> = [], node = parent
        while true {
            guard node != current, seen.insert(node).inserted, lookup.isParent(node) else { return false }
            let info = lookup.info[node]
            guard let parent = info.primary else { return info.related.isEmpty }
            guard let next = lookup.resolve(parent.path) else { return false }
            node = next
        }
    }

    // Find resolutions through the card's primary ancestry. Related links do
    // not affect its home. Any ambiguous or missing ancestor fails closed.
    static func projectsForCard(snapshot: LibrarySnapshot, cardPath: String) -> [String] {
        let lookup = DebateLookup(snapshot)
        guard var node = lookup.exact(cardPath) else { return [] }
        var seen: Set<Int> = []
        while seen.insert(node).inserted {
            let info = lookup.info[node]
            guard info.valid else { return [] }
            if lookup.isProject(node) { return [lookup.cards[node].path] }
            if info.role == .aff || info.role == .def {
                guard canSetPrimary(snapshot: snapshot, currentURL: nil, proposedParent: lookup.cards[node]) else { return [] }
                var paths: [String] = []
                for link in info.projects {
                    guard let target = lookup.resolve(link.path), lookup.isProject(target) else { return [] }
                    paths.append(lookup.cards[target].path)
                }
                return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }
            guard let parent = info.primary, let next = lookup.resolve(parent.path), lookup.isParent(next) else { return [] }
            node = next
        }
        return []
    }

    static func projects(in snapshot: LibrarySnapshot) -> [LibraryCard] {
        snapshot.cards.filter {
            let info = DebateNotes.parse($0.content)
            return info.valid && info.role == .project
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func build(snapshot: LibrarySnapshot, projectPath: String?) -> DebateHierarchy {
        let lookup = DebateLookup(snapshot)
        let cards = lookup.cards, info = lookup.info
        // Match the existing link resolver: a bare name is unsafe if the scan
        // is incomplete or two files share that name, even at the root.
        func resolve(_ path: String) -> Int? { lookup.resolve(path) }
        func isParent(_ index: Int) -> Bool {
            info[index].valid && (info[index].role == .aff || info[index].role == .def)
        }
        func isProject(_ index: Int) -> Bool { lookup.isProject(index) }
        func canBeParent(_ index: Int) -> Bool { lookup.isParent(index) }
        let projectIndex: Int? = projectPath.flatMap { path in
            guard let index = lookup.exact(path), isProject(index) else { return nil }
            return index
        }
        var unresolved = info.filter { !$0.valid }.count
        if projectPath != nil && projectIndex == nil { unresolved += 1 }
        var parents: [Int] = []
        for index in cards.indices where isParent(index) {
            var resolvedProjects: [Int] = []
            for relation in info[index].projects {
                if let target = resolve(relation.path), isProject(target) { resolvedProjects.append(target) }
                else { unresolved += 1 }
            }
            if let selected = projectIndex {
                if resolvedProjects.contains(selected) { parents.append(index) }
            } else if projectPath == nil && resolvedProjects.isEmpty {
                parents.append(index)
            }
        }
        // Resolve one explicit primary edge per note. Any non-project note
        // can become a parent, including an existing untyped Markdown card.
        var parentFor: [Int: Int] = [:]
        for child in cards.indices where canBeParent(child) {
            guard let relation = info[child].primary else { continue }
            if let target = resolve(relation.path), canBeParent(target), target != child {
                parentFor[child] = target
            } else { unresolved += 1 }
        }

        // A card has at most one primary parent, so each chain has at most one
        // cycle. Remove all edges in each cycle; other branches remain usable.
        // This iterative walk also handles very long chains without recursion.
        var complete: Set<Int> = [], cyclic: Set<Int> = []
        for start in cards.indices where !complete.contains(start) {
            var path: [Int] = [], positions: [Int: Int] = [:]
            var current: Int? = start
            while let node = current, !complete.contains(node) {
                if let position = positions[node] {
                    cyclic.formUnion(path[position...]); break
                }
                positions[node] = path.count; path.append(node)
                current = parentFor[node]
            }
            complete.formUnion(path)
        }
        for child in cyclic { parentFor.removeValue(forKey: child); unresolved += 1 }

        var primary: [Int: [Int]] = [:], related: [Int: [Int]] = [:]
        for (child, parent) in parentFor { primary[parent, default: []].append(child) }
        for child in cards.indices where canBeParent(child) {
            for relation in info[child].related {
                guard parentFor[child] != nil, let target = resolve(relation.path),
                      canBeParent(target), target != child else { unresolved += 1; continue }
                related[target, default: []].append(child)
            }
        }
        func sortedIndexes(_ indexes: [Int]) -> [Int] {
            indexes.sorted { cards[$0].path.localizedStandardCompare(cards[$1].path) == .orderedAscending }
        }
        func branch(_ root: Int) -> DebateBranch {
            var pending: [(Int, Bool)] = [(root, false)]
            var built: [Int: DebateBranch] = [:]
            while let (node, ready) = pending.popLast() {
                let children = sortedIndexes(primary[node] ?? [])
                if ready {
                    built[node] = DebateBranch(parent: cards[node],
                                               primary: children.map { cards[$0] },
                                               related: sortedIndexes(related[node] ?? []).map { cards[$0] },
                                               primaryBranches: children.compactMap { built[$0] })
                } else {
                    pending.append((node, true))
                    for child in children.reversed() { pending.append((child, false)) }
                }
            }
            return built[root]!
        }
        let branches = parents.map(branch).sorted { $0.parent.path.localizedStandardCompare($1.parent.path) == .orderedAscending }
        return DebateHierarchy(project: projectIndex.map { cards[$0] },
                               aff: branches.filter { DebateNotes.parse($0.parent.content).role == .aff },
                               def: branches.filter { DebateNotes.parse($0.parent.content).role == .def },
                               unresolved: unresolved, unreadable: snapshot.unreadable)
    }
}
