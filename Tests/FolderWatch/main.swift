import Foundation

// The library notices Markdown files changed outside Kaster: edits, new files, deletions and new folders.
func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
func until(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { if condition() { return true }; spin(0.05) }
    return condition()
}
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("kaster-watch-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
try! manager.createDirectory(at: root.appendingPathComponent("Zettel"), withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
try! Data("# One\n\nSee [[Two]].\n".utf8).write(to: root.appendingPathComponent("Zettel/One.md"))
let store = LibraryStore()
store.watch(folder: root.path)
store.scan(folder: root.path)
precondition(until(5) { store.snapshot.cards.count == 1 }, "initial scan")
spin(0.5)
try! Data("# Two\n".utf8).write(to: root.appendingPathComponent("Zettel/Two.md"))
precondition(until(5) { store.snapshot.cards.count == 2 && store.index.backlinks(for: root.appendingPathComponent("Zettel/Two.md")).count == 1 }, "a new file and its backlink appear")
try! Data("# One edited\n".utf8).write(to: root.appendingPathComponent("Zettel/One.md"))
precondition(until(5) { store.snapshot.cards.first { $0.path == "Zettel/One" }?.title == "One edited" && store.index.backlinks(for: root.appendingPathComponent("Zettel/Two.md")).isEmpty }, "an outside edit updates title and links")
precondition(until(5) { store.externalChange?.files.contains { $0.lastPathComponent == "One.md" } == true }, "open editors are told which files changed")
try! manager.removeItem(at: root.appendingPathComponent("Zettel/Two.md"))
precondition(until(5) { store.snapshot.cards.count == 1 }, "a deleted file disappears: \(store.snapshot.cards.map(\.path)) external=\(String(describing: store.externalChange?.files))")
try! manager.createDirectory(at: root.appendingPathComponent("Ideas"), withIntermediateDirectories: true)
try! Data("# Three\n".utf8).write(to: root.appendingPathComponent("Ideas/Three.md"))
precondition(until(5) { store.snapshot.cards.count == 2 && store.folderPaths.contains("Ideas") }, "a new folder and its card appear: \(store.folderPaths)")
store.stopWatching()
print("Folder watch: outside edits, new files, deletions and new folders passed")
