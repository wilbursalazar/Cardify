import Foundation

// MARK: Card types

/// The four kinds of slip-box card. Each lives in its own folder inside the notes folder.
enum KasterMode: String, CaseIterable, Identifiable {
    case research, zettel, quick, bibliography
    var id: String { rawValue }
    var title: String {
        switch self {
        case .research: return "Research"
        case .zettel: return "Zettel"
        case .quick: return "Quick"
        case .bibliography: return "Bibliography"
        }
    }
    var folder: String { title }
    var systemImage: String {
        switch self {
        case .research: return "books.vertical"
        case .zettel: return "number"
        case .quick: return "bolt"
        case .bibliography: return "text.book.closed"
        }
    }
    var summary: String {
        switch self {
        case .research: return "Eco reading card: a quotation, your response, and its source"
        case .zettel: return "Luhmann card: one idea with a sequence ID like 21/3a"
        case .quick: return "Just a title — capture now, promote later"
        case .bibliography: return "One card per source; lists every Research card citing it"
        }
    }
    var usesID: Bool { self == .zettel }
    var idMode: IDMode { self == .zettel ? .luhmann : .titleOnly }

    /// New-card body. The cursor goes right after the first "# ".
    var template: String {
        switch self {
        case .research: return "# \n\n## Quotation\n\n> \n\n## Response\n\n\n\nSource: \n"
        case .zettel: return "# \n\n\n\n## Related cards\n\n"
        case .quick: return "# "
        case .bibliography: return "# \n\nAuthor: \nYear: \n"
        }
    }

    static func stored(_ value: String) -> KasterMode { KasterMode(rawValue: value) ?? .zettel }

    /// A card's type comes from the folder it lives in; otherwise from its ID.
    static func infer(url: URL?, root: URL?, text: String) -> KasterMode {
        if let url, let root, let first = KasterVault.relativePath(of: url, in: root)?.split(separator: "/").first,
           let mode = allCases.first(where: { $0.folder.caseInsensitiveCompare(String(first)) == .orderedSame }) {
            return mode
        }
        if let id = CardMetadata.parse(text).id, LuhmannIDs.isLuhmann(id) { return .zettel }
        return .quick
    }
}

