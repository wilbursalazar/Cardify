import SwiftUI
import AppKit
import CoreText

struct HabitRow: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var checked = Array(repeating: false, count: 7)
}

struct HabitTracker: Codable {
    var title = "Weekly habits"
    var rows: [HabitRow] = [HabitRow()]
    static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private enum CodingKeys: String, CodingKey { case title, rows }
    init(title: String = "Weekly habits", rows: [HabitRow] = [HabitRow()]) { self.title = title; self.rows = rows }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Weekly habits"
        rows = try values.decode([HabitRow].self, forKey: .rows)
    }

    var markdown: String {
        func cell(_ value: String) -> String {
            value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "|", with: "\\|")
        }
        let heading = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["# " + (heading.isEmpty ? "Weekly habits" : heading), "", "| Habit | " + Self.days.joined(separator: " | ") + " |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for row in rows {
            let cells = (0..<7).map { $0 < row.checked.count && row.checked[$0] ? "X" : "" }
            lines.append("| " + cell(row.name) + " | " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // Accept only Cardify's exact weekly table shape, so unrelated Markdown isn't silently converted.
    static func fromMarkdown(_ text: String) -> HabitTracker? {
        func cells(_ line: String) -> [String]? {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.first == "|", trimmed.last == "|", trimmed.count >= 2 else { return nil }
            var result: [String] = [], part = "", escaped = false
            for character in trimmed.dropFirst().dropLast() {
                if escaped {
                    if character != "|" && character != "\\" { part.append("\\") }
                    part.append(character); escaped = false
                } else if character == "\\" { escaped = true }
                else if character == "|" { result.append(part.trimmingCharacters(in: .whitespaces)); part = "" }
                else { part.append(character) }
            }
            if escaped { part.append("\\") }
            result.append(part.trimmingCharacters(in: .whitespaces))
            return result
        }
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 3, lines[0].trimmingCharacters(in: .whitespaces).hasPrefix("# "),
              cells(lines[1]) == ["Habit"] + days,
              let separator = cells(lines[2]), separator.count == 8,
              separator.allSatisfy({ $0 == "---" }) else { return nil }
        var rows: [HabitRow] = []
        for line in lines.dropFirst(3) {
            guard let fields = cells(line), fields.count == 8,
                  fields.dropFirst().allSatisfy({ $0.isEmpty || $0.lowercased() == "x" }) else { return nil }
            rows.append(HabitRow(name: fields[0], checked: fields.dropFirst().map { !$0.isEmpty }))
        }
        let title = String(lines[0].trimmingCharacters(in: .whitespaces).dropFirst(2))
        return HabitTracker(title: title, rows: rows)
    }

    func pdf(portrait: Bool, dotGrid: Bool = false) -> Data? {
        let size = portrait ? CGSize(width: 216, height: 360) : CGSize(width: 360, height: 216)
        let inset: CGFloat = 27
        let body = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let cellWidth = min(24, max(14, floor(body.width * 0.48 / 7)))
        let gridX = body.maxX - 7 * cellWidth
        let nameWidth = gridX - body.minX
        let headerHeight: CGFloat = 16
        let heading = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = NSAttributedString(string: heading.isEmpty ? "Weekly habits" : heading, attributes: [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: NSColor.black])
        let titleSetter = CTFramesetterCreateWithAttributedString(titleText)
        let titleHeight = ceil(CTFramesetterSuggestFrameSizeWithConstraints(titleSetter, CFRange(location: 0, length: 0), nil, CGSize(width: body.width, height: .greatestFiniteMagnitude), nil).height) + 2
        let topHeight = max(24, titleHeight + 10)
        let maximumRowHeight = body.height - topHeight - headerHeight
        guard maximumRowHeight >= 17 else { return nil }
        let textFont = NSFont.systemFont(ofSize: 8)
        let attrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.black]
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var media = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }

        func line(_ text: String, x: CGFloat, y: CGFloat, font: NSFont) {
            let a = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
            let ct = CTLineCreateWithAttributedString(a)
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(ct, context)
        }
        func startPage() -> CGFloat {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor); context.fill(media)
            context.saveGState(); context.clip(to: body)
            if dotGrid {
                context.setFillColor(NSColor(calibratedWhite: 0.83, alpha: 1).cgColor)
                var x = body.minX + 6
                while x < body.maxX {
                    var y = body.minY + 6
                    while y < body.maxY { context.fillEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)); y += 12 }
                    x += 12
                }
            }
            let titleFrame = CTFramesetterCreateFrame(titleSetter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: body.minX, y: body.maxY - 4 - titleHeight, width: body.width, height: titleHeight), transform: nil), nil)
            CTFrameDraw(titleFrame, context)
            let top = body.maxY - topHeight
            context.setStrokeColor(NSColor.black.cgColor); context.setLineWidth(0.5)
            for i in 0..<7 {
                let rect = CGRect(x: gridX + CGFloat(i) * cellWidth, y: top - headerHeight, width: cellWidth, height: headerHeight)
                context.stroke(rect)
                let day = Self.days[i]
                let dayFont = NSFont.systemFont(ofSize: 6.5, weight: .medium)
                let w = (day as NSString).size(withAttributes: [.font: dayFont]).width
                line(day, x: rect.midX - w / 2, y: rect.midY - 2.3, font: dayFont)
            }
            return top - headerHeight
        }
        func endPage() { context.restoreGState(); context.endPDFPage() }

        var top = startPage()
        for row in rows {
            let rawName = row.name.replacingOccurrences(of: "\n", with: " ")
            let label = NSAttributedString(string: rawName.isEmpty ? " " : rawName, attributes: attrs)
            let setter = CTFramesetterCreateWithAttributedString(label)
            var location = 0
            repeat {
                let available = top - body.minY
                let remaining = CFRange(location: location, length: 0)
                let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, remaining, nil, CGSize(width: nameWidth - 8, height: .greatestFiniteMagnitude), nil)
                let desiredHeight = max(17, ceil(suggested.height) + 5)
                if desiredHeight <= maximumRowHeight && desiredHeight > available + 0.01 {
                    endPage(); top = startPage(); continue
                }
                let rowHeight = min(desiredHeight, top - body.minY)
                if rowHeight < 17 { endPage(); top = startPage(); continue }
                let rect = CGRect(x: body.minX, y: top - rowHeight, width: nameWidth, height: rowHeight)
                let textRect = rect.insetBy(dx: 4, dy: 2)
                let frame = CTFramesetterCreateFrame(setter, remaining, CGPath(rect: textRect, transform: nil), nil)
                let count = CTFrameGetVisibleStringRange(frame).length
                guard count > 0 else { endPage(); context.closePDF(); return nil }
                CTFrameDraw(frame, context)
                context.setStrokeColor(NSColor.black.cgColor); context.setLineWidth(0.5)
                for i in 0..<7 {
                    let box = CGRect(x: gridX + CGFloat(i) * cellWidth, y: top - rowHeight, width: cellWidth, height: rowHeight)
                    context.stroke(box)
                    if i < row.checked.count && row.checked[i] {
                        let d = min(cellWidth, rowHeight) * 0.22
                        context.move(to: CGPoint(x: box.midX - d, y: box.midY - d)); context.addLine(to: CGPoint(x: box.midX + d, y: box.midY + d))
                        context.move(to: CGPoint(x: box.midX - d, y: box.midY + d)); context.addLine(to: CGPoint(x: box.midX + d, y: box.midY - d)); context.strokePath()
                    }
                }
                location += count
                top -= rowHeight
                if location < label.length { endPage(); top = startPage() }
            } while location < label.length
        }
        endPage(); context.closePDF()
        return data as Data
    }
}

struct HabitTrackerEditor: View {
    @Binding var tracker: HabitTracker
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Weekly habits", text: $tracker.title).font(.headline).textFieldStyle(.roundedBorder)
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        Text("Habit").frame(width: 140, alignment: .leading)
                        ForEach(HabitTracker.days, id: \.self) { day in Text(day).font(.caption).frame(width: 28) }
                        Text("").frame(width: 24)
                    }
                    ForEach($tracker.rows) { $row in
                        HStack(spacing: 3) {
                            TextField("Name", text: $row.name).frame(width: 140)
                            ForEach(0..<7, id: \.self) { i in
                                Button { row.checked[i].toggle() } label: {
                                    Text(row.checked[i] ? "X" : " ").font(.system(size: 12, weight: .medium)).frame(width: 26, height: 26).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary)).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("\(HabitTracker.days[i]): \(row.checked[i] ? "Done" : "Not done")")
                            }
                            Button { tracker.rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Remove habit")
                        }
                    }
                }
            }
            Button("Add habit") { tracker.rows.append(HabitRow()) }
            Text("Click a box to mark or clear an X. Printed cards can also be filled in by hand.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
