import Foundation

// Folder paths and card paths are relative to the chosen notes root.
enum SidebarFolders {
    struct Row: Identifiable {
        enum Kind { case folder, card }
        let kind: Kind
        let path: String
        let depth: Int
        let expanded: Bool
        var id: String { (kind == .folder ? "folder:" : "card:") + path }
        var name: String { (path as NSString).lastPathComponent }
    }

    // Do not follow symlinks or inspect hidden/package descendants. Empty
    // folders are included so a vault can be browsed before notes are added.
    static func paths(in root: URL) -> [String] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                 options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { return [] }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isPackage == true { enumerator.skipDescendants(); continue }
            guard values.isDirectory == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            paths.append(String(path.dropFirst(prefix.count)))
        }
        return paths
    }

    // Render a flattened tree, keeping search results visible even when their
    // parent folders are collapsed. Expanded folder paths survive rescans.
    static func rows(folders: [String], cards: [String], expanded: Set<String>, query: String) -> [Row] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var children: [String: Set<String>] = [:]
        var cardsByFolder: [String: [String]] = [:]
        func addFolder(_ path: String) {
            var parent = ""
            for part in path.split(separator: "/") {
                let full = parent.isEmpty ? String(part) : parent + "/" + part
                children[parent, default: []].insert(full)
                parent = full
            }
        }
        for path in folders { addFolder(path) }
        for card in cards {
            let parent = (card as NSString).deletingLastPathComponent
            if !parent.isEmpty { addFolder(parent) }
            cardsByFolder[parent, default: []].append(card)
        }
        let visibleFolders: Set<String>
        if search.isEmpty {
            visibleFolders = Set(children.values.flatMap { $0 })
        } else {
            var matched = Set<String>()
            for path in folders where path.localizedCaseInsensitiveContains(search) {
                var parent = path
                while !parent.isEmpty { matched.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
            }
            for card in cards {
                var parent = (card as NSString).deletingLastPathComponent
                while !parent.isEmpty { matched.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
            }
            visibleFolders = matched
        }
        var result: [Row] = []
        func append(_ parent: String, _ depth: Int) {
            let folders = (children[parent] ?? []).filter { visibleFolders.contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for path in folders {
                let open = !search.isEmpty || expanded.contains(path)
                result.append(Row(kind: .folder, path: path, depth: depth, expanded: open))
                if open { append(path, depth + 1) }
            }
            for path in (cardsByFolder[parent] ?? []).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                result.append(Row(kind: .card, path: path, depth: depth, expanded: false))
            }
        }
        append("", 0)
        return result
    }

    static func ancestors(of cardPath: String) -> Set<String> {
        var result = Set<String>()
        var parent = (cardPath as NSString).deletingLastPathComponent
        while !parent.isEmpty { result.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
        return result
    }
}
