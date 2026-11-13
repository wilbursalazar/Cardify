import Foundation
import CoreGraphics

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let seed = ["A": CGPoint(x: -0.7, y: 0), "B": CGPoint(x: 0.7, y: 0)]
let links = [GraphPhysics.Link("A", "B")]
var first = GraphPhysics(paths: ["A", "B"], links: links, seeds: seed, anchor: nil)
var second = GraphPhysics(paths: ["B", "A"], links: links, seeds: seed, anchor: nil)
for _ in 0..<100 { first.step(); second.step() }
check(first.points == second.points, "same graph gives deterministic motion")
check(abs(first.points["A"]!.x - first.points["B"]!.x) < 1.4, "a link pulls cards toward each other")
var anchored = GraphPhysics(paths: ["A", "B"], links: links, seeds: seed, anchor: "A")
for _ in 0..<40 { anchored.step() }
check(anchored.points["A"] == seed["A"], "local center stays anchored")
anchored.beginDrag("A"); anchored.drag("A", to: CGPoint(x: 0.3, y: 0.4)); anchored.endDrag()
check(anchored.points["A"] == CGPoint(x: 0.3, y: 0.4), "drag moves the anchored card")
let moved = anchored.points["A"]!
for _ in 0..<20 { anchored.step() }
check(anchored.points["A"] != moved, "dragging releases the anchor")
let names = (0..<250).map { "card\($0)" }
var large = GraphPhysics(paths: names, links: [], seeds: [:], anchor: nil)
check(large.points.count == 180, "physics caps work at 180 visible nodes")
for _ in 0..<150 { large.step() }
check(large.points.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 0.97 && abs($0.y) <= 0.97 }, "large graph stays finite and within bounds")
var collisions = GraphPhysics(paths: ["A", "B"], links: [], seeds: ["A": .zero, "B": .zero], anchor: nil)
for _ in 0..<50 { collisions.step() }
check(collisions.points["A"] != collisions.points["B"], "coincident cards repel")
let controller = GraphMotionController()
controller.configure(paths: ["A", "B"], links: links, seeds: seed, anchor: nil, reduceMotion: false)
check(controller.isAnimating, "animation starts for a graph")
RunLoop.main.run(until: Date().addingTimeInterval(0.15))
let beforeSameTopology = controller.points
controller.configure(paths: ["B", "A"], links: links, seeds: seed, anchor: nil, reduceMotion: false)
check(controller.points == beforeSameTopology, "unchanged topology does not reset positions")
controller.stop()
let stopped = controller.points
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
check(!controller.isAnimating && controller.points == stopped, "stopping invalidates the timer")
let finite = GraphMotionController()
finite.configure(paths: ["A", "B"], links: links, seeds: seed, anchor: nil, reduceMotion: false)
let end = Date().addingTimeInterval(6)
while finite.isAnimating && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
check(!finite.isAnimating, "animation stops automatically after settling or its time limit")
controller.configure(paths: ["A", "B"], links: links, seeds: seed, anchor: nil, reduceMotion: true)
let reduced = controller.points
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
check(!controller.isAnimating && controller.points == reduced, "Reduce Motion disables automatic movement")
controller.beginDrag("A"); controller.drag("A", to: CGPoint(x: 0.2, y: 0.2)); controller.endDrag()
check(controller.points["A"] == CGPoint(x: 0.2, y: 0.2) && !controller.isAnimating, "direct dragging works with Reduce Motion")
controller.reset()
check(controller.points.isEmpty && !controller.isAnimating, "closing clears the animation")
print("Deterministic graph motion, attraction, repulsion, drag, 180-node bounds, Reduce Motion, and timer cleanup passed")
