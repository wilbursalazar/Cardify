import SwiftUI
import AppKit

// A stable resolution-first tree. Primary connections expand recursively;
// related connections appear as dashed references to the same source note.
struct DebateHierarchyView: View {
    let hierarchy: DebateHierarchy
    let hasResolutions: Bool
    let selectedPath: String?
    let isFocused: Bool
    let onSelect: (LibraryCard) -> Void
    let onOpen: (LibraryCard) -> Void
    let onNewResolution: () -> Void
    let onNewPoint: (DebateRole, LibraryCard) -> Void

    private let columnGap: CGFloat = 24
    private var lineColor: Color { Color.secondary.opacity(0.38) }
    private var columnWidth: CGFloat {
        // Keep deep nodes legible by expanding the scrollable canvas instead
        // of making each nested card narrower than its contents.
        var depth = 0
        var pending = (hierarchy.aff + hierarchy.def).map { ($0, 0) }
        while let (branch, level) = pending.popLast() {
            depth = max(depth, level)
            pending.append(contentsOf: branch.primaryBranches.map { ($0, level + 1) })
        }
        return max(238, 220 + CGFloat(depth) * 26)
    }

    var body: some View {
        if isFocused { focusedMap } else { fullMap }
    }

    private var fullMap: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                VStack(spacing: 0) {
                    if let project = hierarchy.project {
                        DebateGraphNode(card: project, kind: "Resolution", tint: .accentColor, width: 300,
                                        selectedPath: selectedPath, onSelect: onSelect, onOpen: onOpen)
                    } else {
                        VStack(spacing: 7) {
                            if !hierarchy.aff.isEmpty || !hierarchy.def.isEmpty {
                                Text("Unassigned arguments").font(.subheadline.weight(.medium))
                            }
                            Text(hasResolutions ? "Select a resolution above, or create one." : "Create a resolution to get started.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("New resolution", action: onNewResolution)
                        }
                        .padding(12).frame(width: 300).frame(minHeight: 80)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(lineColor))
                    }
                    if hierarchy.project != nil || !hierarchy.aff.isEmpty || !hierarchy.def.isEmpty {
                        Rectangle().fill(lineColor).frame(width: 1, height: 18)
                        Rectangle().fill(lineColor).frame(width: columnWidth + columnGap, height: 1)
                        HStack(spacing: 0) {
                            Rectangle().fill(lineColor).frame(width: 1, height: 14)
                            Spacer(minLength: 0)
                            Rectangle().fill(lineColor).frame(width: 1, height: 14)
                        }.frame(width: columnWidth + columnGap)
                        HStack(alignment: .top, spacing: columnGap) {
                            column("AFF", branches: hierarchy.aff, tint: .blue)
                            column("DEF", branches: hierarchy.def, tint: .orange)
                        }
                    }
                    if hierarchy.unreadable > 0 || hierarchy.unresolved > 0 {
                        Text("Some notes or connections could not be read or resolved. Refresh after checking the notes folder.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: columnWidth * 2 + columnGap, alignment: .leading)
                            .padding(.top, 14)
                    }
                }
                .padding(18)
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
            .accessibilityLabel("Debate argument graph")
        }
    }

    private var focusedMap: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                if let focus = hierarchy.focus(on: selectedPath) {
                    let width = max(240, min(440, geometry.size.width - 50))
                    VStack(alignment: .leading, spacing: 12) {
                        if !focus.ancestors.isEmpty {
                            Text("Path to this card").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack(spacing: 5) {
                                ForEach(focus.ancestors, id: \.path) { ancestor in
                                    Button(DebateHierarchy.displayName(ancestor)) { onSelect(ancestor) }
                                        .buttonStyle(.link).lineLimit(1)
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                                }
                            }.fixedSize(horizontal: true, vertical: false)
                        }
                        Text("Selected card").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        DebateGraphNode(card: focus.selected, kind: DebateGraphNode.childKind(focus.selected, related: false), tint: .accentColor,
                                        width: width, selectedPath: selectedPath, onSelect: onSelect, onOpen: onOpen,
                                        showStance: !focus.ancestors.isEmpty && focus.ancestors.last?.path != hierarchy.project?.path && !focus.relatedOnly)
                        if focus.relatedOnly {
                            Text("This related card’s primary branch is outside the current map. Select its resolution to see its full path.")
                                .font(.caption).foregroundStyle(.secondary).frame(width: width, alignment: .leading)
                        } else {
                            Text("Directly connected cards").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                            if focus.children.isEmpty && focus.related.isEmpty {
                                Text("No cards connected yet. Use the actions on the right to add one.")
                                    .font(.caption).foregroundStyle(.secondary).frame(width: width, alignment: .leading)
                            }
                            ForEach(focus.children, id: \.path) { child in
                                DebateGraphNode(card: child, kind: DebateGraphNode.childKind(child, related: false), tint: .secondary,
                                                width: width, selectedPath: selectedPath, onSelect: onSelect, onOpen: onOpen,
                                                showStance: DebateNotes.parse(child.content).primary != nil)
                            }
                            ForEach(focus.related, id: \.path) { card in
                                DebateGraphNode(card: card, kind: DebateGraphNode.childKind(card, related: true), tint: .secondary,
                                                width: width, selectedPath: selectedPath, onSelect: onSelect, onOpen: onOpen,
                                                explanation: relatedExplanation(card, parent: focus.selected))
                            }
                            if !focus.related.isEmpty {
                                Text("Related cards are cross-links, not children of this card.")
                                    .font(.caption2).foregroundStyle(.secondary).frame(width: width, alignment: .leading)
                            }
                        }
                    }.padding(18).frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                } else {
                    Text("Select a card in the full map to focus on its branch.")
                        .foregroundStyle(.secondary).padding(18)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .center)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
            .accessibilityLabel("Focused debate branch")
        }
    }

    private func relatedExplanation(_ card: LibraryCard, parent: LibraryCard) -> String {
        DebateNotes.parse(card.content).related.first { relation in
            relation.path.caseInsensitiveCompare(parent.path) == .orderedSame ||
                (!relation.path.contains("/") && relation.path.caseInsensitiveCompare((parent.path as NSString).lastPathComponent) == .orderedSame)
        }?.explanation ?? ""
    }

    private func column(_ label: String, branches: [DebateBranch], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(tint)
                Text("\(branches.count)").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let project = hierarchy.project {
                    Button("Add \(label)") { onNewPoint(label == "AFF" ? .aff : .def, project) }
                        .help("Add another \(label) point to this resolution")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if branches.isEmpty {
                VStack(spacing: 7) {
                    Text(label == "AFF" && hierarchy.project != nil ? "Add an AFF point to begin." : "No \(label) points yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10).frame(maxWidth: .infinity, minHeight: 58)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(lineColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(branches, id: \.parent.path) { branch in
                        HStack(alignment: .top, spacing: 0) {
                            DebateGraphConnector(dashed: false).frame(width: 12, height: 1).padding(.top, 23)
                            DebateGraphBranch(branch: branch, kind: label, tint: tint, width: columnWidth - 22,
                                              selectedPath: selectedPath, onSelect: onSelect, onOpen: onOpen)
                        }
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(lineColor).frame(width: 1).padding(.leading, 10)
                }
            }
        }.frame(width: columnWidth, alignment: .topLeading)
    }
}