/// To-Do, Habit and Debate stay available as artifacts, each in a folder you choose once.
enum KasterArtifact: String, CaseIterable, Identifiable {
    case habits, todos, debates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .habits: return "Habit Tracker"
        case .todos: return "To-Do List"
        case .debates: return "Debate"
        }
    }
    var folderName: String {
        switch self {
        case .habits: return "Habits"
        case .todos: return "To-Dos"
        case .debates: return "Debates"
        }
    }
    var storageKey: String { "kasterArtifactFolder.\(rawValue)" }
    var systemImage: String {
        switch self {
        case .habits: return "checkmark.circle"
        case .todos: return "checklist"
        case .debates: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: Frontmatter fields

/// Reads and writes single `key: value` lines in a card's YAML frontmatter, leaving every
/// other line (and the note body) exactly as it was. Used for `uid:` and `order:`.
enum KasterFrontmatter {
    private static func split(_ text: String) -> (newline: String, lines: [String], end: Int?)? {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let lines = text.components(separatedBy: newline)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{feff}", with: "") == "---" else {
            return (newline, lines, nil)
        }
        let end = lines.indices.dropFirst().first { lines[$0].trimmingCharacters(in: .whitespaces) == "---" || lines[$0] == "..." }
        guard let end else { return nil }  // unterminated: never touch
        return (newline, lines, end)
    }

    /// Every top-level `key: value` in the header, read once (same rules as `value`).
    /// Only the header is split into lines, so long cards cost no more than short ones.
    static func fields(in text: String) -> [String: String] {
        var body = Substring(text)
        if body.hasPrefix("\u{feff}") { body = body.dropFirst() }
        guard body.hasPrefix("---") else { return [:] }
        var result: [String: String] = [:]
        // "\r\n" is one Character in Swift, so split on either form.
        let isBreak: (Character) -> Bool = { $0 == "\n" || $0 == "\r\n" }
        var lines = body.split(maxSplits: 200, omittingEmptySubsequences: false, whereSeparator: isBreak).dropFirst().makeIterator()
        guard body.split(maxSplits: 1, whereSeparator: isBreak).first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        while let raw = lines.next() {
            let line = raw
            if line.trimmingCharacters(in: .whitespaces) == "---" || line == "..." { return result }
            guard let colon = line.firstIndex(of: ":"), line.first.map({ !$0.isWhitespace }) == true else { continue }
            let key = String(line[..<colon])
            guard result[key] == nil else { continue }
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { result[key] = value }
        }
        return [:]  // unterminated header: ignored, as `value` does
    }

    static func value(_ key: String, in text: String) -> String? {
        guard let parts = split(text), let end = parts.end else { return nil }
        for line in parts.lines[1..<end] where line.hasPrefix(key + ":") {
            var value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Sets (or removes, with nil) one field. Returns nil if the frontmatter can't be edited safely.
    static func setting(_ key: String, to value: String?, in text: String) -> String? {
        guard var parts = split(text) else { return nil }
        let line = value.map { "\(key): \($0)" }
        if let end = parts.end {
            if let index = parts.lines[1..<end].firstIndex(where: { $0.hasPrefix(key + ":") }) {
                if let line { parts.lines[index] = line } else { parts.lines.remove(at: index) }
            } else if let line {
                parts.lines.insert(line, at: end)
            } else { return text }
            return parts.lines.joined(separator: parts.newline)
        }
        guard let line else { return text }
        return "---" + parts.newline + line + parts.newline + "---" + parts.newline + text
    }

    /// A permanent, never-reused card identity (8 lowercase letters and digits).
    static func newUID() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    /// Adds a permanent `uid:` if the card doesn't have one yet.
    static func ensuringUID(in text: String) -> String {
        guard value("uid", in: text) == nil else { return text }
        return setting("uid", to: newUID(), in: text) ?? text
    }

    static func order(in text: String) -> Double? { value("order", in: text).flatMap(Double.init) }
}

// MARK: Luhmann IDs

/// Luhmann-style addresses: top-level 1, 2, 3…; going deeper from a top-level card uses a
/// slash (21 → 21/1); deeper levels alternate letters and numbers (21/1 → 21/1a → 21/1a1).
enum LuhmannIDs {
    static func isLuhmann(_ id: String) -> Bool {
        id.range(of: "^[0-9]{1,6}([/,][0-9]+)?([A-Za-z]+[0-9]*)*([/,][0-9A-Za-z]+)*$", options: .regularExpression) != nil
    }
    static func isTopLevel(_ id: String) -> Bool { id.range(of: "^[0-9]{1,6}$", options: .regularExpression) != nil }

    static func leadingNumber(_ id: String) -> Int? {
        guard isLuhmann(id) else { return nil }
        return Int(id.prefix { $0.isNumber })
    }

    /// The next unused top-level number after the highest one in use (gaps are not refilled).
    static func nextTopLevel(existing: Set<String>) -> String {
        String((existing.compactMap(leadingNumber).max() ?? 0) + 1)
    }

    static func firstChild(of parent: String, existing: Set<String>) -> String {
        let prefix = parent.lowercased() + "/"
        let used = existing.map { $0.lowercased() }.filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count).prefix { $0.isNumber }) }
        return "\(parent)/\((used.max() ?? 0) + 1)"
    }

    /// Continue = the next card at the same level: 21 → 22, 21/1 → 21/2, 21/1a → 21/1b.
    static func continuation(of parent: String, existing: Set<String>) throws -> String {
        try CardIDs.continuation(from: parent, existing: existing)
    }

    /// Branch = one level deeper: 21 → 21/1, 21/1 → 21/1a, 21/1a → 21/1a1.
    static func branch(of parent: String, existing: Set<String>) throws -> String {
        if isTopLevel(parent) { return firstChild(of: parent, existing: existing) }
        return try BranchIDs.branch(from: parent, existing: existing)
    }
}

// MARK: Files, names and links

