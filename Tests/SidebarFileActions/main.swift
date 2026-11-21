@testable import KasterCore
import Foundation

let manager = FileManager.default
let directory = manager.temporaryDirectory.appendingPathComponent("cardify-sidebar-\(UUID().uuidString)", isDirectory: true)
try manager.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: directory) }
let original = directory.appendingPathComponent("202611131437 Ideas.md")
let markdown = "\u{feff}---\r\ncard_id: \"202611131437\"\r\ntags: [research]\r\n---\r\n# An idea\r\nBody 🗂\r\n"
try Data(markdown.utf8).write(to: original)
let snapshot = try SidebarFileActions.capture(original, root: directory)
precondition(snapshot.cardID == "202611131437" && snapshot.bytes == Data(markdown.utf8))

func fails(_ action: () throws -> Void) -> Bool {
    do { try action(); return false } catch { return true }
}

// The file actions only plan; the journaled engine performs each one, as the app does.
let engine = VaultChanges(journalFolder: directory.appendingPathComponent(".journal", isDirectory: true))
func moveCard(_ snapshot: SidebarFileActions.Snapshot, to folder: URL, openURLs: [URL]) throws -> URL {
    let destination = try SidebarFileActions.moveDestination(snapshot, to: folder, openURLs: openURLs)
    if destination.standardizedFileURL != snapshot.url { try engine.apply(VaultChange(summary: "Move", steps: [.move(snapshot.url.path, destination.path)])) }
    return destination
}
func renameCard(_ snapshot: SidebarFileActions.Snapshot, filename: String, openURLs: [URL]) throws -> URL {
    let destination = try SidebarFileActions.renameDestination(snapshot, filename: filename, openURLs: openURLs)
    try engine.apply(VaultChange(summary: "Rename", steps: [.move(snapshot.url.path, destination.path)]))
    return destination
}
func duplicateCard(_ snapshot: SidebarFileActions.Snapshot, openURLs: [URL], allowOpen: Bool = false) throws -> URL {
    let copy = try SidebarFileActions.duplicateCopy(snapshot, openURLs: openURLs, allowOpen: allowOpen)
    try engine.apply(VaultChange(summary: "Duplicate", steps: [.write(copy.url.path, Data(copy.text.utf8))]))
    return copy.url
}
func retitleCard(_ snapshot: SidebarFileActions.Snapshot, newText: String, filename: String, openURLs: [URL]) throws -> URL {
    let destination = try SidebarFileActions.retitleDestination(snapshot, filename: filename, openURLs: openURLs)
    var steps: [VaultChange.Step] = [.write(snapshot.url.path, Data(newText.utf8))]
    if destination.path != snapshot.url.path { steps.append(.move(snapshot.url.path, destination.path)) }
    try engine.apply(VaultChange(summary: "Retitle", steps: steps))
    return destination
}
let destinationFolder = directory.appendingPathComponent("Research")
try manager.createDirectory(at: destinationFolder, withIntermediateDirectories: false)
precondition(fails { _ = try moveCard(snapshot, to: destinationFolder, openURLs: [original]) }, "Open notes cannot move through the basic file action")
let occupiedInFolder = destinationFolder.appendingPathComponent(original.lastPathComponent)
try Data("different".utf8).write(to: occupiedInFolder)
precondition(fails { _ = try moveCard(snapshot, to: destinationFolder, openURLs: []) }, "Moving must not overwrite an existing note")
precondition((try? Data(contentsOf: occupiedInFolder)) == Data("different".utf8))
try manager.removeItem(at: occupiedInFolder)
let outsideFolder = manager.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
try manager.createDirectory(at: outsideFolder, withIntermediateDirectories: false)
defer { try? manager.removeItem(at: outsideFolder) }
precondition(fails { _ = try moveCard(snapshot, to: outsideFolder, openURLs: []) }, "Moving outside the notes root must fail")
let movedIntoFolder = try moveCard(snapshot, to: destinationFolder, openURLs: [])
precondition((try? Data(contentsOf: movedIntoFolder)) == snapshot.bytes && !manager.fileExists(atPath: original.path), "Moving keeps the note bytes and removes its old path")
let movedBack = try moveCard(SidebarFileActions.capture(movedIntoFolder, root: directory), to: directory, openURLs: [])
precondition(movedBack == original && (try? Data(contentsOf: original)) == snapshot.bytes)
precondition(fails { _ = try renameCard(snapshot, filename: "../escape.md", openURLs: []) })
precondition(fails { _ = try renameCard(snapshot, filename: "renamed.md", openURLs: [original]) })
precondition(fails { _ = try duplicateCard(snapshot, openURLs: [original]) })
let hardlink = directory.appendingPathComponent("hardlinked.md")
try manager.linkItem(at: original, to: hardlink)
precondition(fails { _ = try renameCard(snapshot, filename: "renamed.md", openURLs: [hardlink]) }, "An open hardlink still refers to the same file")
try SidebarFileActions.validateActive(snapshot, activeURL: original, activeDiskSnapshot: snapshot.bytes, otherOpenURLs: [])
precondition(fails { try SidebarFileActions.validateActive(snapshot, activeURL: original, activeDiskSnapshot: nil, otherOpenURLs: []) }, "Active notes need a verified saved baseline")
precondition(fails { try SidebarFileActions.validateActive(snapshot, activeURL: original, activeDiskSnapshot: Data("old".utf8), otherOpenURLs: []) }, "Active notes cannot use a stale saved baseline")
precondition(fails { try SidebarFileActions.validateActive(snapshot, activeURL: hardlink, activeDiskSnapshot: snapshot.bytes, otherOpenURLs: []) }, "A hardlink is not the active pathname")
precondition(fails { try SidebarFileActions.validateActive(snapshot, activeURL: original, activeDiskSnapshot: snapshot.bytes, otherOpenURLs: [hardlink]) }, "An alias open in another mode blocks file mutations")
precondition(fails { try SidebarFileActions.validateActive(snapshot, activeURL: original, activeDiskSnapshot: snapshot.bytes, otherOpenURLs: [original]) }, "The same path open in another mode blocks file mutations")
let duplicate = try duplicateCard(snapshot, openURLs: [original], allowOpen: true)
let copied = String(decoding: try Data(contentsOf: duplicate), as: UTF8.self)
precondition(duplicate.lastPathComponent == "Copy of 202611131437 Ideas.md")
precondition(copied == "\u{feff}---\r\ntags: [research]\r\n---\r\n# An idea\r\nBody 🗂\r\n")
precondition(CardMetadata.parse(copied).id == nil && BranchIDs.filenameID(for: duplicate) == nil)
let duplicate2 = try duplicateCard(snapshot, openURLs: [])
precondition(duplicate2.lastPathComponent == "Copy of 202611131437 Ideas 2.md")
let originalBytes = try Data(contentsOf: original)
precondition(originalBytes == snapshot.bytes)

