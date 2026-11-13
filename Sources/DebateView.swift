import SwiftUI
import AppKit

enum DebateBrowserSafety {
    static func canOpen(_ url: URL, in folder: URL) -> Bool {
        CardGraph.canOpen(url, in: folder)
    }
    static func isRelated(_ info: DebateInfo, to path: String) -> Bool {
        guard info.valid, let primary = info.primary,
              primary.path.caseInsensitiveCompare(path) != .orderedSame else { return false }
        return info.related.contains { $0.path.caseInsensitiveCompare(path) == .orderedSame }
    }
}

// Debate is a view of the same Markdown draft used by Research. No files are
// changed by browsing; relationship actions change only the open draft.
struct DebatePanel: View {
    @Binding var text: String
    @Binding var showBrowser: Bool
    let currentURL: URL?
    let onOpen: (URL) -> Bool
    let onNew: (String) -> Bool
    let onFollowLink: (CardLinkTarget) -> Void
    @State private var message = ""

    private var info: DebateInfo { DebateNotes.parse(text) }
    private var kind: String {
        switch info.role {
        case .project: return "Project"
        case .aff: return "AFF"
        case .def: return "DEF"
        case nil: return info.primary == nil ? "Card" : "Connected card"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button("Browse Debate…") { showBrowser = true }
                Menu("New") {
                    Button("Debate Project") { newRole(.project) }
                    Button("AFF Parent") { newRole(.aff) }
                    Button("DEF Parent") { newRole(.def) }
                }
                Menu("Mark as") {
                    Button("Debate Project") { mark(.project) }
                    Button("AFF Parent") { mark(.aff) }
                    Button("DEF Parent") { mark(.def) }
                }.help("Mark the current draft without renaming the file")
                Spacer(minLength: 0)
                Text(kind).font(.caption).foregroundStyle(.secondary)
            }
            if !info.valid {
                Text("Check the debate relationship lines before editing them.").font(.caption).foregroundStyle(.secondary)
            } else if info.primary != nil || !info.related.isEmpty || !info.projects.isEmpty {
                HStack(spacing: 6) {
                    if let primary = info.primary {
                        Button("Primary parent: \(primary.path)") { onFollowLink(.wiki(primary.path)) }
                            .buttonStyle(.link).font(.caption).lineLimit(1).truncationMode(.middle)
                    } else if !info.related.isEmpty {
                        Text("Choose a primary parent to repair related links.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Connections").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Menu("Links") {
                        if let primary = info.primary {
                            Button("Open primary: \(primary.path)") { onFollowLink(.wiki(primary.path)) }
                            Button("Remove primary parent") { removePrimary() }
                                .disabled(!info.related.isEmpty)
                                .help("Remove related parents first, so connected cards keep a primary parent.")
                        }
                        ForEach(info.related, id: \.path) { relation in
                            Button("Open related: \(relation.path)") { onFollowLink(.wiki(relation.path)) }
                            Button("Remove related: \(relation.path)") { removeRelated(relation.path) }
                        }
                        ForEach(info.projects, id: \.path) { relation in
                            Button("Open project: \(relation.path)") { onFollowLink(.wiki(relation.path)) }
                            Button("Remove project: \(relation.path)") { removeProject(relation.path) }
                        }
                    }
                }
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .sheet(isPresented: $showBrowser) {
            DebateBrowser(text: $text, currentURL: currentURL, onOpen: onOpen, onNew: onNew)
        }
    }
    private func newRole(_ role: DebateRole) {
        let title: String
        switch role { case .project: title = "# \n\nResolution: \n"; case .aff, .def: title = "# \n\n" }
        guard let draft = DebateNotes.setRole(role, in: title) else { message = "Could not create a debate draft."; return }
        if onNew(draft) { message = "New \(role == .project ? "project" : "parent") draft. Save it when ready." }
    }
    private func mark(_ role: DebateRole) {
        guard let updated = DebateNotes.setRole(role, in: text) else { message = "Could not mark this draft. Check its debate metadata."; return }
        text = updated
        message = "Marked this draft. Save to update the debate browser."
    }
    private func removePrimary() {
        guard info.related.isEmpty else { message = "Remove related parents before removing the primary parent."; return }
        guard let updated = DebateNotes.setPrimary(nil, explanation: "", in: text) else { message = "Could not remove the primary parent."; return }
        text = updated; message = "Primary parent removed from the draft. Save to keep it."
    }
    private func removeRelated(_ path: String) {
        guard let updated = DebateNotes.removeRelated(path, in: text) else { message = "Could not remove the related parent."; return }
        text = updated; message = "Related parent removed from the draft. Save to keep it."
    }
    private func removeProject(_ path: String) {
        guard let updated = DebateNotes.removeProject(path, in: text) else { message = "Could not remove the project."; return }
        text = updated; message = "Project removed from the draft. Save to keep it."
    }
}

private struct DebateBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("saveFolder") private var saveFolder = ""
    @Binding var text: String
    let currentURL: URL?
    let onOpen: (URL) -> Bool
    let onNew: (String) -> Bool
    @State private var query = ""
    @State private var selected: String?
    @State private var explanation = ""
    @State private var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @State private var message = "Choose a notes folder to browse debate cards."
    @State private var scanID = UUID()

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var current: LibraryCard? { snapshot.cards.first { $0.path == selected } }
    private var currentInfo: DebateInfo { DebateNotes.parse(text) }
    private var matches: [LibraryCard] {
        snapshot.cards.filter {
            let parsed = DebateNotes.parse($0.content)
            return parsed.valid && parsed.role != nil && LibrarySearch.matches($0, query: query)
        }
    }
    private func samePath(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
    private func roleName(_ role: DebateRole?) -> String {
        switch role { case .project: return "Project"; case .aff: return "AFF"; case .def: return "DEF"; case nil: return "Card" }
    }
    private func linkable(_ card: LibraryCard) -> Bool {
        guard card.canLink, DebateNotes.validPath(card.path), snapshot.unreadable == 0 else { return false }
        guard snapshot.cards.filter({ samePath($0.path, card.path) }).count == 1 else { return false }
        // A root-level filename is an unqualified wiki link, which the library
        // intentionally refuses if another note shares that filename.
        if !card.path.contains("/") {
            return snapshot.cards.filter { samePath(($0.path as NSString).lastPathComponent, card.path) }.count == 1
        }
        return true
    }
    private func canUse(_ card: LibraryCard) -> Bool {
        linkable(card) && card.url.standardizedFileURL != currentURL?.standardizedFileURL
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Debate").font(.title2.bold())
                Spacer()
                Button("Choose Folder…", action: chooseFolder)
                Button("Refresh", action: scan).disabled(folder.isEmpty)
            }
            Text(folder.isEmpty ? "No notes folder selected" : folder).font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            TextField("Search projects, AFF and DEF parents", text: $query)
            Text(message).font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(matches, selection: $selected) { card in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title).fontWeight(.medium).lineLimit(1)
                        Text("\(roleName(DebateNotes.parse(card.content).role)) · \(card.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.tag(card.path)
                }.frame(minWidth: 200)
                ScrollView {
                    if let card = current {
                        let parsed = DebateNotes.parse(card.content)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(card.title).font(.headline)
                            Text("\(roleName(parsed.role)) · \(card.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Button("Open") { open(card) }
                                if parsed.role == .aff || parsed.role == .def {
                                    Button("New connected card") { newChild(card) }.disabled(!linkable(card))
                                }
                            }
                            if !linkable(card) {
                                Text("A connection cannot be safely resolved. Check the filename, duplicate note names, and whether all notes are readable.").font(.caption).foregroundStyle(.secondary)
                            }
                            if parsed.role == .project {
                                HStack {
                                    Button("New AFF in project") { newParent(.aff, project: card) }.disabled(!linkable(card))
                                    Button("New DEF in project") { newParent(.def, project: card) }.disabled(!linkable(card))
                                }
                                Button("Add current parent to project") { changeProject(card) }
                                    .disabled(!canUse(card) || !currentInfo.valid || (currentInfo.role != .aff && currentInfo.role != .def))
                                Divider()
                                connectedSection("Parents in this project", cards: snapshot.cards.filter { candidate in
                                    let info = DebateNotes.parse(candidate.content)
                                    return info.valid && (info.role == .aff || info.role == .def) && info.projects.contains { samePath($0.path, card.path) }
                                })
                            } else if parsed.role == .aff || parsed.role == .def {
                                TextField("Connection (optional)", text: $explanation)
                                HStack {
                                    Button("Set as primary parent") { setPrimary(card) }.disabled(!canUse(card) || !currentInfo.valid)
                                    Button("Add related parent") { addRelated(card) }
                                        .disabled(!canUse(card) || !currentInfo.valid || currentInfo.primary == nil)
                                        .help("Choose a primary parent before adding related parents.")
                                }
                                Divider()
                                connectedSection("Primary cards", cards: snapshot.cards.filter { candidate in
                                    let info = DebateNotes.parse(candidate.content)
                                    return info.valid && info.primary.map { samePath($0.path, card.path) } == true
                                })
                                connectedSection("Related cards", cards: snapshot.cards.filter { candidate in
                                    DebateBrowserSafety.isRelated(DebateNotes.parse(candidate.content), to: card.path)
                                })
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    } else {
                        Text("Select a project or parent to see its connections.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
                    }
                }.frame(minWidth: 360)
            }
            Text("Connections shown here come from saved notes. Save the current draft and refresh to update the list.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(minWidth: 660, minHeight: 460)
            .onAppear { if !folder.isEmpty { scan() } }
    }
    @ViewBuilder private func connectedSection(_ title: String, cards: [LibraryCard]) -> some View {
        Text(title).font(.subheadline.bold())
        if cards.isEmpty { Text("None yet.").font(.caption).foregroundStyle(.secondary) }
        else {
            ForEach(cards) { card in
                Button(card.title) { open(card) }.buttonStyle(.link)
            }
        }
    }
    private func safe(_ card: LibraryCard, requireRole: Bool = false) -> Bool {
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        guard !folder.isEmpty, DebateBrowserSafety.canOpen(card.url, in: root) else {
            message = "This note is no longer safely available in the notes folder. Refresh and try again."
            return false
        }
        if requireRole {
            guard let latest = try? String(contentsOf: card.url, encoding: .utf8),
                  DebateNotes.parse(latest).valid,
                  DebateNotes.parse(latest).role == DebateNotes.parse(card.content).role else {
                message = "This note changed since the last scan. Refresh and try again."
                return false
            }
        }
        return true
    }
    private func open(_ card: LibraryCard) {
        guard safe(card) else { return }
        if onOpen(card.url) { dismiss() }
    }
    private func newChild(_ parent: LibraryCard) {
        guard safe(parent, requireRole: true) else { return }
        guard let draft = DebateNotes.setPrimary(parent.path, explanation: "", in: "# \n\n") else { message = "Could not create a linked card."; return }
        if onNew(draft) { dismiss() }
    }
    private func newParent(_ role: DebateRole, project: LibraryCard) {
        guard safe(project, requireRole: true) else { return }
        guard let marked = DebateNotes.setRole(role, in: "# \n\n"),
              let draft = DebateNotes.addProject(project.path, in: marked) else { message = "Could not create a parent in this project."; return }
        if onNew(draft) { dismiss() }
    }
    private func setPrimary(_ parent: LibraryCard) {
        guard safe(parent, requireRole: true) else { return }
        guard let updated = DebateNotes.setPrimary(parent.path, explanation: explanation, in: text) else { message = "Could not set the primary parent. Check the current note's debate links."; return }
        text = updated
        message = "Primary parent added to the current draft. Save to keep it."
    }
    private func addRelated(_ parent: LibraryCard) {
        guard safe(parent, requireRole: true) else { return }
        guard currentInfo.primary != nil else { message = "Choose a primary parent before adding related parents."; return }
        guard let updated = DebateNotes.addRelated(parent.path, explanation: explanation, in: text) else { message = "Could not add this related parent. Check for duplicate or invalid links."; return }
        text = updated
        message = "Related parent added to the current draft. Save to keep it."
    }
    private func changeProject(_ project: LibraryCard) {
        guard safe(project, requireRole: true) else { return }
        guard let updated = DebateNotes.addProject(project.path, in: text) else { message = "Could not add the project. Check for duplicate or invalid links."; return }
        text = updated
        message = "Project added to the current draft. Save to keep it."
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { notesFolder = url.path; scan() }
    }
    private func scan() {
        guard !folder.isEmpty else { return }
        let url = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let id = UUID(); scanID = id; selected = nil; message = "Searching notes…"
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LibrarySnapshot.load(folder: url)
            DispatchQueue.main.async {
                guard scanID == id else { return }
                guard let found else { message = "Could not open this folder. Choose it again."; return }
                snapshot = found
                let count = found.cards.filter { let info = DebateNotes.parse($0.content); return info.valid && info.role != nil }.count
                message = "\(count) saved debate projects and parents." + (found.unreadable > 0 ? " Some notes could not be read." : "")
            }
        }
    }
}
