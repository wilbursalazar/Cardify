import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let outlineDragType = UTType(exportedAs: "com.wilbursalazar.cardify.outline-row")

struct OutlineRow: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var depth = 0
}

// Outlines opt in through a marker. Only the supported Markdown subset is
// loaded into the structured editor; anything else stays in Research mode.
struct OutlineDocument: Codable, Equatable {
    static let marker = "<!-- cardify:outline -->"
    var identity = UUID()
    var title = "Outline"
    var rows: [OutlineRow] = [OutlineRow()]
    // Exact YAML/BOM and newline style from an imported outline.
    private var header = ""
    private var newline = "\n"
    private var hasFinalNewline = true

    static func fromMarkdown(_ text: String) -> OutlineDocument? {
        let source = text as NSString
        var newline = "\n"
        for i in 0..<source.length {
            let ch = source.character(at: i)
            if ch == 13 { newline = i + 1 < source.length && source.character(at: i + 1) == 10 ? "\r\n" : "\r"; break }
            if ch == 10 { newline = "\n"; break }
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Refuse mixed line endings rather than normalizing unrelated bytes.
        guard normalized.replacingOccurrences(of: "\n", with: newline) == text else { return nil }
        let bom = normalized.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : ""
        let withoutBOM = bom.isEmpty ? normalized : String(normalized.dropFirst())
        var lines = withoutBOM.components(separatedBy: "\n")
        let trailing = withoutBOM.hasSuffix("\n")
        if trailing { lines.removeLast() }
        func delimiter(_ line: String) -> Bool {
            line.hasPrefix("---") && line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
        }
        var markerIndex = 0
        if let first = lines.first, delimiter(first) {
            guard let end = lines.indices.dropFirst().first(where: { delimiter(lines[$0]) }) else { return nil }
            markerIndex = end + 1
            while markerIndex < lines.count && lines[markerIndex].isEmpty { markerIndex += 1 }
        }
        guard markerIndex + 3 < lines.count,
              lines[markerIndex] == marker, lines[markerIndex + 1].isEmpty,
              lines[markerIndex + 2].hasPrefix("# "), lines[markerIndex + 3].isEmpty else { return nil }
        let headerLines = Array(lines.prefix(markerIndex))
        let header = bom + (headerLines.isEmpty ? "" : headerLines.joined(separator: newline) + newline)
        let title = String(lines[markerIndex + 2].dropFirst(2))
        var rows: [OutlineRow] = []
        for line in lines.dropFirst(markerIndex + 4) {
            let spaces = line.prefix(while: { $0 == " " }).count
            guard spaces % 2 == 0 else { return nil }
            let after = line.dropFirst(spaces)
            guard after.hasPrefix("- ") else { return nil }
            let depth = spaces / 2
            guard rows.isEmpty ? depth == 0 : depth <= rows.last!.depth + 1 else { return nil }
            rows.append(OutlineRow(text: String(after.dropFirst(2)), depth: depth))
        }
        var outline = OutlineDocument()
        outline.title = title; outline.rows = rows; outline.header = header
        outline.newline = newline; outline.hasFinalNewline = trailing
        // Prove the accepted subset is lossless before permitting structured edits.
        guard outline.markdown == text else { return nil }
        return outline
    }

    var markdown: String {
        let body = ([Self.marker, "", "# " + title, ""] + rows.map { String(repeating: "  ", count: $0.depth) + "- " + $0.text }).joined(separator: newline)
        return header + body + (hasFinalNewline ? newline : "")
    }

    // MarkdownRendering flattens nested list markers, so the print-only text
    // uses visible bullets with en-space indentation while the saved file stays
    // ordinary Markdown. Inline links and formatting remain available.
    func printMarkdown(cardID: String?) -> String {
        let lines = ["# " + title, ""] + rows.map { String(repeating: "\u{2002}\u{2002}", count: $0.depth) + "• " + $0.text }
        // The renderer splits on LF; normalize only this print representation.
        let body = lines.joined(separator: "\n") + (hasFinalNewline ? "\n" : "")
        guard let id = cardID, !id.isEmpty, let encoded = try? JSONEncoder().encode(id), let quoted = String(data: encoded, encoding: .utf8) else { return body }
        return "---\ncard_id: \(quoted)\n---\n" + body
    }

    private func subtreeRange(_ id: UUID) -> Range<Int>? {
        guard let start = rows.firstIndex(where: { $0.id == id }) else { return nil }
        var end = start + 1
        while end < rows.count && rows[end].depth > rows[start].depth { end += 1 }
        return start..<end
    }
    func descendantCount(_ id: UUID) -> Int { subtreeRange(id).map { $0.count - 1 } ?? 0 }

    @discardableResult mutating func add(after id: UUID?) -> Bool {
        guard let id else { rows.append(OutlineRow()); return true }
        guard let range = subtreeRange(id) else { return false }
        rows.insert(OutlineRow(depth: rows[range.lowerBound].depth), at: range.upperBound)
        return true
    }
    @discardableResult mutating func removeBranch(_ id: UUID) -> Bool {
        guard let range = subtreeRange(id) else { return false }
        rows.removeSubrange(range); return true
    }
    @discardableResult mutating func indent(_ id: UUID) -> Bool {
        guard let range = subtreeRange(id), range.lowerBound > 0,
              rows[range.lowerBound - 1].depth >= rows[range.lowerBound].depth else { return false }
        for i in range { rows[i].depth += 1 }
        return true
    }
    @discardableResult mutating func outdent(_ id: UUID) -> Bool {
        guard let range = subtreeRange(id), rows[range.lowerBound].depth > 0 else { return false }
        let originalDepth = rows[range.lowerBound].depth
        guard let parent = (0..<range.lowerBound).reversed().first(where: { rows[$0].depth == originalDepth - 1 }),
              let parentRange = subtreeRange(rows[parent].id) else { return false }
        var branch = Array(rows[range]); for i in branch.indices { branch[i].depth -= 1 }
        let destination = parentRange.upperBound - range.count
        rows.removeSubrange(range); rows.insert(contentsOf: branch, at: destination)
        return true
    }
    // Place a whole branch beside a target, preserving the hierarchy of both.
    @discardableResult mutating func move(_ id: UUID, relativeTo targetID: UUID, after: Bool) -> Bool {
        guard let source = subtreeRange(id), let target = subtreeRange(targetID), !source.contains(target.lowerBound) else { return false }
        let targetDepth = rows[target.lowerBound].depth
        let delta = targetDepth - rows[source.lowerBound].depth
        var branch = Array(rows[source]); for i in branch.indices { branch[i].depth += delta }
        var candidate = self; candidate.rows.removeSubrange(source)
        guard let adjustedTarget = candidate.subtreeRange(targetID) else { return false }
        let insertion = after ? adjustedTarget.upperBound : adjustedTarget.lowerBound
        candidate.rows.insert(contentsOf: branch, at: insertion)
        guard candidate.rows != rows else { return false }
        rows = candidate.rows; return true
    }
    @discardableResult mutating func appendLink(_ link: String, to id: UUID) -> Bool {
        guard !link.contains(where: { $0.isNewline }), link.hasPrefix("[["), let end = link.range(of: "]]"), end.lowerBound > link.index(link.startIndex, offsetBy: 2),
              let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        if !rows[index].text.isEmpty && !rows[index].text.hasSuffix(" ") { rows[index].text += " " }
        rows[index].text += link; return true
    }
}

// Structural actions register inverse snapshots on the window's undo manager.
// Identity guards prevent an old undo action from changing a different note.
final class OutlineUndoController: ObservableObject {
    func apply(_ next: OutlineDocument, to binding: Binding<OutlineDocument>, manager: UndoManager?, name: String) {
        let previous = binding.wrappedValue
        guard previous.identity == next.identity, previous != next else { return }
        manager?.registerUndo(withTarget: self) { [weak manager] controller in
            guard binding.wrappedValue.identity == previous.identity else { return }
            controller.apply(previous, to: binding, manager: manager, name: name)
        }
        manager?.setActionName(name)
        binding.wrappedValue = next
    }
}

struct OutlineEditor: View {
    @Binding var outline: OutlineDocument
    // Caller presents NotePicker and invokes the completion with its wiki link.
    let onRequestLink: (@escaping (String) -> Void) -> Void
    @Environment(\.undoManager) private var undoManager
    @StateObject private var history = OutlineUndoController()
    @State private var confirmDelete: OutlineDeleteRequest?