private struct DebateGraphBranch: View {
    let branch: DebateBranch
    let kind: String
    let tint: Color
    let width: CGFloat
    let selectedPath: String?
    let onSelect: (LibraryCard) -> Void
    let onOpen: (LibraryCard) -> Void
    var explanation = ""
    var isPrimaryChild = false
    private var lineColor: Color { Color.secondary.opacity(0.38) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DebateGraphNode(card: branch.parent, kind: kind, tint: tint, width: width,
                            selectedPath: selectedPath, onSelect: onSelect, onOpen: onOpen, explanation: explanation,
                            showStance: isPrimaryChild)
            if !branch.primaryBranches.isEmpty || !branch.related.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(branch.primaryBranches, id: \.parent.path) { child in
                        HStack(alignment: .top, spacing: 0) {
                            Rectangle().fill(lineColor).frame(width: 1)
                            DebateGraphConnector(dashed: false).frame(width: 12, height: 1).padding(.top, 21)
                            DebateGraphBranch(branch: child, kind: DebateGraphNode.childKind(child.parent, related: false),
                                              tint: .secondary, width: width - 26, selectedPath: selectedPath,
                                              onSelect: onSelect, onOpen: onOpen,
                                              explanation: DebateNotes.parse(child.parent.content).primary?.explanation ?? "", isPrimaryChild: true)
                                .padding(.top, 6)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(branch.related) { card in
                        HStack(alignment: .top, spacing: 0) {
                            Rectangle().fill(lineColor).frame(width: 1)
                            DebateGraphConnector(dashed: true).frame(width: 12, height: 1).padding(.top, 21)
                            DebateGraphNode(card: card, kind: DebateGraphNode.childKind(card, related: true),
                                            tint: .secondary, width: width - 26, selectedPath: selectedPath,
                                            onSelect: onSelect, onOpen: onOpen,
                                            explanation: relatedExplanation(card))
                                .padding(.top, 6)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.leading, 13)
            }
        }
    }

    private func relatedExplanation(_ card: LibraryCard) -> String {
        DebateNotes.parse(card.content).related.first {
            $0.path.caseInsensitiveCompare(branch.parent.path) == .orderedSame
        }?.explanation ?? ""
    }
}

private struct DebateGraphConnector: View {
    let dashed: Bool
    var body: some View {
        Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 12, y: 0)) }
            .stroke(Color.secondary.opacity(0.38), style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : []))
    }
}

