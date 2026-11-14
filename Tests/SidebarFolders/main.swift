import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent("cardify-folders-" + UUID().uuidString, isDirectory: true)
let manager = FileManager.default
try manager.createDirectory(at: root.appendingPathComponent("Research/Theology"), withIntermediateDirectories: true)
try manager.createDirectory(at: root.appendingPathComponent("Empty"), withIntermediateDirectories: true)
try manager.createDirectory(at: root.appendingPathComponent(".Hidden/Child"), withIntermediateDirectories: true)
try manager.createDirectory(at: root.appendingPathComponent("Bundle.app/Contents"), withIntermediateDirectories: true)
try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundlePackageType</key><string>APPL</string></dict></plist>".write(to: root.appendingPathComponent("Bundle.app/Contents/Info.plist"), atomically: true, encoding: .utf8)
try manager.createSymbolicLink(at: root.appendingPathComponent("Linked"), withDestinationURL: root.appendingPathComponent("Research"))
defer { try? manager.removeItem(at: root) }
let folders = SidebarFolders.paths(in: root)
precondition(Set(folders) == ["Research", "Research/Theology", "Empty"], "list real and empty folders without hidden, symlink or package folders: \(folders)")

let cards = ["Root", "Research/Alpha", "Research/Theology/Argument"]
func rowPaths(_ rows: [SidebarFolders.Row]) -> [String] { rows.map(\.path) }
let collapsed = SidebarFolders.rows(folders: folders, cards: cards, expanded: [], query: "")
precondition(rowPaths(collapsed) == ["Empty", "Research", "Root"], "root contains folders first and root note")
precondition(collapsed.allSatisfy { $0.depth == 0 })
let research = SidebarFolders.rows(folders: folders, cards: cards, expanded: ["Research"], query: "")
precondition(rowPaths(research) == ["Empty", "Research", "Research/Theology", "Research/Alpha", "Root"])
precondition(research[2].depth == 1 && research[3].depth == 1)
let expanded = SidebarFolders.rows(folders: folders, cards: cards, expanded: ["Research", "Research/Theology"], query: "")
precondition(rowPaths(expanded).contains("Research/Theology/Argument"))
precondition(expanded.first(where: { $0.path == "Research/Theology/Argument" })?.depth == 2)
let search = SidebarFolders.rows(folders: folders, cards: ["Research/Theology/Argument"], expanded: [], query: "Argument")
precondition(rowPaths(search) == ["Research", "Research/Theology", "Research/Theology/Argument"], "search reveals collapsed ancestor folders")
precondition(search[0].expanded && search[1].expanded)
let emptySearch = SidebarFolders.rows(folders: folders, cards: [], expanded: [], query: "empty")
precondition(rowPaths(emptySearch) == ["Empty"], "search finds empty folders")
precondition(SidebarFolders.ancestors(of: "Research/Theology/Argument") == ["Research", "Research/Theology"])
precondition(SidebarFolders.ancestors(of: "Root").isEmpty)
print("Sidebar folders include safe empty directories, nesting, search, and active-note ancestors")