enum KasterVault {
    /// Works for files that no longer exist (e.g. a card's old location after a move),
    /// where symlinked folders such as /var → /private/var can't be resolved.
    static func relativePath(of url: URL, in root: URL) -> String? {
        func variants(_ path: String) -> [String] {
            var result = [path]
            if path.hasPrefix("/private/") { result.append(String(path.dropFirst("/private".count))) }
            else { result.append("/private" + path) }
            return result
        }
        let bases = Set(variants(root.resolvingSymlinksInPath().standardizedFileURL.path) + variants(root.standardizedFileURL.path))
        let paths = Set(variants(url.resolvingSymlinksInPath().standardizedFileURL.path) + variants(url.standardizedFileURL.path))
        for base in bases {
            let prefix = base.hasSuffix("/") ? base : base + "/"
            if let path = paths.first(where: { $0.hasPrefix(prefix) }) { return String(path.dropFirst(prefix.count)) }
        }
        return nil
    }

    static func cleanTitle(_ title: String) -> String {
        let prohibited = CharacterSet(charactersIn: "/:\\[]|#^").union(.controlCharacters).union(.newlines)
        var result = title.components(separatedBy: prohibited).joined(separator: " ")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if result.count > 120 { result = String(result.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return result
    }

    /// Zettel: "21-3a7-Title.md" (slash becomes a dash; a dash joins ID and title). Others: "Title.md".
    static func filename(mode: KasterMode, id: String?, title: String) -> String? {
        let safeTitle = cleanTitle(title)
        guard !safeTitle.isEmpty else { return nil }
        if mode == .zettel, let id, !id.isEmpty {
            let safeID = id.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ",", with: "-")
            return "\(safeID)-\(safeTitle).md"
        }
        return "\(safeTitle).md"
    }

    /// The filename a card gets when retitled in place. Zettel cards follow the "21-3a7-Title" scheme;
    /// any other card keeps a filename ID it already has ("202611131437 Title", "AFF-1 Title").
    static func retitledFilename(for url: URL, root: URL?, text: String, title: String) -> String? {
        let safeTitle = cleanTitle(title)
        guard !safeTitle.isEmpty else { return nil }
        if let root, let relative = relativePath(of: url, in: root), let first = relative.split(separator: "/").first,
           KasterMode.zettel.folder.caseInsensitiveCompare(String(first)) == .orderedSame,
           let id = CardMetadata.parse(text).id, !id.isEmpty {
            return filename(mode: .zettel, id: id, title: safeTitle)
        }
        let stem = url.deletingPathExtension().lastPathComponent
        let ids = [BranchIDs.debateFilenameID(for: url), BranchIDs.filenameID(for: url), BranchIDs.luhmannFilenameID(for: url)].compactMap { $0 }
        guard let id = ids.max(by: { $0.count < $1.count }) else { return "\(safeTitle).md" }
        let rest = stem.dropFirst(id.count)
        let separator = rest.first.map(String.init) ?? " "
        return "\(id)\(separator)\(safeTitle).md"
    }

    /// The title a card shows: its "# " heading, or its filename (minus any ID) when it has none.
    static func displayTitle(for url: URL?, text: String) -> String {
        let heading = NoteEditing.title(in: text).trimmingCharacters(in: .whitespaces)
        if !heading.isEmpty { return heading }
        guard let url else { return "" }
        let stem = url.deletingPathExtension().lastPathComponent
        if let id = CardMetadata.parse(text).id, !id.isEmpty {
            let safeID = id.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ",", with: "-")
            if stem.count > safeID.count + 1, stem.lowercased().hasPrefix(safeID.lowercased() + "-") { return String(stem.dropFirst(safeID.count + 1)) }
        }
        let ids = [BranchIDs.debateFilenameID(for: url), BranchIDs.filenameID(for: url), BranchIDs.luhmannFilenameID(for: url)].compactMap { $0 }
        guard let id = ids.max(by: { $0.count < $1.count }) else { return stem }
        let rest = String(stem.dropFirst(id.count)).trimmingCharacters(in: CharacterSet(charactersIn: " _-"))
        return rest.isEmpty ? stem : rest
    }

    /// The first free name in the folder: "Title.md", "Title 2.md", …
    static func uniqueURL(in folder: URL, filename: String, excluding: URL? = nil) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var counter = 2
        let skip = excluding?.resolvingSymlinksInPath().standardizedFileURL.path
        while FileManager.default.fileExists(atPath: candidate.path) && candidate.resolvingSymlinksInPath().standardizedFileURL.path != skip {
            candidate = folder.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    static func ensureFolder(_ folder: URL) throws {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw CocoaError(.fileWriteFileExists) }
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static func markdownFiles(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true, values.isRegularFile == true,
                  url.pathExtension.lowercased() == "md" else { continue }
            files.append(url)
        }
        return files
    }

