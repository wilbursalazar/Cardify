import Foundation
import CoreGraphics
import Combine

// A bounded, deterministic spring layout. Its output changes positions only;
// it never changes the graph's cards, links, or link counts.
struct GraphPhysics {
    struct Link: Hashable {
        let first: String
        let second: String
        init(_ a: String, _ b: String) {
            first = min(a, b); second = max(a, b)
        }
    }
    private(set) var paths: [String]
    private var positions: [CGPoint]
    private var velocity: [CGPoint]
    private var links: [(Int, Int)]
    private var anchor: Int?
    private var grabbed: Int?
    private static let bound: CGFloat = 0.97

    init(paths: [String], links: [Link], seeds: [String: CGPoint], anchor: String?) {
        let normalizedPaths = Array(Set(paths).sorted().prefix(180))
        self.paths = normalizedPaths
        let index = Dictionary(uniqueKeysWithValues: normalizedPaths.enumerated().map { ($0.element, $0.offset) })
        self.positions = normalizedPaths.enumerated().map { i, path in
            if let p = seeds[path], p.x.isFinite, p.y.isFinite { return Self.clamp(p) }
            let angle = CGFloat(i) * 2.399963229728653
            let radius = 0.85 * sqrt(CGFloat(i + 1) / CGFloat(max(1, normalizedPaths.count)))
            return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
        self.velocity = Array(repeating: .zero, count: self.paths.count)
        let unique = Set(links).filter { $0.first != $0.second }.sorted { ($0.first, $0.second) < ($1.first, $1.second) }
        self.links = unique.compactMap { link in
            guard let a = index[link.first], let b = index[link.second] else { return nil }
            return (a, b)
        }
        self.anchor = anchor.flatMap { index[$0] }
    }

    var points: [String: CGPoint] { Dictionary(uniqueKeysWithValues: zip(paths, positions)) }

    // Returns the largest movement, allowing the timer to stop once settled.
    @discardableResult mutating func step() -> CGFloat {
        let n = paths.count
        guard n > 1 else { return 0 }
        var forces = Array(repeating: CGPoint.zero, count: n)
        let repulsion: CGFloat = 0.0007 / sqrt(CGFloat(n))
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                var dx = positions[j].x - positions[i].x
                var dy = positions[j].y - positions[i].y
                if abs(dx) + abs(dy) < 0.00001 {
                    let angle = CGFloat((i + 1) * 31 + (j + 1) * 17)
                    dx = 0.001 * cos(angle); dy = 0.001 * sin(angle)
                }
                let distance2 = dx * dx + dy * dy + 0.0025
                let distance = sqrt(distance2)
                let amount = min(0.012, repulsion / distance2)
                let x = amount * dx / distance, y = amount * dy / distance
                forces[i].x -= x; forces[i].y -= y
                forces[j].x += x; forces[j].y += y
            }
        }
        let desired: CGFloat = 0.28 + min(0.12, sqrt(CGFloat(n)) * 0.006)
        for (a, b) in links {
            let dx = positions[b].x - positions[a].x, dy = positions[b].y - positions[a].y
            let distance = max(0.0001, hypot(dx, dy))
            let strength = max(-0.008, min(0.008, (distance - desired) * 0.006))
            let x = strength * dx / distance, y = strength * dy / distance
            forces[a].x += x; forces[a].y += y
            forces[b].x -= x; forces[b].y -= y
        }
        var maxMovement: CGFloat = 0
        for i in 0..<n {
            if i == anchor || i == grabbed { velocity[i] = .zero; continue }
            forces[i].x -= positions[i].x * 0.00065
            forces[i].y -= positions[i].y * 0.00065
            var dx = (velocity[i].x + forces[i].x) * 0.78
            var dy = (velocity[i].y + forces[i].y) * 0.78
            let speed = hypot(dx, dy)
            if speed > 0.018 { dx *= 0.018 / speed; dy *= 0.018 / speed }
            let old = positions[i]
            positions[i] = Self.clamp(CGPoint(x: old.x + dx, y: old.y + dy))
            velocity[i] = CGPoint(x: positions[i].x - old.x, y: positions[i].y - old.y)
            maxMovement = max(maxMovement, hypot(velocity[i].x, velocity[i].y))
        }
        return maxMovement
    }

    mutating func beginDrag(_ path: String) {
        guard let index = paths.firstIndex(of: path) else { return }
        grabbed = index
        // Once explicitly moved, the local center is free to participate.
        if anchor == index { anchor = nil }
        velocity[index] = .zero
    }
    mutating func drag(_ path: String, to point: CGPoint) {
        guard let index = paths.firstIndex(of: path), grabbed == index, point.x.isFinite, point.y.isFinite else { return }
        positions[index] = Self.clamp(point); velocity[index] = .zero
    }
    mutating func endDrag() { grabbed = nil }

    private static func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: max(-bound, min(bound, p.x)), y: max(-bound, min(bound, p.y)))
    }
}