    private func change(_ name: String, _ edit: (inout OutlineDocument) -> Bool) {
        var next = outline
        guard edit(&next) else { return }
        history.apply(next, to: $outline, manager: undoManager, name: name)
    }
    private func moveBranch(_ identity: UUID, _ source: UUID, _ target: UUID, _ after: Bool) {
        guard outline.identity == identity else { return }
        change("Move Point") { $0.move(source, relativeTo: target, after: after) }
    }
    private func link(_ row: UUID) {
        let identity = outline.identity
        onRequestLink { value in
            guard outline.identity == identity else { return }
            change("Insert Link") { $0.appendLink(value, to: row) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Outline title", text: Binding(get: { outline.title }, set: { value in
                guard !value.contains(where: { $0.isNewline }) else { return }
                outline.title = value
            })).id(outline.identity).font(.headline).textFieldStyle(.roundedBorder)
            HStack { Text("Outline").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Text("Drag a point to reorder its branch").font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(outline.rows) { row in
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).help("Drag to move this point and its subpoints")
                            Text("•").foregroundStyle(.secondary)
                            TextField("Point", text: Binding(get: { outline.rows.first(where: { $0.id == row.id })?.text ?? "" }, set: { value in
                                guard !value.contains(where: { $0.isNewline }), let i = outline.rows.firstIndex(where: { $0.id == row.id }) else { return }
                                outline.rows[i].text = value
                            })).textFieldStyle(.roundedBorder)
                            Button { change("Outdent Point") { $0.outdent(row.id) } } label: { Image(systemName: "decrease.indent") }.help("Outdent point and its subpoints").disabled(row.depth == 0)
                            Button { change("Indent Point") { $0.indent(row.id) } } label: { Image(systemName: "increase.indent") }.help("Indent point and its subpoints")
                            Button { link(row.id) } label: { Image(systemName: "link") }.help("Link an existing note")
                            Button { change("Add Point") { $0.add(after: row.id) } } label: { Image(systemName: "plus") }.help("Add a point after this branch")
                            Button { confirmDelete = OutlineDeleteRequest(identity: outline.identity, row: row.id) } label: { Image(systemName: "minus.circle") }.help("Delete this point and its subpoints")
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, CGFloat(min(row.depth, 20)) * 14)
                        .contentShape(Rectangle())
                        .onDrag {
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(forTypeIdentifier: outlineDragType.identifier, visibility: .ownProcess) { completion in
                                completion(row.id.uuidString.data(using: .utf8), nil); return nil
                            }
                            return provider
                        }
                        .onDrop(of: [outlineDragType], delegate: OutlineDropDelegate(target: row.id, identity: outline.identity, after: false, onMove: moveBranch))
                    }
                    if let last = outline.rows.last {
                        Text("Drop here to move a branch to the end")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Rectangle())
                            .onDrop(of: [outlineDragType], delegate: OutlineDropDelegate(target: last.id, identity: outline.identity, after: true, onMove: moveBranch))
                    }
                }
            }
            Button("Add point") { change("Add Point") { $0.add(after: outline.rows.last?.id) } }
        }
        .confirmationDialog("Delete this point and its subpoints?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), presenting: confirmDelete) { request in
            Button("Delete Branch", role: .destructive) {
                if outline.identity == request.identity { change("Delete Branch") { $0.removeBranch(request.row) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
    }
}

private struct OutlineDeleteRequest { let identity: UUID; let row: UUID }

private struct OutlineDropDelegate: DropDelegate {
    let target: UUID
    let identity: UUID
    let after: Bool
    let onMove: (UUID, UUID, UUID, Bool) -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [outlineDragType]) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [outlineDragType]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: outlineDragType.identifier) { data, _ in
            guard let data, let raw = String(data: data, encoding: .utf8), let source = UUID(uuidString: raw) else { return }
            DispatchQueue.main.async { onMove(identity, source, target, after) }
        }
        return true
    }
}
