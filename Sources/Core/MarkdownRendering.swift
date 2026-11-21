import AppKit
import Foundation

// Converts the supported Markdown syntax into the same attributed text used for
// both the PDF preview and printing. The original Markdown is never changed.
enum MarkdownRendering {
    static func render(_ markdown: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let sourceLines = markdown.components(separatedBy: "\n")
        let recognizedLinks = CardLinkParser.links(in: markdown)
        var offset = 0
        var fence: (Character, Int)?
        var htmlComment = false
        var lines: [(text: String, offset: Int, links: [CardLink])] = []
        for (lineIndex, originalLine) in sourceLines.enumerated() {
            // Strip only the CR belonging to a CRLF line ending for rendering.
            // Keep the original UTF-16 length when advancing source offsets so
            // link annotations still point to the correct Markdown characters.
            let line = lineIndex < sourceLines.count - 1 && originalLine.hasSuffix("\r") ? String(originalLine.dropLast()) : originalLine
            let count = (line as NSString).length
            let links = recognizedLinks.filter { $0.range.location >= offset && NSMaxRange($0.range) <= offset + count }
            let trimmed = line.drop(while: { $0 == " " })
            let indentation = line.count - trimmed.count
            if !htmlComment, indentation <= 3, let marker = trimmed.first, marker == "`" || marker == "~" {
                let count = trimmed.prefix(while: { $0 == marker }).count
                if count >= 3 {
                    if let open = fence {
                        if open.0 == marker && count >= open.1 && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    } else { fence = (marker, count) }
                }
            }
            let markerLine = lineIndex == 0 && line.hasPrefix("\u{FEFF}") ? String(line.dropFirst()) : line
            let debateMarker = fence == nil && !htmlComment && ["<!-- cardify:debate=project -->", "<!-- cardify:debate=aff -->", "<!-- cardify:debate=def -->", "<!-- cardify:debate=evidence -->", "<!-- cardify:debate=objection -->", "<!-- cardify:debate=argument -->", "<!-- cardify:debate=reply -->", "<!-- cardify:stance=supports -->", "<!-- cardify:stance=challenges -->"].contains(markerLine)
            if fence == nil && !debateMarker {
                var cursor = line.startIndex
                while cursor < line.endIndex {
                    let marker = htmlComment ? "-->" : "<!--"
                    guard let range = line.range(of: marker, range: cursor..<line.endIndex) else { break }
                    htmlComment.toggle(); cursor = range.upperBound
                }
            }
            if !debateMarker && !line.hasPrefix("Zotero: [Open source](zotero://select/") { lines.append((line, offset, links)) }
            offset += (originalLine as NSString).length + 1
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5

        for (index, entry) in lines.enumerated() {
            var body = entry.text
            var size = fontSize
            var heading = false
            var prefix = ""
            var bodyOffset = entry.offset
            if let match = body.range(of: #"^\s{0,3}#{1,6}\s+"#, options: .regularExpression) {
                let level = body[match].filter { $0 == "#" }.count
                size = fontSize * (level == 1 ? 1.30 : level == 2 ? 1.16 : 1.05)
                heading = true
                bodyOffset += (String(body[match]) as NSString).length
                body.removeSubrange(match)
            } else if let match = body.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) {
                let marker = String(body[match])
                prefix = marker.contains("[ ]") ? "☐ " : "☑ "
                bodyOffset += (marker as NSString).length
                body.removeSubrange(match)
            } else if let match = body.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) {
                bodyOffset += (String(body[match]) as NSString).length
                prefix = "• "
                body.removeSubrange(match)
            }
            let baseFont = heading ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraph
            ]
            if !prefix.isEmpty { result.append(NSAttributedString(string: prefix, attributes: attributes)) }
            appendInline(body, baseFont: baseFont, attributes: attributes, links: entry.links, offset: bodyOffset, to: result)
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
        }
        return result.length == 0 ? NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: fontSize)]) : result
    }

    private static func appendInline(_ source: String, baseFont: NSFont, attributes: [NSAttributedString.Key: Any], links: [CardLink], offset: Int, to result: NSMutableAttributedString) {
        // Turn Obsidian links into temporary Markdown links so the parser can
        // handle link labels inside bold/italic spans as well as ordinary links.
        var markdown = source
        let pattern = try! NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
        let matches = pattern.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: markdown), let inside = Range(match.range(at: 1), in: markdown) else { continue }
            let parts = markdown[inside].split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let label = String(parts.last ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            let recognized = links.first { link in
                guard link.range.location == offset + match.range.location else { return false }
                if case .wiki = link.target { return true }
                return false
            }
            let destination = recognized.flatMap { CardPreviewLinks.action(for: $0.target) }?.absoluteString ?? "https://cardify.invalid/"
            markdown.replaceSubrange(whole, with: "[\(label)](\(destination))")
        }
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            result.append(NSAttributedString(string: source, attributes: attributes)); return
        }
        for run in parsed.runs {
            let content = String(parsed[run.range].characters)
            var runAttributes = attributes
            var font = baseFont
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular) }
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            runAttributes[.font] = font
            if let link = run.link {
                runAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if CardPreviewLinks.target(from: link) != nil {
                    runAttributes[CardPreviewLinks.attribute] = link.absoluteString
                } else if let recognized = links.first(where: { candidate in
                    guard case .url(let raw) = candidate.target else { return false }
                    return URL(string: raw)?.absoluteString == link.absoluteString
                }), let action = CardPreviewLinks.action(for: recognized.target) {
                    runAttributes[CardPreviewLinks.attribute] = action.absoluteString
                }
            }
            if intent.contains(.strikethrough) { runAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: content, attributes: runAttributes))
        }
    }
}