// A finite timer settles after movement or stops after five seconds. It is
// invalidated when the graph disappears and uses no timer for Reduce Motion.
final class GraphMotionController: ObservableObject {
    @Published private(set) var points: [String: CGPoint] = [:]
    @Published private(set) var isAnimating = false
    private struct Signature: Equatable {
        let paths: [String]
        let links: [GraphPhysics.Link]
        let anchor: String?
        let reduced: Bool
    }
    private var signature: Signature?
    private var physics: GraphPhysics?
    private var timer: Timer?
    private var stepsLeft = 0
    private var quietSteps = 0
    private var deadline: TimeInterval = 0
    private var reduceMotion = false

    func configure(paths: [String], links: [GraphPhysics.Link], seeds: [String: CGPoint], anchor: String?, reduceMotion: Bool) {
        let paths = Array(Set(paths).sorted().prefix(180))
        let allowed = Set(paths)
        let links = Set(links.filter { allowed.contains($0.first) && allowed.contains($0.second) && $0.first != $0.second })
            .sorted { ($0.first, $0.second) < ($1.first, $1.second) }
        let next = Signature(paths: paths, links: links, anchor: anchor, reduced: reduceMotion)
        guard next != signature else { return }
        let oldAnchor = signature?.anchor
        stop()
        signature = next; self.reduceMotion = reduceMotion
        var initial = seeds
        for path in paths { if let point = points[path] { initial[path] = point } }
        if let anchor, oldAnchor != anchor { initial[anchor] = seeds[anchor] ?? .zero }
        physics = GraphPhysics(paths: paths, links: links, seeds: initial, anchor: anchor)
        points = physics?.points ?? [:]
        if !reduceMotion { start() }
    }
    func beginDrag(_ path: String) {
        physics?.beginDrag(path)
        if !reduceMotion && !isAnimating { start() }
    }
    func drag(_ path: String, to point: CGPoint) {
        physics?.drag(path, to: point)
        points = physics?.points ?? [:]
        if !reduceMotion && !isAnimating { start() }
    }
    func endDrag() {
        physics?.endDrag()
        if !reduceMotion { start() }
    }
    func reset() { stop(); signature = nil; physics = nil; points = [:] }
    func stop() { timer?.invalidate(); timer = nil; isAnimating = false; stepsLeft = 0; quietSteps = 0; deadline = 0 }
    private func start() {
        guard !reduceMotion, (physics?.paths.count ?? 0) > 1 else { return }
        let crowded = (physics?.paths.count ?? 0) > 120 || (signature?.links.count ?? 0) > 2000
        timer?.invalidate(); stepsLeft = crowded ? 80 : 150; quietSteps = 0
        deadline = ProcessInfo.processInfo.systemUptime + 5; isAnimating = true
        let tick = Timer(timeInterval: crowded ? 1.0 / 20.0 : 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.stepsLeft > 0, ProcessInfo.processInfo.systemUptime < self.deadline, var model = self.physics else { self.stop(); return }
            let movement = model.step(); self.physics = model; self.points = model.points
            self.stepsLeft -= 1
            self.quietSteps = movement < 0.00012 ? self.quietSteps + 1 : 0
            if self.quietSteps >= 10 || self.stepsLeft == 0 { self.stop() }
        }
        timer = tick; RunLoop.main.add(tick, forMode: .common)
    }
    deinit { timer?.invalidate() }
}