let occupied = directory.appendingPathComponent("Occupied.md")
try Data("other note".utf8).write(to: occupied)
precondition(fails { _ = try renameCard(snapshot, filename: "Occupied.md", openURLs: []) })
let occupiedBytes = try Data(contentsOf: occupied)
precondition(occupiedBytes == Data("other note".utf8))
let plainSnapshot = try SidebarFileActions.capture(occupied, root: directory)
precondition(fails { _ = try renameCard(plainSnapshot, filename: "99 Occupied.md", openURLs: []) }, "Rename must not introduce a new filename ID")
precondition(fails { _ = try renameCard(snapshot, filename: "Renamed.md", openURLs: []) }, "Timestamp filename IDs must remain stable")
let renamed = try renameCard(snapshot, filename: "202611131437 Renamed.md", openURLs: [])
let renamedBytes = try Data(contentsOf: renamed)
precondition(renamedBytes == snapshot.bytes && !manager.fileExists(atPath: original.path))

let renamedSnapshot = try SidebarFileActions.capture(renamed, root: directory)
try Data("external change".utf8).write(to: renamed)
precondition(fails { _ = try duplicateCard(renamedSnapshot, openURLs: []) })
precondition(fails { _ = try renameCard(renamedSnapshot, filename: "Never.md", openURLs: []) })
let changedBytes = try Data(contentsOf: renamed)
precondition(changedBytes == Data("external change".utf8))

for id in ["13-11-26", "1a", "AFF-01-OB-01"] {
    let file = directory.appendingPathComponent("\(id) Original.md")
    try Data("# Note".utf8).write(to: file)
    let identifierSnapshot = try SidebarFileActions.capture(file, root: directory)
    precondition(fails { _ = try renameCard(identifierSnapshot, filename: "No ID.md", openURLs: []) }, "Filename ID \(id) must be retained")
    let sameID = try renameCard(identifierSnapshot, filename: "\(id) New title.md", openURLs: [])
    precondition(manager.fileExists(atPath: sameID.path))
}

