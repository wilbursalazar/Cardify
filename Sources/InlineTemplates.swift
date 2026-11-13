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
        let lines = MarkdownSource.lines(in: existing)
        let source = lines.source
        var offset = max(lines.bomLength, min(location, source.length))
        // Keep YAML frontmatter at the beginning of the document.
        if lines.hasFrontmatterStart {
            guard let end = lines.frontmatterEnd else { return (existing, offset) }
            offset = max(offset, NSMaxRange(lines.values[end].full))
        }
        let prefix = source.substring(to: offset)
        let suffix = source.substring(from: offset)
        let newline = lines.newline
        let template = markdown.replacingOccurrences(of: "\n", with: newline)
        let hasBlankLine = prefix.hasSuffix("\n\n") || prefix.hasSuffix("\r\n\r\n") || prefix.hasSuffix("\r\r")
        let endsLine = prefix.hasSuffix("\n") || prefix.hasSuffix("\r")
        let startsLine = suffix.hasPrefix("\n") || suffix.hasPrefix("\r")
        let separatorBefore = prefix.isEmpty || hasBlankLine ? "" : endsLine ? newline : newline + newline
        let separatorAfter = suffix.isEmpty || startsLine || template.hasSuffix(newline) ? "" : newline + newline
        let inserted = separatorBefore + template + separatorAfter
        return (prefix + inserted + suffix, offset + (inserted as NSString).length)
    }
}
