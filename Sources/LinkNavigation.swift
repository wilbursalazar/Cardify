import Foundation

enum CardLinkTarget: Equatable {
    case wiki(String)
    case url(String)
}

enum CardLinkResolution: Equatable {
    case note(URL, fragment: String?)
    case current(fragment: String)
    case external(URL)
    case failure(String)
}

// Read-only resolution. The caller performs any save prompt or app launch.
enum CardLinkNavigation {
    static func resolve(_ target: CardLinkTarget, folder: URL?, currentFile: URL?) -> CardLinkResolution {
        switch target {
        case .wiki(let raw):
            let value = String(raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
            return note(value, folder: folder, currentFile: currentFile, relativeToCurrent: false)
        case .url(let raw):
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .failure("The link is empty or invalid.") }
            if let components = URLComponents(string: value), let scheme = components.scheme?.lowercased() {
                guard ["http", "https", "zotero"].contains(scheme), let url = components.url else { return .failure("This link type is not supported.") }
                if scheme == "zotero" {
                    guard components.host?.lowercased() == "select" else { return .failure("This Zotero link is not supported.") }
                } else {
                    guard let host = components.host, !host.isEmpty else { return .failure("This web link is invalid.") }
                }
                return .external(url)
            }
            // A relative Markdown link may point to another note, or to a heading
            // in the current note. Other relative paths are not opened as files.
            let pieces = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            guard let path = String(pieces[0]).removingPercentEncoding,
                  let fragment = pieces.count == 2 ? String(pieces[1]).removingPercentEncoding : "" else { return .failure("The note link is invalid.") }
            guard path.isEmpty || (path as NSString).pathExtension.lowercased() == "md" else { return .failure("Only Markdown note links can be opened in Cardify.") }
            return note(path + (pieces.count == 2 ? "#" + fragment : ""), folder: folder, currentFile: currentFile, relativeToCurrent: true)
        }
    }

    private struct Candidate {
        let path: String
        let url: URL
    }

    private static func note(_ raw: String, folder: URL?, currentFile: URL?, relativeToCurrent: Bool) -> CardLinkResolution {
        let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var path = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let fragment = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if let fragment, fragment.isEmpty { return .failure("The linked heading is empty.") }
        if let fragment, fragment.hasPrefix("^") { return .failure("Block links are not supported yet.") }
        if path.isEmpty {
            guard let fragment else { return .failure("The note link is empty.") }
            return .current(fragment: fragment)
        }
        guard let folder else { return .failure("Choose a notes folder before opening a note link.") }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .failure("This note path is not supported.") }
        if (path as NSString).pathExtension.lowercased() == "md" { path = String(path.dropLast(3)) }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let containsParent = components.contains("..")
        guard (!containsParent || relativeToCurrent), !components.contains(where: { $0.isEmpty }) else { return .failure("This note path is not supported.") }
        let hasExplicitRelative = components.first == "."
        if hasExplicitRelative { path = components.dropFirst().joined(separator: "/") }
        guard !path.isEmpty else { return .failure("The note link is empty.") }
        let candidates: [Candidate]
        do { candidates = try scan(root: root) }
        catch { return .failure("Could not read the complete notes folder.") }
        let byPath: (String) -> [Candidate] = { target in candidates.filter { $0.path.caseInsensitiveCompare(target) == .orderedSame } }
        var matches: [Candidate] = []
        if (relativeToCurrent || hasExplicitRelative), let currentFile {
            let currentParent = currentFile.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if currentParent.path == root.path || currentParent.path.hasPrefix(prefix) {
                let destination = currentParent.appendingPathComponent(path).standardizedFileURL.path
                guard destination.hasPrefix(prefix) else { return .failure("This note path leaves the selected notes folder.") }
                matches = byPath(String(destination.dropFirst(prefix.count)))
            } else if containsParent { return .failure("The current note is outside the selected notes folder.") }
        } else if containsParent {
            return .failure("Open a note in the selected folder before following this relative link.")
        }
        if matches.isEmpty && !hasExplicitRelative && !containsParent {
            if path.contains("/") { matches = byPath(path) }
            else { matches = candidates.filter { ($0.path as NSString).lastPathComponent.caseInsensitiveCompare(path) == .orderedSame } }
        }
        guard matches.count == 1, let result = matches.first else {
            return .failure(matches.isEmpty ? "The linked note was not found." : "More than one note matches this link. Use a folder path to disambiguate it.")
        }
        let resolved = result.url.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(prefix), (try? result.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              FileManager.default.isReadableFile(atPath: resolved.path) else { return .failure("The linked note cannot be read safely.") }
        return .note(resolved, fragment: fragment)
    }

    private static func scan(root: URL) throws -> [Candidate] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        var failed = false
        guard manager.isReadableFile(atPath: root.path), let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failed = true; return false }) else { throw CocoaError(.fileReadNoPermission) }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var candidates: [Candidate] = []
        for case let url as URL in enumerator {
            let properties = try url.resourceValues(forKeys: keys)
            guard properties.isSymbolicLink != true, properties.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            candidates.append(Candidate(path: String(relative.dropLast(url.pathExtension.count + 1)), url: url))
        }
        if failed { throw CocoaError(.fileReadNoPermission) }
        return candidates
    }

    // Return the UTF-16 range of a Markdown ATX heading, excluding fenced code.
    // A nil result means the heading could not be located; never silently fall back.
    static func headingRange(_ fragment: String, in text: String) -> NSRange? {
        let target = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !target.hasPrefix("^") else { return nil }
        let source = text as NSString
        let heading = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}[ \t]+(.+?)[ \t]*#*[ \t]*$"#)
        var location = 0, fence: String?
        // Skip a conventional YAML header so comments in metadata are not
        // mistaken for headings in the note body.
        if source.length > 0 {
            let first = source.lineRange(for: NSRange(location: 0, length: 0))
            if source.substring(with: first).trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                let mapping = try! NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_. -]*:[ \t]*(?:.*)$"#)
                var cursor = NSMaxRange(first), sawMapping = false
                while cursor < source.length {
                    let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
                    let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
                    if line.trimmingCharacters(in: .whitespaces) == "---" {
                        if sawMapping { location = NSMaxRange(lineRange) }
                        break
                    }
                    if mapping.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil { sawMapping = true }
                    cursor = NSMaxRange(lineRange)
                }
            }
        }
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
            } else if fence == nil, let match = heading.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
                      let range = Range(match.range(at: 1), in: line) {
                let name = String(line[range]).trimmingCharacters(in: .whitespaces)
                if name.compare(target, options: [.caseInsensitive]) == .orderedSame {
                    return NSRange(location: lineRange.location + match.range(at: 1).location, length: match.range(at: 1).length)
                }
            }
            location = NSMaxRange(lineRange)
        }
        return nil
    }
}
