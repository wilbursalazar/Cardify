import Foundation
import AppKit

struct CardifyNote: Identifiable, Hashable {
    let path: String
    var id: String { path }
    var title: String { URL(fileURLWithPath: path).lastPathComponent }
    // Obsidian treats these characters as link syntax rather than filename characters.
    var canLink: Bool { !path.contains("%%") && !path.contains(where: { "[]|#^:\n\r".contains($0) }) }
    var wikiLink: String { "[[\(path)]]" }
    /// "[[Name]]" when no other note shares that file name, else "[[Folder/Name]]", so links stay
    /// short and readable but never ambiguous.
    func wikiLink(among paths: [String]) -> String { "[[\(Self.shortestLink(for: path, among: paths))]]" }
    static func shortestLink(for path: String, among paths: [String]) -> String {
        let name = (path as NSString).lastPathComponent
        let lowered = name.lowercased()
        let clashes = paths.contains { $0 != path && ($0 as NSString).lastPathComponent.lowercased() == lowered }
        return clashes ? path : name
    }
}

enum CardifyNoteIndex {
    static func scan(folder: URL) -> [CardifyNote]? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        let rootPath = folder.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var notes: [CardifyNote] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isHidden == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            let fullPath = url.standardizedFileURL.path
            guard fullPath.hasPrefix(prefix) else { continue }
            let relative = String(fullPath.dropFirst(prefix.count))
            let path = String(relative.dropLast(url.pathExtension.count + 1))
            notes.append(CardifyNote(path: path))
        }
        return notes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
