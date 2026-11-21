import Foundation

struct CardLink {
    let range: NSRange
    let labelRange: NSRange
    let target: CardLinkTarget
}

// Locations are UTF-16 offsets, matching NSTextView and NSRegularExpression.
enum CardLinkParser {
    static func links(in text: String) -> [CardLink] {
        let source = text as NSString
        let length = source.length
        var results: [CardLink] = []
        var lineStart = 0
        var fence: (marker: unichar, count: Int)?
        func unit(_ index: Int) -> unichar { source.character(at: index) }
        func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        func find(_ needle: String, from: Int, end: Int) -> NSRange {
            guard from < end else { return NSRange(location: NSNotFound, length: 0) }
            return source.range(of: needle, options: [], range: NSRange(location: from, length: end - from))
        }
        while lineStart < length {
            let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
            let end = NSMaxRange(lineRange)
            var first = lineStart
            while first < end && unit(first) == 32 && first - lineStart < 4 { first += 1 }
            if first - lineStart <= 3, first < end, unit(first) == 96 || unit(first) == 126 {
                let marker = unit(first)
                var after = first
                while after < end && unit(after) == marker { after += 1 }
                let count = after - first
                if count >= 3 {
                    if let open = fence {
                        if open.marker == marker && count >= open.count {
                            let rest = source.substring(with: NSRange(location: after, length: end - after))
                            if rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fence = nil }
                        }
                    } else { fence = (marker, count) }
                    lineStart = end; continue
                }
            }
            if fence != nil { lineStart = end; continue }
            // Markdown treats four leading spaces or a tab as an indented code block.
            if first - lineStart >= 4 || (lineStart < end && unit(lineStart) == 9) { lineStart = end; continue }
            var i = lineStart
            while i < end {
                let ch = unit(i)
                if ch == 92 { i = min(i + 2, end); continue }
                if ch == 96 {
                    var after = i
                    while after < end && unit(after) == 96 { after += 1 }
                    let ticks = source.substring(with: NSRange(location: i, length: after - i))
                    let closing = find(ticks, from: after, end: end)
                    if closing.location != NSNotFound { i = NSMaxRange(closing); continue }
                    i = after; continue
                }
                if ch == 91 {
                    let embedded = i > lineStart && unit(i - 1) == 33
                    if i + 1 < end && unit(i + 1) == 91 {
                        let close = find("]]", from: i + 2, end: end)
                        if close.location != NSNotFound && close.location > i + 2 {
                            let inside = NSRange(location: i + 2, length: close.location - i - 2)
                            let raw = source.substring(with: inside)
                            let pipe = (raw as NSString).range(of: "|")
                            let label = pipe.location == NSNotFound ? inside : NSRange(location: inside.location + pipe.location + 1, length: inside.length - pipe.location - 1)
                            let full = NSRange(location: i, length: NSMaxRange(close) - i)
                            if !embedded { results.append(CardLink(range: full, labelRange: label, target: .wiki(raw))) }
                            i = NSMaxRange(close); continue
                        }
                    } else {
                        var labelEnd = i + 1
                        while labelEnd < end && unit(labelEnd) != 93 {
                            if unit(labelEnd) == 92 && labelEnd + 1 < end { labelEnd += 1 }
                            labelEnd += 1
                        }
                        if labelEnd > i + 1 && labelEnd + 1 < end && unit(labelEnd) == 93 && unit(labelEnd + 1) == 40 {
                            var j = labelEnd + 2
                            while j < end && (unit(j) == 32 || unit(j) == 9) { j += 1 }
                            let angle = j < end && unit(j) == 60
                            let targetStart = angle ? j + 1 : j
                            if angle { j += 1 }
                            var depth = 0
                            while j < end {
                                let c = unit(j)
                                if c == 92 && j + 1 < end { j += 2; continue }
                                if angle && c == 62 { break }
                                if !angle {
                                    if c == 40 { depth += 1 }
                                    if c == 41 { if depth == 0 { break }; depth -= 1 }
                                    if isSpace(c) { break }
                                }
                                j += 1
                            }
                            let targetEnd = j
                            if angle && j < end && unit(j) == 62 { j += 1 }
                            while j < end && (unit(j) == 32 || unit(j) == 9) { j += 1 }
                            if j < end && (unit(j) == 34 || unit(j) == 39) {
                                let quote = unit(j); j += 1
                                while j < end && unit(j) != quote { if unit(j) == 92 && j + 1 < end { j += 1 }; j += 1 }
                                if j < end { j += 1 }
                                while j < end && (unit(j) == 32 || unit(j) == 9) { j += 1 }
                            }
                            if targetEnd > targetStart && j < end && unit(j) == 41 {
                                let full = NSRange(location: i, length: j + 1 - i)
                                let label = NSRange(location: i + 1, length: labelEnd - i - 1)
                                let target = source.substring(with: NSRange(location: targetStart, length: targetEnd - targetStart))
                                if !embedded { results.append(CardLink(range: full, labelRange: label, target: .url(target))) }
                                i = j + 1; continue
                            }
                        }
                    }
                }
                let prefix = ["https://", "http://", "zotero://"].first { value in
                    let n = (value as NSString).length
                    return i + n <= end && source.substring(with: NSRange(location: i, length: n)).lowercased() == value
                }
                let precedingIsWord: Bool = i > lineStart && UnicodeScalar(UInt32(unit(i - 1))).map { CharacterSet.alphanumerics.contains($0) } == true
                if prefix != nil && !precedingIsWord {
                    var j = i, depth = 0, brackets = 0
                    while j < end {
                        let c = unit(j)
                        if isSpace(c) || c == 60 || c == 62 || c == 34 || c == 39 { break }
                        if c == 40 { depth += 1 }
                        if c == 41 { if depth == 0 { break }; depth -= 1 }
                        if c == 91 { brackets += 1 }
                        if c == 93 { if brackets == 0 { break }; brackets -= 1 }
                        j += 1
                    }
                    while j > i && [46, 44, 59, 33, 63].contains(Int(unit(j - 1))) { j -= 1 }
                    if j > i {
                        let range = NSRange(location: i, length: j - i)
                        results.append(CardLink(range: range, labelRange: range, target: .url(source.substring(with: range))))
                        i = j; continue
                    }
                }
                i += 1
            }
            lineStart = end
        }
        return results
    }
    static func link(in text: String, atUTF16 index: Int) -> CardLink? {
        links(in: text).first { NSLocationInRange(index, $0.range) }
    }
}
