import SwiftUI
import AppKit

// Library data is read-only: filenames and note contents are never changed by browsing.
struct LibraryCard: Identifiable {
    let url: URL
    let path: String
    let title: String
    let cardID: String?
    let content: String
    var id: String { path }
    var canLink: Bool { CardifyNote(path: path).canLink }
}

struct LibrarySnapshot {
    let cards: [LibraryCard]
    let outgoing: [String: [String]]
    let incoming: [String: [String]]
    let unreadable: Int

    static func load(folder: URL) -> LibrarySnapshot? {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var unreadable = 0
        guard manager.isReadableFile(atPath: folder.path),
              let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in unreadable += 1; return true }) else { return nil }
        let root = folder.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var cards: [LibraryCard] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { unreadable += 1; continue }
            if values.isSymbolicLink == true { if values.isDirectory == true { enumerator.skipDescendants() }; continue }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            let fullPath = url.standardizedFileURL.path
            guard fullPath.hasPrefix(prefix) else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { unreadable += 1; continue }
            let relative = String(fullPath.dropFirst(prefix.count))
            let path = String(relative.dropLast(url.pathExtension.count + 1))
            let heading = NoteEditing.title(in: content).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = heading.isEmpty ? url.deletingPathExtension().lastPathComponent : heading
            let cardID = CardMetadata.parse(content).id ?? BranchIDs.filenameID(for: url) ?? BranchIDs.luhmannFilenameID(for: url)
            cards.append(LibraryCard(url: url, path: path, title: title, cardID: cardID, content: content))
        }
        cards.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let links = LibraryLinks.build(cards: cards)
        return LibrarySnapshot(cards: cards, outgoing: links.outgoing, incoming: links.incoming, unreadable: unreadable)
    }
}

enum LibrarySearch {
    static func matches(_ card: LibraryCard, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || card.path.localizedCaseInsensitiveContains(q) || card.title.localizedCaseInsensitiveContains(q) || (card.cardID?.localizedCaseInsensitiveContains(q) ?? false) || card.content.localizedCaseInsensitiveContains(q)
    }
}

