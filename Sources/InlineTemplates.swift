import Foundation

// Templates are plain Markdown so the regular editor remains the source of truth.
enum InlineTemplate: String, CaseIterable, Identifiable {
    case idea = "Idea"
    case reading = "Reading"
    case index = "Index"
    var id: String { rawValue }

    var markdown: String {
        switch self {
        case .idea:
            return "# Idea\n\n\n\n## Related cards\n\n"
        case .reading:
            return "# Reading note\n\n## Quotation or summary\n\n\n\n## My response\n\n\n\nSource: \n\n## Related cards\n\n"
        case .index:
            return "# Index\n\n\n\n## Related cards\n\n- "
        }
    }

    // Insert without overwriting the current selection, existing note or metadata.
    // `location` is an NSString/NSRange (UTF-16) offset, as used by NSTextView.
    func inserting(in existing: String, at location: Int) -> (text: String, cursor: Int) {
        let source = existing as NSString
        var offset = max(0, min(location, source.length))
        // Keep YAML frontmatter at the beginning of the document.
        if let pattern = try? NSRegularExpression(pattern: #"\A---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)"#),
           let match = pattern.firstMatch(in: existing, range: NSRange(location: 0, length: source.length)) {
            offset = max(offset, NSMaxRange(match.range))
        }
        let prefix = source.substring(to: offset)
        let suffix = source.substring(from: offset)
        let separatorBefore = prefix.isEmpty || prefix.hasSuffix("\n\n") ? "" : prefix.hasSuffix("\n") ? "\n" : "\n\n"
        let separatorAfter = suffix.isEmpty || suffix.hasPrefix("\n") || markdown.hasSuffix("\n") ? "" : "\n\n"
        let inserted = separatorBefore + markdown + separatorAfter
        return (prefix + inserted + suffix, offset + (inserted as NSString).length)
    }
}
