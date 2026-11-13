import AppKit
import Foundation

// Converts the supported Markdown syntax into the same attributed text used for
// both the PDF preview and printing. The original Markdown is never changed.
enum MarkdownRendering {
    static func render(_ markdown: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let lines = markdown.components(separatedBy: "\n").filter {
            !$0.hasPrefix("Zotero: [Open source](zotero://select/")
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5

        for (index, line) in lines.enumerated() {
            var body = line
            var size = fontSize
            var heading = false
            var prefix = ""
            if let match = body.range(of: #"^\s{0,3}#{1,6}\s+"#, options: .regularExpression) {
                let level = body[match].filter { $0 == "#" }.count
                size = fontSize * (level == 1 ? 1.30 : level == 2 ? 1.16 : 1.05)
                heading = true
                body.removeSubrange(match)
            } else if let match = body.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) {
                let marker = String(body[match])
                prefix = marker.contains("[ ]") ? "☐ " : "☑ "
                body.removeSubrange(match)
            } else if let match = body.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) {
                prefix = "• "
                body.removeSubrange(match)
            }
            let baseFont = heading ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraph
            ]
            if !prefix.isEmpty { result.append(NSAttributedString(string: prefix, attributes: attributes)) }
            appendInline(body, baseFont: baseFont, attributes: attributes, to: result)
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
        }
        return result.length == 0 ? NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: fontSize)]) : result
    }

    private static func appendInline(_ source: String, baseFont: NSFont, attributes: [NSAttributedString.Key: Any], to result: NSMutableAttributedString) {
        // Turn Obsidian links into temporary Markdown links so the parser can
        // handle link labels inside bold/italic spans as well as ordinary links.
        var markdown = source
        let pattern = try! NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
        let matches = pattern.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: markdown), let inside = Range(match.range(at: 1), in: markdown) else { continue }
            let parts = markdown[inside].split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let label = String(parts.last ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            markdown.replaceSubrange(whole, with: "[\(label)](https://cardify.invalid/)")
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
            if run.link != nil { runAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if intent.contains(.strikethrough) { runAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: content, attributes: runAttributes))
        }
    }
}