private struct DebateGraphNode: View {
    let card: LibraryCard
    let kind: String
    let tint: Color
    let width: CGFloat
    let selectedPath: String?
    let onSelect: (LibraryCard) -> Void
    let onOpen: (LibraryCard) -> Void
    var explanation = ""
    var showStance = false
    private var lineColor: Color { Color.secondary.opacity(0.38) }
    private var stanceLabel: String {
        switch DebateNotes.parse(card.content).primaryStance {
        case .supports: return "Supports parent"
        case .challenges: return "Challenges parent"
        case nil: return "Relationship unspecified"
        }
    }

    var body: some View {
        Button { onSelect(card) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(kind).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    Spacer(minLength: 0)
                    if let cardID = card.cardID, !cardID.isEmpty {
                        Text(cardID).font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: max(85, width * 0.55), alignment: .trailing)
                    }
                }
                Text(card.title).font(.system(size: 12, weight: .medium))
                    .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if showStance {
                    Text(stanceLabel).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !explanation.isEmpty {
                    Text(explanation).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(width: width, alignment: .leading).frame(minHeight: 47, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedPath == card.path ? Color.accentColor : lineColor, lineWidth: selectedPath == card.path ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("\(card.path) · Click to select; double-click to open")
        .accessibilityLabel("\(kind): \(card.title)\(showStance ? ", \(stanceLabel)" : "")")
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(card) })
    }

    static func childKind(_ card: LibraryCard, related: Bool) -> String {
        let role = DebateNotes.parse(card.content).role?.rawValue
        let label: String
        switch role {
        case "project": label = "Resolution"
        case "evidence": label = "Evidence"
        case "objection": label = "Objection"
        case "argument": label = "Argument"
        case "reply": label = "Reply"
        case "aff": label = "AFF"
        case "def": label = "DEF"
        default: label = "Card"
        }
        return related ? label + " · related" : label
    }
}
