import Foundation
import AppKit
import CoreText
import PDFKit

// Encoded internal actions are attached only to the in-app preview PDF.
enum CardPreviewLinks {
    static let attribute = NSAttributedString.Key("CardifyPreviewLink")

    struct Hit {
        let page: Int
        let bounds: CGRect
        let action: URL
    }

    static func action(for target: CardLinkTarget) -> URL? {
        let type: String
        let value: String
        switch target {
        case .wiki(let raw): type = "wiki"; value = raw
        case .url(let raw): type = "url"; value = raw
        }
        let encoded = Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        guard !encoded.isEmpty else { return nil }
        return URL(string: "cardify-preview://\(type)/\(encoded)")
    }

    static func target(from action: URL) -> CardLinkTarget? {
        guard action.scheme?.lowercased() == "cardify-preview", let type = action.host?.lowercased() else { return nil }
        let encoded = action.path.dropFirst().replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = encoded + String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        switch type {
        case "wiki": return .wiki(value)
        case "url": return .url(value)
        default: return nil
        }
    }

    // Run positions are relative to the line baseline. Keep separate rectangles
    // for wrapped lines and styled runs so each hit opens its exact destination.
    static func collect(line: CTLine, origin: CGPoint, page: Int, into hits: inout [Hit]) {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let raw = attributes[attribute.rawValue] as? String, let action = URL(string: raw), target(from: action) != nil else { continue }
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            var left = CGFloat.greatestFiniteMagnitude, right = -CGFloat.greatestFiniteMagnitude
            for index in 0..<count {
                left = min(left, positions[index].x, positions[index].x + advances[index].width)
                right = max(right, positions[index].x, positions[index].x + advances[index].width)
            }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
            guard left.isFinite, right.isFinite, right > left, ascent + descent > 0 else { continue }
            hits.append(Hit(page: page, bounds: CGRect(x: origin.x + left, y: origin.y - descent, width: right - left, height: ascent + descent), action: action))
        }
    }

    static func collect(frame: CTFrame, page: Int, into hits: inout [Hit]) {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let offset = CTFrameGetPath(frame).boundingBoxOfPath.origin
        for index in lines.indices {
            collect(line: lines[index], origin: CGPoint(x: offset.x + origins[index].x, y: offset.y + origins[index].y), page: page, into: &hits)
        }
    }

    static func add(to data: Data, hits: [Hit]) -> Data? {
        guard let document = PDFDocument(data: data) else { return nil }
        for hit in hits {
            guard let page = document.page(at: hit.page) else { continue }
            let bounds = hit.bounds.intersection(page.bounds(for: .mediaBox))
            guard !bounds.isNull, !bounds.isEmpty else { continue }
            let annotation = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
            annotation.action = PDFActionURL(url: hit.action)
            annotation.color = .clear
            let border = PDFBorder(); border.lineWidth = 0; annotation.border = border
            page.addAnnotation(annotation)
        }
        return document.dataRepresentation()
    }
}