let malformed = directory.appendingPathComponent("bad.md")
try Data("---\ncard_id: \"unfinished\n---\n# Bad\n".utf8).write(to: malformed)
let invalidSnapshot = try SidebarFileActions.capture(malformed, root: directory)
precondition(fails { _ = try duplicateCard(invalidSnapshot, openURLs: []) })
let malformedRenamed = try renameCard(invalidSnapshot, filename: "bad-renamed.md", openURLs: [])
precondition((try? Data(contentsOf: malformedRenamed)) == invalidSnapshot.bytes)
let invalidBytesURL = directory.appendingPathComponent("invalid-bytes.md")
let invalidBytes = Data([0xff, 0xfe])
try invalidBytes.write(to: invalidBytesURL)
let invalidBytesSnapshot = try SidebarFileActions.capture(invalidBytesURL, root: directory)
precondition(fails { _ = try duplicateCard(invalidBytesSnapshot, openURLs: []) })
let invalidBytesRenamed = try renameCard(invalidBytesSnapshot, filename: "invalid-renamed.md", openURLs: [])
precondition((try? Data(contentsOf: invalidBytesRenamed)) == invalidBytes)
let commented = directory.appendingPathComponent("commented.md")
try Data("---\ncard_id: \"a#b\" # This comment matters\ntags: research\n---\n# Note\n".utf8).write(to: commented)
let commentedSnapshot = try SidebarFileActions.capture(commented, root: directory)
precondition(fails { _ = try duplicateCard(commentedSnapshot, openURLs: []) }, "Inline ID comments must not be discarded")
let quotedHash = directory.appendingPathComponent("quoted.md")
try Data("---\ncard_id: \"a#b\"\ntags: research\n---\n# Note\n".utf8).write(to: quotedHash)
let quotedCopy = try duplicateCard(SidebarFileActions.capture(quotedHash, root: directory), openURLs: [])
precondition((try? String(contentsOf: quotedCopy, encoding: .utf8)) == "---\ntags: research\n---\n# Note\n", "Quoted # is not an inline YAML comment")
let target = manager.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).md")
try Data("# Outside".utf8).write(to: target)
defer { try? manager.removeItem(at: target) }
let link = directory.appendingPathComponent("link.md")
try manager.createSymbolicLink(at: link, withDestinationURL: target)
precondition(fails { _ = try SidebarFileActions.capture(link, root: directory) })
precondition(fails { _ = try SidebarFileActions.capture(target, root: directory) })
print("Sidebar file snapshots, safe rename, ID-free duplicate, stale changes and symlink rejection passed")

// Retitle: new contents + new filename in one step; IDs stay; failures restore the original bytes.
let retitleSource = directory.appendingPathComponent("202611131500 Draft.md")
let retitleText = "---\ncard_id: \"202611131500\"\n---\n# Draft\n\nBody\n"
try Data(retitleText.utf8).write(to: retitleSource)
let retitleSnapshot = try SidebarFileActions.capture(retitleSource, root: directory)
precondition(fails { _ = try retitleCard(retitleSnapshot, newText: "x", filename: "Final.md", openURLs: []) }, "Retitle keeps the filename ID")
precondition((try? String(contentsOf: retitleSource, encoding: .utf8)) == retitleText, "A refused retitle leaves the file untouched")
precondition(fails { _ = try retitleCard(retitleSnapshot, newText: "x", filename: "202611131500 Final.md", openURLs: [retitleSource]) }, "Open cards are protected")
let newText = retitleText.replacingOccurrences(of: "# Draft", with: "# Final")
let retitledURL = try retitleCard(retitleSnapshot, newText: newText, filename: "202611131500 Final.md", openURLs: [])
precondition(retitledURL.lastPathComponent == "202611131500 Final.md" && !manager.fileExists(atPath: retitleSource.path))
precondition((try? String(contentsOf: retitledURL, encoding: .utf8)) == newText, "Heading and filename change together")
let caseSnapshot = try SidebarFileActions.capture(retitledURL, root: directory)
let caseOnly = try retitleCard(caseSnapshot, newText: newText.replacingOccurrences(of: "# Final", with: "# final"), filename: "202611131500 final.md", openURLs: [])
let listing = try manager.contentsOfDirectory(atPath: directory.path)
precondition(listing.contains("202611131500 final.md") && caseOnly.lastPathComponent == "202611131500 final.md", "Case-only renames work")
let plainZettel = directory.appendingPathComponent("Loose.md")
try Data("---\ncard_id: \"4/1\"\n---\n# Loose\n".utf8).write(to: plainZettel)
let gained = try retitleCard(SidebarFileActions.capture(plainZettel, root: directory), newText: "---\ncard_id: \"4/1\"\n---\n# Tight\n", filename: "4-1-Tight.md", openURLs: [])
precondition(gained.lastPathComponent == "4-1-Tight.md", "A filename without an ID may gain the card's metadata ID")
print("Sidebar retitle: ID safety, open-card protection, case-only and atomic contents passed")
