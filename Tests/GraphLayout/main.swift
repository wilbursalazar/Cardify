import AppKit
import Foundation

@main struct GraphLayoutCheck {
 static func main() {
  let focus = "zzz-focus"
  let neighbors = (0..<220).map { String(format: "note-%03d", $0) }
  let paths = neighbors + [focus]
  let nodes = paths.map { GraphNode(path: $0, url: URL(fileURLWithPath: "/vault/" + $0 + ".md"), title: $0, cardID: nil, degree: 1) }
  let all = Set(paths)
  let nearby = Set(neighbors.prefix(100) + [focus])
  let shown = GraphLayout.localNodes(nodes, center: focus, all: all, nearby: nearby, limit: 180)
  precondition(shown.count == 180 && shown.first?.path == focus, "the focus must not be cut off by the display limit")
  precondition(Set(neighbors.prefix(100)).isSubset(of: Set(shown.map(\.path))), "one-step neighbors must be shown before two-step notes")
  let edges = neighbors.prefix(100).map { GraphEdge(source: focus, target: $0, kind: .link) }
  let positions = GraphLayout.positions(nodes: shown, edges: edges, focus: focus, includeBranches: true)
  precondition(positions[focus] == .zero, "local focus should be centered")
  let allPositions = GraphLayout.positions(nodes: nodes, edges: edges, focus: nil, includeBranches: true)
  precondition(allPositions.count == nodes.count, "whole-vault layout should locate every supplied node")
  print("Local graph retains its late-sorting center and prioritizes nearby nodes")
 }
}
