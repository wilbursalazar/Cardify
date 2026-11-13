import SwiftUI

// The panes keep the same SwiftUI identity in every arrangement. This matters
// for the NSTextView's undo history and the preview's stable PDF view.
enum WorkspaceArrangement: String, CaseIterable, Identifiable {
    case editorLeft = "editor-left"
    case previewLeft = "preview-left"
    case editorAbove = "editor-above"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .editorLeft: return "Writing left · Preview right"
        case .previewLeft: return "Preview left · Writing right"
        case .editorAbove: return "Writing above · Preview below"
        }
    }
    var isVertical: Bool { self == .editorAbove }
    static func stored(_ value: String) -> WorkspaceArrangement { WorkspaceArrangement(rawValue: value) ?? .editorLeft }
}

struct WorkspacePaneGeometry {
    let editor: CGRect
    let divider: CGRect
    let preview: CGRect
    let editorFraction: CGFloat

    static func calculate(size: CGSize, arrangement: WorkspaceArrangement, fraction: CGFloat) -> WorkspacePaneGeometry {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let total = arrangement.isVertical ? height : width
        let handle = min(10, total)
        let available = max(0, total - handle)
        var editorMinimum: CGFloat = arrangement.isVertical ? 200 : 280
        var previewMinimum: CGFloat = arrangement.isVertical ? 170 : 230
        if editorMinimum + previewMinimum > available {
            let scale = available / (editorMinimum + previewMinimum)
            editorMinimum *= scale
            previewMinimum *= scale
        }
        let safeFraction = fraction.isFinite ? min(1, max(0, fraction)) : 0.55
        let editorLength = min(max(available * safeFraction, editorMinimum), available - previewMinimum)
        let previewLength = max(0, available - editorLength)
        let actual = available > 0 ? editorLength / available : 0.5
        if arrangement == .editorAbove {
            return WorkspacePaneGeometry(editor: CGRect(x: 0, y: 0, width: width, height: editorLength),
                                         divider: CGRect(x: 0, y: editorLength, width: width, height: handle),
                                         preview: CGRect(x: 0, y: editorLength + handle, width: width, height: previewLength), editorFraction: actual)
        }
        if arrangement == .previewLeft {
            return WorkspacePaneGeometry(editor: CGRect(x: previewLength + handle, y: 0, width: editorLength, height: height),
                                         divider: CGRect(x: previewLength, y: 0, width: handle, height: height),
                                         preview: CGRect(x: 0, y: 0, width: previewLength, height: height), editorFraction: actual)
        }
        return WorkspacePaneGeometry(editor: CGRect(x: 0, y: 0, width: editorLength, height: height),
                                     divider: CGRect(x: editorLength, y: 0, width: handle, height: height),
                                     preview: CGRect(x: editorLength + handle, y: 0, width: previewLength, height: height), editorFraction: actual)
    }
}

private struct WorkspacePaneLayout: Layout {
    var arrangement: WorkspaceArrangement
    var fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 600,
               height: proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 400)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let geometry = WorkspacePaneGeometry.calculate(size: bounds.size, arrangement: arrangement, fraction: fraction)
        for (view, rect) in zip(subviews, [geometry.editor, geometry.divider, geometry.preview]) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
    }
}

struct WorkspaceSplitView<Editor: View, Preview: View>: View {
    let arrangement: WorkspaceArrangement
    private let editor: Editor
    private let preview: Preview
    @State private var horizontalFraction: CGFloat = 0.55
    @State private var verticalFraction: CGFloat = 0.55
    @State private var dragStartFraction: CGFloat?

    init(arrangement: WorkspaceArrangement, @ViewBuilder editor: () -> Editor, @ViewBuilder preview: () -> Preview) {
        self.arrangement = arrangement
        self.editor = editor()
        self.preview = preview()
    }

    private var fraction: CGFloat { arrangement.isVertical ? verticalFraction : horizontalFraction }
    private func setFraction(_ value: CGFloat) {
        if arrangement.isVertical { verticalFraction = value } else { horizontalFraction = value }
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = WorkspacePaneGeometry.calculate(size: proxy.size, arrangement: arrangement, fraction: fraction)
            WorkspacePaneLayout(arrangement: arrangement, fraction: fraction) {
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
                divider(size: proxy.size, current: geometry.editorFraction)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func divider(size: CGSize, current: CGFloat) -> some View {
        let vertical = arrangement.isVertical
        return ZStack {
            Color.clear
            Rectangle().fill(Color.secondary.opacity(0.25))
                .frame(width: vertical ? nil : 1, height: vertical ? 1 : nil)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartFraction == nil { dragStartFraction = current }
                let available = max(1, (vertical ? size.height : size.width) - 10)
                let translation = vertical ? value.translation.height : value.translation.width * (arrangement == .previewLeft ? -1 : 1)
                setFraction((dragStartFraction ?? current) + translation / available)
            }
            .onEnded { _ in dragStartFraction = nil })
        .focusable()
        .onMoveCommand { direction in
            let change: CGFloat
            switch (arrangement, direction) {
            case (.editorAbove, .up), (.editorLeft, .left), (.previewLeft, .right): change = -0.05
            case (.editorAbove, .down), (.editorLeft, .right), (.previewLeft, .left): change = 0.05
            default: return
            }
            setFraction(current + change)
        }
        .accessibilityLabel("Adjust writing and preview sizes")
        .accessibilityValue("Writing area \(Int((current * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setFraction(current + 0.05)
            case .decrement: setFraction(current - 0.05)
            @unknown default: break
            }
        }
        .help("Drag to resize writing and preview. Select and use arrow keys to adjust.")
    }
}
