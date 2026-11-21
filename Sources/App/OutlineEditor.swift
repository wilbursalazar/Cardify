import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let outlineDragType = UTType(exportedAs: "com.wilbursalazar.cardify.outline-row")

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
