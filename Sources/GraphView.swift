import SwiftUI
import AppKit

// Read-only, deterministic placement. The local view uses one ring per link
// distance; the whole-vault view uses a spiral to avoid implying hierarchy.
enum GraphLayout {
    static func localNodes(_ nodes: [GraphNode], center: String, all: Set<String>, nearby: Set<String>, limit: Int) -> [GraphNode] {
        let first = nodes.filter { $0.path == center }
        let second = nodes.filter { $0.path != center && nearby.contains($0.path) }
        let third = nodes.filter { all.contains($0.path) && !nearby.contains($0.path) }
        return Array((first + second + third).prefix(max(0, limit)))
    }
    static func positions(nodes: [GraphNode], edges: [GraphEdge], focus: String?, includeBranches: Bool) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let paths = Set(nodes.map(\.path))
        let active = edges.filter { paths.contains($0.source) && paths.contains($0.target) && (includeBranches || $0.kind == .link) }
        if let focus, paths.contains(focus) {
            var distance: [String: Int] = [focus: 0]
            for level in 1...2 {
                let previous = Set(distance.filter { $0.value == level - 1 }.map(\.key))
                for edge in active {
                    if previous.contains(edge.source), distance[edge.target] == nil { distance[edge.target] = level }
                    if previous.contains(edge.target), distance[edge.source] == nil { distance[edge.source] = level }
                }
            }
            var result: [String: CGPoint] = [focus: .zero]
            for level in 1...2 {
                let ring = nodes.filter { distance[$0.path] == level }
                let radius: CGFloat = level == 1 ? 0.50 : 0.91
                for (index, node) in ring.enumerated() {
                    let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(max(1, ring.count)) - CGFloat.pi / 2
                    result[node.path] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
                }
            }
            return result
        }
        var result: [String: CGPoint] = [:]
        for (index, node) in nodes.enumerated() {
            let radius = 0.93 * sqrt(CGFloat(index) / CGFloat(max(1, nodes.count - 1)))
            let angle = CGFloat(index) * 2.399963229728653
            result[node.path] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
        return result
    }
}

struct GraphView: View {
    let currentURL: URL?
    let onOpen: (URL) -> Void
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("saveFolder") private var saveFolder = ""
    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    @State private var graph: CardGraph?
    @State private var selected: String?
    @State private var focus: String?
    @State private var scope: String
    @State private var depth = 1
    @State private var showBranches = true
    @State private var query = ""
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @State private var message = "Choose a notes folder to begin."
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var hovered: String?
    @State private var preview = ""
    @State private var previewID = UUID()
    @State private var matches: [GraphNode] = []
    @State private var visibleNodes: [GraphNode] = []
    @State private var visibleEdges: [GraphEdge] = []
    @State private var totalVisibleCandidates = 0
    @State private var maximumDegree = 1
    private let nodeLimit = 180