enum LibraryLinks {
    // Resolve only unambiguous paths or names. Ambiguous links are not presented as backlinks.
    static func build(cards: [LibraryCard]) -> (outgoing: [String: [String]], incoming: [String: [String]]) {
        var byPath: [String: [String]] = [:]
        var byName: [String: [String]] = [:]
        for card in cards {
            byPath[card.path.lowercased(), default: []].append(card.path)
            byName[(card.path as NSString).lastPathComponent.lowercased(), default: []].append(card.path)
        }
        var outgoing: [String: [String]] = [:]
        var incoming: [String: [String]] = [:]
        let regex = try! NSRegularExpression(pattern: #"(?<!!)\[\[([^\]\r\n]+)\]\]"#)
        for source in cards {
            let value = source.content as NSString
            var seen: Set<String> = []
            for match in regex.matches(in: source.content, range: NSRange(location: 0, length: value.length)) {
                var target = value.substring(with: match.range(at: 1))
                target = String(target.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
                target = String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                if target.lowercased().hasSuffix(".md") { target = String(target.dropLast(3)) }
                guard !target.isEmpty else { continue }
                if target.hasPrefix("/") { target.removeFirst() }
                // An unqualified name shared by multiple files is ambiguous,
                // even when one happens to live at the vault root.
                if !target.contains("/"), (byName[target.lowercased()]?.count ?? 0) > 1 { continue }
                var matches = byPath[target.lowercased()] ?? []
                if matches.isEmpty && (target.hasPrefix("./") || target.hasPrefix("../")) {
                    let folder = (source.path as NSString).deletingLastPathComponent
                    let joined = ("/" + folder + "/" + target as NSString).standardizingPath
                    matches = byPath[String(joined.dropFirst()).lowercased()] ?? []
                }
                if matches.isEmpty && !target.contains("/") { matches = byName[target.lowercased()] ?? [] }
                guard matches.count == 1, let resolved = matches.first, seen.insert(resolved).inserted else { continue }
                outgoing[source.path, default: []].append(resolved)
                incoming[resolved, default: []].append(source.path)
            }
        }
        return (outgoing, incoming)
    }
}

// These are address-shape hints, not assertions about why two notes were created.
enum LibrarySequence {
    static func components(_ id: String) -> (prefix: String, suffix: String)? {
        guard !id.isEmpty,
              id.range(of: #"^[0-9]{12}"#, options: .regularExpression) == nil,
              id.range(of: #"^[0-9]+(?:[.,/][0-9]+)?(?:[A-Za-z]+[0-9]*)*$"#, options: .regularExpression) != nil else { return nil }
        let chars = Array(id)
        guard let last = chars.last else { return nil }
        let isNumber = last.isNumber
        var index = chars.count - 1
        while index > 0 && chars[index - 1].isNumber == isNumber { index -= 1 }
        return (String(chars[..<index]), String(chars[index...]))
    }
    static func hints(for card: LibraryCard, in cards: [LibraryCard]) -> [(String, LibraryCard)] {
        guard let id = card.cardID, let parts = components(id) else { return [] }
        // Duplicate IDs make any inferred address relationship unreliable.
        let counts = Dictionary(grouping: cards.compactMap { $0.cardID?.lowercased() }, by: { $0 }).mapValues { $0.count }
        guard counts[id.lowercased()] == 1 else { return [] }
        let eligible = cards.filter { $0.path != card.path && $0.cardID.map { counts[$0.lowercased()] == 1 && components($0) != nil } == true }
        var result: [(String, LibraryCard)] = []
        if !parts.prefix.isEmpty, let parent = eligible.first(where: { $0.cardID?.caseInsensitiveCompare(parts.prefix) == .orderedSame }) {
            result.append(("Possible parent", parent))
        }
        let siblings = eligible.filter { other in
            guard let otherID = other.cardID, let otherParts = components(otherID) else { return false }
            return otherParts.prefix.caseInsensitiveCompare(parts.prefix) == .orderedSame && otherParts.suffix.first?.isNumber == parts.suffix.first?.isNumber
        } + [card]
        let sorted = siblings.sorted { ($0.cardID ?? "").localizedStandardCompare($1.cardID ?? "") == .orderedAscending }
        if let index = sorted.firstIndex(where: { $0.path == card.path }) {
            if index > 0 { result.append(("Previous in sequence", sorted[index - 1])) }
            if index + 1 < sorted.count { result.append(("Next in sequence", sorted[index + 1])) }
        }
        for child in eligible where components(child.cardID!)?.prefix.caseInsensitiveCompare(id) == .orderedSame {
            result.append(("Possible branch", child))
        }
        return result
    }
}

struct CardLibrary: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("saveFolder") private var saveFolder = ""
    let currentURL: URL?
    let allowInsert: Bool
    let onOpen: (URL) -> Void
    let onInsert: (String) -> Void
    @State private var query = ""
    @State private var explanation = ""
    @State private var selected: String?
    @State private var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @State private var message = "Choose a notes folder to get started."
    @State private var scanID = UUID()
    @State private var tab = "cards"

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var matches: [LibraryCard] {
        snapshot.cards.filter { LibrarySearch.matches($0, query: query) }
    }
    private var current: LibraryCard? { snapshot.cards.first { $0.path == selected } }
    private func card(_ path: String) -> LibraryCard? { snapshot.cards.first { $0.path == path } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Library").font(.title2.bold())
                Spacer()
                Button("Choose Folder…", action: chooseFolder)
                Button("Refresh", action: scan).disabled(folder.isEmpty)
            }
            Text(folder.isEmpty ? "No notes folder selected" : folder).font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Picker("Library view", selection: $tab) { Text("Cards").tag("cards"); Text("Index").tag("index") }.pickerStyle(.segmented).frame(width: 190)
            if tab == "index" {
                CuratedIndexView(cards: snapshot.cards, onOpen: { url in
                    if let note = snapshot.cards.first(where: { $0.url == url }) { query = ""; selected = note.path; tab = "cards" }
                }, onRefresh: scan)
            } else {
                TextField("Search titles, IDs, filenames, or note text", text: $query)
                Text(message).font(.caption).foregroundStyle(.secondary)
                HSplitView {
                    List(matches, selection: $selected) { note in
                        VStack(alignment: .leading) {
                            Text(note.title).fontWeight(.medium).lineLimit(1)
                            Text([note.cardID, note.path].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.tag(note.path)
                    }.frame(minWidth: 220)
                    ScrollView {
                        if let note = current {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(note.title).font(.headline)
                                Text(note.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let id = note.cardID { Text("ID: \(id)").font(.caption) }
                                HStack {
                                    Button("Open Card") { onOpen(note.url); dismiss() }
                                    Button("Insert Link") {
                                        let context = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                                        onInsert(CardifyNote(path: note.path).wikiLink + (context.isEmpty ? "" : " — " + context)); dismiss()
                                    }.disabled(!note.canLink || !allowInsert)
                                }
                                if allowInsert {
                                    TextField("Why is this card related? (optional)", text: $explanation)
                                } else {
                                    Text("Switch to Markdown to insert a link into a draft.").font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                                connectionSection("Links to", paths: snapshot.outgoing[note.path] ?? [])
                                connectionSection("Linked from", paths: snapshot.incoming[note.path] ?? [])
                                let sequence = LibrarySequence.hints(for: note, in: snapshot.cards)
                                if !sequence.isEmpty {
                                    Text("Nearby IDs").font(.subheadline.bold())
                                    Text("Inferred from addresses; not necessarily an intentional relationship.").font(.caption).foregroundStyle(.secondary)
                                    ForEach(Array(sequence.enumerated()), id: \.offset) { _, item in
                                        Button("\(item.0): \(item.1.cardID ?? "") · \(item.1.title)") { query = ""; selected = item.1.path }.buttonStyle(.link)
                                    }
                                }
                                Divider()
                                Text("Note text").font(.subheadline.bold())
                                Text(CardMetadata.parse(note.content).body).font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        } else {
                            Text("Select a card to see its connections.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
                        }
                    }.frame(minWidth: 300)
                }
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(22).frame(minWidth: 760, minHeight: 520)
        .onAppear { if !folder.isEmpty { scan() } }
        .onChange(of: selected) { _ in explanation = "" }
    }
    @ViewBuilder private func connectionSection(_ title: String, paths: [String]) -> some View {
        Text("\(title) (\(paths.count))").font(.subheadline.bold())
        if paths.isEmpty { Text("None found").font(.caption).foregroundStyle(.secondary) }
        ForEach(paths, id: \.self) { path in
            if let target = card(path) {
                Button(target.title) { query = ""; selected = target.path }.buttonStyle(.link)
            }
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            notesFolder = url.path; selected = nil
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
            scan()
        }
    }
    private func scan() {
        guard !folder.isEmpty else { message = "Choose a notes folder to get started."; return }
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let id = UUID(); scanID = id; message = "Searching for cards…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = LibrarySnapshot.load(folder: url)
            DispatchQueue.main.async {
                guard id == scanID else { return }
                guard let result else {
                    snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0); selected = nil
                    message = "Could not read the notes folder. Choose it again."; return
                }
                snapshot = result
                if let selected, !result.cards.contains(where: { $0.path == selected }) { self.selected = nil }
                if self.selected == nil, let currentURL, let card = result.cards.first(where: { $0.url.standardizedFileURL == currentURL.standardizedFileURL }) { self.selected = card.path }
                message = "\(result.cards.count) Markdown cards" + (result.unreadable > 0 ? "; \(result.unreadable) could not be read." : ".")
            }
        }
    }
}