    /// Rewrites [[old]], [[old|label]], [[old#heading]] and folder-path forms to the new name.
    static func rewriteLinks(in text: String, from oldPaths: [String], to newPath: String) -> String? {
        let olds = Set(oldPaths.filter { !$0.isEmpty }.map { $0.lowercased() })
        guard !olds.isEmpty, let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]|#]+)((?:#[^\\]|]*)?(?:\\|[^\\]]*)?)\\]\\]") else { return nil }
        let ns = text as NSString
        var result = ""
        var last = 0
        var changed = false
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let target = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            var comparable = target.lowercased()
            if comparable.hasSuffix(".md") { comparable = String(comparable.dropLast(3)) }
            guard olds.contains(comparable) else { continue }
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += "[[\(newPath)\(ns.substring(with: match.range(at: 2)))]]"
            last = NSMaxRange(match.range)
            changed = true
        }
        guard changed else { return nil }
        return result + ns.substring(from: last)
    }

    /// Updates every link to a moved card. Links use the new filename; links that used a
    /// folder path keep using one. Returns the files that changed.
    @discardableResult
    static func updateLinks(root: URL, oldURL: URL, newURL: URL, skip: Set<String> = []) throws -> [URL] {
        guard let oldRelative = relativePath(of: oldURL, in: root), let newRelative = relativePath(of: newURL, in: root) else { return [] }
        let oldName = oldURL.deletingPathExtension().lastPathComponent
        let newName = newURL.deletingPathExtension().lastPathComponent
        let oldPath = (oldRelative as NSString).deletingPathExtension
        let newPath = (newRelative as NSString).deletingPathExtension
        guard oldPath != newPath else { return [] }
        var changed: [URL] = []
        for file in markdownFiles(in: root) {
            let key = file.resolvingSymlinksInPath().standardizedFileURL.path
            guard !skip.contains(key), let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var updated = text
            // Path-style links ([[Folder/Card]]) keep a path; plain-name links keep a plain name.
            if oldPath.contains("/"), let pathRewrite = rewriteLinks(in: updated, from: [oldPath], to: newPath) { updated = pathRewrite }
            if oldName != newName, let nameRewrite = rewriteLinks(in: updated, from: [oldName], to: newName) { updated = nameRewrite }
            if updated != text {
                try Data(updated.utf8).write(to: file, options: .atomic)
                changed.append(file)
            }
        }
        return changed
    }

    // MARK: Research sources

    struct Source: Equatable { var link: String?; var page: String? }

    static func source(in text: String) -> Source {
        guard let line = text.components(separatedBy: "\n").last(where: { $0.hasPrefix("Source:") }) else { return Source() }
        let ns = line as NSString
        var source = Source()
        if let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]|#]+)"), let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            source.link = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
        if let regex = try? NSRegularExpression(pattern: "(?:,\\s*|\\s)pp?\\.\\s*(.+)$"), let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            source.page = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
        return source
    }

    /// Writes "Source: [[Bibliography card]], p. 42", replacing the last Source line or appending one.
    static func setSource(_ source: Source, in text: String) -> String {
        var parts: [String] = []
        if let link = source.link, !link.isEmpty { parts.append("[[\(link)]]") }
        if let page = source.page?.trimmingCharacters(in: .whitespaces), !page.isEmpty { parts.append("p. \(page)") }
        let line = "Source: " + parts.joined(separator: ", ")
        var lines = text.components(separatedBy: "\n")
        if let index = lines.lastIndex(where: { $0.hasPrefix("Source:") }) {
            lines[index] = line
            return lines.joined(separator: "\n")
        }
        let trimmed = text.trimmingCharacters(in: .newlines)
        return trimmed + "\n\n" + line + "\n"
    }

    static func bibliographyMarkdown(title: String, author: String, year: String) -> String {
        "# \(title)\n\nAuthor: \(author)\nYear: \(year)\n"
    }

    // MARK: Migration

    struct MigrationStep: Identifiable, Equatable {
        let from: URL
        let to: URL
        let newContent: String?   // nil = move only
        var id: String { from.path }
    }

    struct MigrationPlan: Equatable {
        var steps: [MigrationStep]
        var foldersToRemove: [URL]
    }

    /// Classifies every Markdown card outside the Kaster folders:
    /// cards with a Luhmann ID → Zettel/ID-Title.md; habit tables, to-do lists and debates →
    /// their artifact folders; everything else → Quick/Title.md. Titles come from headings.
    static func migrationPlan(root: URL, artifactFolders: [KasterArtifact: URL]) -> MigrationPlan {
        let managed = Set(KasterMode.allCases.map { $0.folder.lowercased() })
        let artifactPaths = artifactFolders.values.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        var steps: [MigrationStep] = []
        var claimed = Set<String>()
        func claim(_ folder: URL, _ filename: String) -> URL {
            var candidate = uniqueURL(in: folder, filename: filename)
            var counter = 2
            let base = (filename as NSString).deletingPathExtension
            while claimed.contains(candidate.path.lowercased()) {
                candidate = folder.appendingPathComponent("\(base) \(counter).md"); counter += 1
            }
            claimed.insert(candidate.path.lowercased())
            return candidate
        }
        for file in markdownFiles(in: root).sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            guard let relative = relativePath(of: file, in: root) else { continue }
            let first = relative.split(separator: "/").first.map { String($0).lowercased() } ?? ""
            if relative.contains("/") && managed.contains(first) { continue }
            let path = file.resolvingSymlinksInPath().standardizedFileURL.path
            if artifactPaths.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let heading = NoteEditing.title(in: text).trimmingCharacters(in: .whitespaces)
            let title = heading.isEmpty ? file.deletingPathExtension().lastPathComponent : heading
            let artifact: KasterArtifact? = HabitTracker.fromMarkdown(text) != nil ? .habits
                : TodoList.fromMarkdown(text) != nil ? .todos
                : (DebateNotes.parse(text).valid && DebateNotes.parse(text).role != nil) ? .debates : nil
            // Slip-box cards get their permanent uid as they're organized; artifacts are left as they are.
            let withUID = KasterFrontmatter.ensuringUID(in: text)
            let uidContent = withUID == text ? nil : withUID
            if let artifact, let folder = artifactFolders[artifact] {
                steps.append(MigrationStep(from: file, to: claim(folder, cleanTitle(title).isEmpty ? file.lastPathComponent : cleanTitle(title) + ".md"), newContent: nil))
            } else if let id = CardMetadata.parse(text).id, LuhmannIDs.isLuhmann(id), let name = filename(mode: .zettel, id: id, title: title) {
                steps.append(MigrationStep(from: file, to: claim(root.appendingPathComponent(KasterMode.zettel.folder), name), newContent: uidContent))
            } else if let name = filename(mode: .quick, id: nil, title: title) {
                steps.append(MigrationStep(from: file, to: claim(root.appendingPathComponent(KasterMode.quick.folder), name), newContent: uidContent))
            }
        }
        steps = steps.filter { $0.from.standardizedFileURL.path != $0.to.standardizedFileURL.path }
        // Folders left empty by the moves (deepest first).
        let sources = Set(steps.map { $0.from.deletingLastPathComponent().standardizedFileURL.path })
        let rootPath = root.standardizedFileURL.path
        var remove: [URL] = []
        for folderPath in sources where folderPath != rootPath {
            let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
            let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let leaving = Set(steps.map { $0.from.standardizedFileURL.path })
            if contents.allSatisfy({ leaving.contains($0.standardizedFileURL.path) }) { remove.append(folder) }
        }
        return MigrationPlan(steps: steps, foldersToRemove: remove.sorted { $0.path.count > $1.path.count })
    }

    /// Zips the whole notes folder next to it before anything moves. Returns the archive.
    static func backup(root: URL) throws -> URL {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyyMMdd-HHmmss"
        let archive = root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent) backup \(stamp.string(from: Date())).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, archive.path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: archive.path) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Could not create the backup archive."])
        }
        return archive
    }

    /// Moves every card, then rewrites links vault-wide, then removes emptied folders.
    static func applyMigration(_ plan: MigrationPlan, root: URL) throws {
        for step in plan.steps {
            try ensureFolder(step.to.deletingLastPathComponent())
            if let content = step.newContent { try Data(content.utf8).write(to: step.from, options: .atomic) }
            try FileManager.default.moveItem(at: step.from, to: step.to)
        }
        for step in plan.steps { try updateLinks(root: root, oldURL: step.from, newURL: step.to) }
        for folder in plan.foldersToRemove {
            let leftovers = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])) ?? []
            if leftovers.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) { try? FileManager.default.removeItem(at: folder) }
        }
    }
}