    init(currentURL: URL?, onOpen: @escaping (URL) -> Void) {
        self.currentURL = currentURL
        self.onOpen = onOpen
        _scope = State(initialValue: currentURL == nil ? "all" : "local")
    }

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var allNodes: [GraphNode] { graph?.nodes ?? [] }
    private var selectedNode: GraphNode? { allNodes.first { $0.path == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Graph").font(.title2.bold())
                Spacer()
                Button("Choose Notes Folder…", action: chooseFolder).help("Changes the notes folder used throughout Cardify")
                Button("Refresh", action: load).disabled(folder.isEmpty || loading)
            }
            Text(folder.isEmpty ? "No notes folder selected" : folder)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 12) {
                Picker("View", selection: $scope) {
                    Text("Local").tag("local")
                    Text("Whole vault").tag("all")
                }.pickerStyle(.segmented).frame(width: 220)
                if scope == "local" {
                    Picker("Depth", selection: $depth) { Text("1 step").tag(1); Text("2 steps").tag(2) }
                        .frame(width: 120).help("Show cards one or two connections from the center")
                }
                Toggle("Possible branches", isOn: $showBranches).help("Dotted lines are possible branches inferred from IDs")
                Spacer()
                Button("Reset view") { zoom = 1; pan = .zero }
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search card titles or IDs", text: $query)
                    Text("\(matches.count) cards").font(.caption).foregroundStyle(.secondary)
                    List(matches.prefix(500)) { node in
                        Button { select(node.path); if scope == "local" && !visibleNodes.contains(where: { $0.path == node.path }) { focus = node.path; pan = .zero; zoom = 1 } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.title).lineLimit(1).fontWeight(node.path == selected ? .semibold : .regular)
                                Text(node.cardID.map { "\($0) · \(node.degree) linked" } ?? "\(node.degree) linked")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.frame(minHeight: 150)
                    if matches.count > 500 { Text("First 500 results shown. Refine search for more.").font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    if let node = selectedNode {
                        Text(node.title).font(.headline).lineLimit(2)
                        Text(node.cardID.map { "ID: \($0)" } ?? "No card ID").font(.caption).foregroundStyle(.secondary)
                        Text("\(node.degree) distinct linked \(node.degree == 1 ? "card" : "cards")")
                            .font(.caption).foregroundStyle(.secondary)
                        if !preview.isEmpty { Text(preview).font(.caption).lineLimit(4).foregroundStyle(.secondary).textSelection(.enabled) }
                        HStack {
                            Button("Center here") { focus = node.path; scope = "local"; pan = .zero; zoom = 1 }
                            Button("Open Card") { onOpen(node.url) }
                        }
                    } else {
                        Text("Select a card to inspect its connections.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                VStack(alignment: .leading, spacing: 6) {
                    graphCanvas
                    HStack {
                        Text("Zoom").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $zoom, in: 0.5...2.5).frame(maxWidth: 200)
                        Text("\(Int(zoom * 100))%").font(.caption).monospacedDigit()
                        Spacer()
                        Text("Drag to pan · click to inspect").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        Text("━  Link").font(.caption)
                        Text("┈  Possible branch by ID").font(.caption)
                        Text("Blue: fewer · orange: more links in folder").font(.caption).help("Distinct linked cards across the notes folder; possible branches are not counted.")
                    }.foregroundStyle(.secondary)
                    Text("\(message)\(totalVisibleCandidates > nodeLimit ? " Showing the first \(nodeLimit) of \(totalVisibleCandidates); search or focus a card to narrow the view." : "")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }.frame(minWidth: 420)
            }
        }.padding(20).frame(minWidth: 800, minHeight: 540)
        .preferredColorScheme(AppearancePreference.colorScheme(for: appearance))
        .onAppear { if !folder.isEmpty { load() } }
        .onChange(of: folder) { _ in load() }
        .onChange(of: selected) { _ in loadPreview() }
        .onChange(of: scope) { _ in rebuildGraph() }
        .onChange(of: focus) { _ in rebuildGraph() }
        .onChange(of: depth) { _ in rebuildGraph() }
        .onChange(of: showBranches) { _ in rebuildGraph() }
        .onChange(of: query) { _ in rebuildGraph() }
    }

    @ViewBuilder private var graphCanvas: some View {
        if loading {
            ProgressView("Loading cards…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if allNodes.isEmpty {
            Text(folder.isEmpty ? "Choose your notes folder to see its graph." : message)
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scope == "local" && focus == nil {
            Text("Select a card, then choose Center here to see its neighborhood.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleNodes.isEmpty {
            Text("No cards match this view.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                let nodes = visibleNodes
                let edges = visibleEdges
                let points = GraphLayout.positions(nodes: nodes, edges: edges, focus: scope == "local" ? focus : nil, includeBranches: showBranches)
                let maximum = maximumDegree
                let scale = min(geometry.size.width, geometry.size.height) * 0.40 * zoom
                let center = CGPoint(x: geometry.size.width / 2 + pan.width + drag.width, y: geometry.size.height / 2 + pan.height + drag.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor))
                    Canvas { context, _ in
                        let pairs = Set(edges.filter { $0.kind == .link }.map { pair($0.source, $0.target) })
                        for edge in edges {
                            guard let a = points[edge.source], let b = points[edge.target] else { continue }
                            var start = CGPoint(x: center.x + a.x * scale, y: center.y + a.y * scale)
                            var end = CGPoint(x: center.x + b.x * scale, y: center.y + b.y * scale)
                            if edge.kind == .possibleBranch && pairs.contains(pair(edge.source, edge.target)) {
                                let dx = end.x - start.x, dy = end.y - start.y, length = max(1, hypot(dx, dy))
                                start.x -= dy / length * 4; start.y += dx / length * 4
                                end.x -= dy / length * 4; end.y += dx / length * 4
                            }
                            var line = Path(); line.move(to: start); line.addLine(to: end)
                            context.stroke(line, with: .color(edge.kind == .link ? .secondary.opacity(0.65) : .orange.opacity(0.8)), style: edge.kind == .link ? StrokeStyle(lineWidth: 1.2) : StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4]))
                        }
                    }
                    ForEach(nodes) { node in
                        if let point = points[node.path] {
                            let diameter = CGFloat(24 + 14 * sqrt(Double(node.degree) / Double(maximum)))
                            Button { select(node.path) } label: {
                                ZStack(alignment: .top) {
                                    Circle().fill(color(for: node.degree, maximum: maximum))
                                        .overlay(Circle().stroke(node.path == selected ? Color.primary : Color.clear, lineWidth: 2))
                                        .overlay(Text("\(node.degree)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white))
                                        .frame(width: diameter, height: diameter)
                                    if nodes.count <= 16 || node.path == selected || node.path == hovered {
                                        Text(node.title).font(.caption2).lineLimit(1).frame(maxWidth: 120)
                                            .padding(.horizontal, 3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                                            .fixedSize().offset(y: diameter + 3)
                                    }
                                }.frame(width: diameter, height: diameter).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("\(node.title) · \(node.degree) linked cards")
                                .accessibilityLabel("\(node.title), \(node.degree) linked cards")
                                .onHover { inside in hovered = inside ? node.path : nil }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(node.url) })
                                .position(x: center.x + point.x * scale, y: center.y + point.y * scale)
                        }
                    }
                }.clipped().contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3).updating($drag) { value, state, _ in state = value.translation }.onEnded { value in pan.width += value.translation.width; pan.height += value.translation.height })
            }
        }
    }

    private func pair(_ a: String, _ b: String) -> String { a < b ? a + "\u{0}" + b : b + "\u{0}" + a }
    private func color(for degree: Int, maximum: Int) -> Color {
        let t = min(1, Double(degree) / Double(maximum))
        return Color(red: 0.20 + 0.55 * t, green: 0.48 + 0.03 * t, blue: 0.72 - 0.62 * t)
    }
    private func select(_ path: String) { selected = path }
    private func rebuildGraph() {
        guard let graph else { matches = []; visibleNodes = []; visibleEdges = []; totalVisibleCandidates = 0; maximumDegree = 1; return }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        matches = term.isEmpty ? graph.nodes : graph.nodes.filter { $0.title.localizedCaseInsensitiveContains(term) || $0.path.localizedCaseInsensitiveContains(term) || ($0.cardID?.localizedCaseInsensitiveContains(term) ?? false) }
        maximumDegree = max(1, graph.nodes.map(\.degree).max() ?? 1)
        if scope == "local", let focus {
            let all = graph.neighborhood(of: focus, depth: depth, includeBranches: showBranches)
            let nearby = graph.neighborhood(of: focus, depth: 1, includeBranches: showBranches)
            totalVisibleCandidates = all.count
            visibleNodes = GraphLayout.localNodes(graph.nodes, center: focus, all: all, nearby: nearby, limit: nodeLimit)
        } else {
            totalVisibleCandidates = matches.count
            visibleNodes = Array(matches.prefix(nodeLimit))
        }
        let paths = Set(visibleNodes.map(\.path))
        visibleEdges = graph.edges.filter { paths.contains($0.source) && paths.contains($0.target) && (showBranches || $0.kind == .link) }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { notesFolder = url.path }
    }
    private func loadPreview() {
        preview = ""
        let request = UUID(); previewID = request
        guard let node = selectedNode, !folder.isEmpty else { return }
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let text = CardGraph.canOpen(node.url, in: root) ? ((try? String(contentsOf: node.url, encoding: .utf8)) ?? "") : ""
            let body = CardMetadata.parse(text).body.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = String(body.prefix(250))
            DispatchQueue.main.async { if previewID == request { preview = snippet } }
        }
    }
    private func load() {
        let path = folder
        let request = UUID(); loadID = request; previewID = UUID()
        graph = nil; selected = nil; focus = nil; preview = ""; pan = .zero; zoom = 1
        rebuildGraph()
        guard !path.isEmpty else { loading = false; message = "Choose a notes folder to begin."; return }
        loading = true; message = "Loading cards…"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try CardGraph.load(folder: url) }
            DispatchQueue.main.async {
                guard loadID == request else { return }
                loading = false
                switch result {
                case .failure:
                    message = "Could not read the notes folder. Check access and try again."
                case .success(let loaded):
                    graph = loaded
                    if let currentURL, let node = loaded.nodes.first(where: { $0.url.resolvingSymlinksInPath().standardizedFileURL == currentURL.resolvingSymlinksInPath().standardizedFileURL }) {
                        selected = node.path; focus = node.path
                    } else { scope = "all" }
                    rebuildGraph()
                    if loaded.nodes.isEmpty { message = "No Markdown cards found in this folder." }
                    else {
                        let warnings = (loaded.unreadableCount > 0 ? " Across the folder, \(loaded.unreadableCount) files could not be read; some links and possible branches may be missing." : "") + (loaded.unresolvedCount > 0 ? " Across the folder, \(loaded.unresolvedCount) links could not be resolved." : "")
                        message = "\(loaded.nodes.count) cards. Positions do not imply similarity." + warnings
                    }
                }
            }
        }
    }
}
