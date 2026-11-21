@testable import KasterCore
import Foundation

// Editor responsiveness at 10,000 cards. Prints timings; fails only on clear regressions.
func ms(_ body: () -> Void) -> Double { let t = Date(); body(); return Date().timeIntervalSince(t) * 1000 }
func average(_ runs: Int, _ body: () -> Void) -> Double { (0..<runs).map { _ in ms(body) }.reduce(0, +) / Double(runs) }

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("kaster-perf-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
defer { try? manager.removeItem(at: root) }
let count = Int(ProcessInfo.processInfo.environment["KASTER_PERF_CARDS"] ?? "10000")!
for folder in ["Zettel", "Research", "Quick", "Bibliography"] { try! manager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true) }
let body = String(repeating: "Some thinking about cards and links, with *emphasis* and a #tag. ", count: 12)
for i in 0..<count {
    let folder = ["Zettel", "Research", "Quick", "Bibliography"][i % 4]
    let id = folder == "Zettel" ? "\(i / 4 + 1)" : nil
    let name = id.map { "\($0)-Card \(i)" } ?? "Card \(i)"
    let front = "---\nuid: u\(i)\n" + (id.map { "card_id: \"\($0)\"\n" } ?? "") + "order: \((i * 7919) % count)\n---\n"
    let text = front + "# Card \(i)\n\n\(body)\n\nSee [[Card \((i + 1) % count)]] and [[\(i % 4 == 0 ? "\(i / 4 + 2)-Card \(i + 4)" : "Card \(i + 2)")]].\n" + (folder == "Research" ? "\nSource: [[Card \(i - 1)]], p. 4\n" : "")
    try! Data(text.utf8).write(to: root.appendingPathComponent(folder).appendingPathComponent(name + ".md"))
}
let snapshot = LibrarySnapshot.load(folder: root)!
precondition(snapshot.cards.count == count)
let target = snapshot.cards[count / 2].url
var results: [(String, Double)] = []
results.append(("Full library scan", ms { _ = LibrarySnapshot.load(folder: root) }))
// Before: linear lookups resolving every path.
results.append(("card(for:) linear", average(3) { _ = snapshot.cards.first { $0.url.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL } }))
results.append(("Manual-order sort (parse in comparator)", ms { _ = snapshot.cards.sorted { (KasterFrontmatter.order(in: $0.content) ?? 0) < (KasterFrontmatter.order(in: $1.content) ?? 0) } }))
results.append(("Bibliography filter via infer", average(3) { _ = snapshot.cards.filter { KasterMode.infer(url: $0.url, root: root, text: $0.content) == .bibliography } }))
results.append(("ID scan of all files", ms { _ = try? BranchIDs.existing(in: [root]) }))
// After: the shared index.
var index: LibraryIndex!
results.append(("Build LibraryIndex", ms { index = LibraryIndex(snapshot: snapshot, root: root) }))
results.append(("card(for:) indexed", average(50) { _ = index.card(for: target) }))
results.append(("backlinks indexed", average(50) { _ = index.backlinks(for: target) }))
results.append(("Manual-order sort (precomputed)", ms { _ = index.sortedByOrder(snapshot.cards) }))
results.append(("Bibliography list indexed", average(50) { _ = index.cards(in: .bibliography) }))
results.append(("ID set from index", average(50) { _ = index.ids }))
let changed = snapshot.cards[10].url
try! Data((try! String(contentsOf: changed, encoding: .utf8) + "\nMore [[Card 3]].\n").utf8).write(to: changed)
var updated: LibrarySnapshot!
results.append(("Incremental update of one saved card", average(5) { updated = snapshot.updating([changed], root: root) }))
precondition(updated.cards.count == count && updated.outgoing[updated.cards[10].path]?.contains(where: { $0.hasSuffix("Card 3") }) == true, "Incremental update sees the new link")
let fresh = LibrarySnapshot.load(folder: root)!
precondition(Set(fresh.incoming.keys) == Set(updated.incoming.keys) && fresh.outgoing.mapValues(Set.init) == updated.outgoing.mapValues(Set.init), "Incremental update matches a full scan")
// Saved library: written after a scan, read back at launch before the real scan finishes.
results.append(("Save library cache", ms { LibraryCache.save(fresh, modified: [:], created: [:], root: root) }))
var cached: LibrarySnapshot?
results.append(("Load library cache (launch head start)", ms { cached = LibraryCache.load(root: root)?.snapshot }))
precondition(cached?.cards.count == count && cached?.cards.map(\.path) == fresh.cards.map(\.path) && cached?.incoming.count == fresh.incoming.count, "The cache restores the same cards and links")
precondition(LibraryCache.load(root: root.appendingPathComponent("Zettel")) == nil, "A cache never applies to another folder")
if let file = LibraryCache.file(for: root) { try? manager.removeItem(at: file) }
for (name, value) in results { print(String(format: "%-44@ %9.2f ms", name as NSString, value)) }
let lookup = results.first { $0.0 == "card(for:) indexed" }!.1, inc = results.first { $0.0 == "Incremental update of one saved card" }!.1
precondition(lookup < 1 && inc < 150, "Indexed lookups must stay under 1 ms and incremental updates under 150 ms")
print("Performance at \(count) cards passed")