// MARK: Library index

/// Lookups the editor makes on every render, computed once per library snapshot
/// so typing never walks every card.
struct LibraryIndex {
    let cards: [LibraryCard]
    private let byKey: [String: Int]
    private let byPath: [String: Int]
    private let incoming: [String: [String]]
    private let outgoing: [String: [String]]
    let orders: [String: Double]
    let modes: [String: KasterMode]
    /// Every card ID and filename ID, lowercased-insensitive as stored, for new-ID suggestions.
    let ids: Set<String>
    private let byMode: [KasterMode: [LibraryCard]]
    private let byUID: [String: Int]
    /// Research cards citing each Zotero item ("library/key").
    private let zoteroCiting: [String: [LibraryCard]]
    /// Cards inside each folder path, including subfolders.
    private let folderCounts: [String: Int]
    /// Card paths carrying each #tag (lowercased), and the tags as first written, by name.
    private let tagged: [String: Set<String>]
    let tags: [(name: String, count: Int)]
    private static let tagPattern = try! NSRegularExpression(pattern: "(?<![\\w#&/])#([A-Za-z][\\w/-]*)")

    /// Every #tag in a card's text (code spans and fenced blocks included; headings need a space, so never match).
    static func tags(in text: String) -> [String] {
        let ns = text as NSString
        var seen: [String] = []
        for match in tagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1))
            if !seen.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { seen.append(tag) }
        }
        return seen
    }
    /// Luhmann-numbered cards in sequence order (Promote → Branch From…).
    let zettels: [LibraryCard]

    static let empty = LibraryIndex(snapshot: LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0), root: nil)

    init(snapshot: LibrarySnapshot, root: URL?) {
        cards = snapshot.cards
        incoming = snapshot.incoming; outgoing = snapshot.outgoing
        var byKey: [String: Int] = [:], byPath: [String: Int] = [:], orders: [String: Double] = [:]
        var modes: [String: KasterMode] = [:], ids: Set<String> = [], byMode: [KasterMode: [LibraryCard]] = [:], byUID: [String: Int] = [:]
        var zoteroCiting: [String: [LibraryCard]] = [:], folderCounts: [String: Int] = [:]
        var tagged: [String: Set<String>] = [:], spelled: [String: String] = [:]
        for (index, card) in snapshot.cards.enumerated() {
            byKey[card.url.standardizedFileURL.path] = byKey[card.url.standardizedFileURL.path] ?? index
            byPath[card.path] = byPath[card.path] ?? index
            var folder = (card.path as NSString).deletingLastPathComponent
            while !folder.isEmpty { folderCounts[folder, default: 0] += 1; folder = (folder as NSString).deletingLastPathComponent }
            for tag in Self.tags(in: card.content) {
                let key = tag.lowercased()
                tagged[key, default: []].insert(card.path)
                if spelled[key] == nil { spelled[key] = tag }
            }
            let header = KasterFrontmatter.fields(in: card.content)
            if let order = header["order"].flatMap(Double.init) { orders[card.path] = order }
            if let uid = header["uid"] { byUID[uid] = byUID[uid] ?? index }
            if let key = header["zotero"] {
                zoteroCiting[(header["zotero-library"] ?? "personal") + "/" + key, default: []].append(card)
            }
            // The card's relative path already names its type folder; avoid resolving paths per card.
            let first = card.path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            let metadataID = CardMetadata.parse(card.content).id
            let mode = card.path.contains("/") ? (KasterMode.allCases.first { $0.folder.caseInsensitiveCompare(first) == .orderedSame }
                ?? (metadataID.map(LuhmannIDs.isLuhmann) == true ? .zettel : .quick)) : (metadataID.map(LuhmannIDs.isLuhmann) == true ? .zettel : .quick)
            modes[card.path] = mode
            byMode[mode, default: []].append(card)
            if let id = metadataID { ids.insert(id) }
            if let id = BranchIDs.filenameID(for: card.url), id.caseInsensitiveCompare(metadataID ?? "") != .orderedSame { ids.insert(id) }
            else if metadataID == nil, let id = BranchIDs.luhmannFilenameID(for: card.url) { ids.insert(id) }
            if let id = BranchIDs.debateFilenameID(for: card.url), id.caseInsensitiveCompare(metadataID ?? "") != .orderedSame { ids.insert(id) }
        }
        self.byKey = byKey; self.byPath = byPath; self.orders = orders; self.modes = modes; self.ids = ids; self.byUID = byUID; self.zoteroCiting = zoteroCiting; self.folderCounts = folderCounts
        self.tagged = tagged
        tags = tagged.map { (name: spelled[$0.key] ?? $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        zettels = snapshot.cards.filter { $0.cardID.map(LuhmannIDs.isLuhmann) ?? false }
            .sorted { ($0.cardID ?? "").localizedStandardCompare($1.cardID ?? "") == .orderedAscending }
        self.byMode = byMode.mapValues { $0.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    }

    func card(for url: URL?) -> LibraryCard? {
        guard let url else { return nil }
        if let index = byKey[url.standardizedFileURL.path] { return cards[index] }
        if let index = byKey[url.resolvingSymlinksInPath().standardizedFileURL.path] { return cards[index] }
        return nil
    }
    func card(path: String) -> LibraryCard? { byPath[path].map { cards[$0] } }
    func count(inFolder path: String) -> Int { folderCounts[path] ?? 0 }

    /// The card a [[link]] points to: an exact path, or a file name only one card has.
    func resolve(link raw: String) -> LibraryCard? {
        var target = String(raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
        target = String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]).trimmingCharacters(in: .whitespaces)
        if target.lowercased().hasSuffix(".md") { target = String(target.dropLast(3)) }
        if let exact = card(path: target) { return exact }
        let lowered = target.lowercased()
        if target.contains("/") { return cards.first { $0.path.lowercased() == lowered } }
        let named = cards.filter { ($0.path as NSString).lastPathComponent.lowercased() == lowered }
        return named.count == 1 ? named[0] : nil
    }

    /// Cards carrying every one of these tags (case-insensitive).
    func cards(taggedWithAll names: [String]) -> [LibraryCard] {
        guard let first = names.first else { return cards }
        var paths = tagged[first.lowercased()] ?? []
        for name in names.dropFirst() { paths.formIntersection(tagged[name.lowercased()] ?? []) }
        return cards.filter { paths.contains($0.path) }
    }

    /// Sidebar search: "#tag" words must all be on the card; other words search its text.
    func search(_ query: String) -> [LibraryCard] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let tagWords = words.filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
        let text = words.filter { !($0.hasPrefix("#") && $0.count > 1) }.joined(separator: " ")
        return cards(taggedWithAll: tagWords).filter { LibrarySearch.matches($0, query: text) }
    }
    func card(uid: String) -> LibraryCard? { byUID[uid].map { cards[$0] } }
    func cards(citingZotero key: String, library: String = "personal") -> [LibraryCard] { zoteroCiting[library + "/" + key] ?? [] }

    private func related(_ paths: [String]?) -> [LibraryCard] {
        Array(Set(paths ?? [])).compactMap { card(path: $0) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func backlinks(for url: URL?) -> [LibraryCard] { card(for: url).map { related(incoming[$0.path]) } ?? [] }
    func outgoing(for url: URL?) -> [LibraryCard] { card(for: url).map { related(outgoing[$0.path]) } ?? [] }

    /// Cards of one type, by title.
    func cards(in mode: KasterMode) -> [LibraryCard] { byMode[mode] ?? [] }
    func mode(of card: LibraryCard) -> KasterMode { modes[card.path] ?? .quick }

    /// Manual order from each card's `order:` field; unordered cards follow by ID, then title.
    func sortedByOrder(_ list: [LibraryCard]) -> [LibraryCard] {
        list.sorted { a, b in
            switch (orders[a.path], orders[b.path]) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.cardID ?? "~" + a.title).localizedStandardCompare(b.cardID ?? "~" + b.title) == .orderedAscending
            }
        }
    }
}
