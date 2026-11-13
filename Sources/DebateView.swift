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

private func debateStanceLabel(_ stance: DebateStance?) -> String {
    switch stance {
    case .supports: return "Supports parent"
    case .challenges: return "Challenges parent"
    case nil: return "Not specified"
    }
}

// Debate is a view of the same Markdown draft used by Research. No files are
// changed by browsing; relationship actions change only the open draft.
struct DebatePanel: View {
    @Binding var text: String
    @Binding var showBrowser: Bool
    let currentURL: URL?
    let onOpen: (URL) -> Bool
    let onNew: (String, DebateParentReference?) -> Bool
    let onFollowLink: (CardLinkTarget) -> Void
    @State private var message = ""

    private var info: DebateInfo { DebateNotes.parse(text) }
    private var kind: String {
        switch info.role {
        case .project: return "Resolution"
        case .aff: return "AFF"
        case .def: return "DEF"
        case .evidence: return "Evidence"
        case .objection: return "Objection"
        case .argument: return "Argument"
        case .reply: return "Reply"
        case nil: return info.primary == nil ? "Card" : "Connected card"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button("Argument map…") { showBrowser = true }
                Menu("New") {
                    Button("Resolution") { newRole(.project) }
                    Button("Unassigned AFF point") { newRole(.aff) }
                    Button("Unassigned DEF point") { newRole(.def) }
                }
                Menu("Mark as") {
                    Button("Resolution") { mark(.project) }
                    Button("AFF Parent") { mark(.aff) }
                    Button("DEF Parent") { mark(.def) }
                    Divider()
                    Button("Evidence") { mark(.evidence) }
                    Button("Objection") { mark(.objection) }
                    Button("Argument") { mark(.argument) }
                    Button("Reply") { mark(.reply) }
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
                            Button("Open resolution: \(relation.path)") { onFollowLink(.wiki(relation.path)) }
                            Button("Remove resolution: \(relation.path)") { removeProject(relation.path) }
                        }
                    }
                }
            }
            if info.valid, info.primary != nil {
                HStack(spacing: 6) {
                    Text("Relationship to parent").font(.caption).foregroundStyle(.secondary)
                    Menu(debateStanceLabel(info.primaryStance)) {
                        Button("Supports parent") { changeStance(.supports) }
                        Button("Challenges parent") { changeStance(.challenges) }
                        Button("Not specified") { changeStance(nil) }
                    }.help("Describe how this card relates to its immediate parent.")
                }
            }
            if info.role == .project {
                Text(currentURL == nil ? "Enter your resolution as the title, then save it and open the argument map." : "Open the argument map to add AFF and DEF points.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if currentURL == nil && (info.role != nil || info.primary != nil) {
                Text("Give this card a title, write your point, and save it. Open the argument map to continue the chain.")
                    .font(.caption).foregroundStyle(.secondary)
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
        guard let draft = DebateNotes.setRole(role, in: DebateTemplates.body(for: role)) else { message = "Could not create a debate draft."; return }
        if onNew(draft, nil) { message = "New \(role == .project ? "resolution" : "parent") draft. Save it when ready." }
    }
    private func mark(_ role: DebateRole) {
        guard let updated = DebateNotes.setRole(role, in: text) else { message = "Could not mark this draft. Check its debate metadata."; return }
        text = updated
        message = "Marked this draft. Save to update the debate browser."
    }
    private func changeStance(_ stance: DebateStance?) {
        guard let updated = DebateNotes.setStance(stance, in: text) else { message = "Could not update the relationship. Check the card's metadata."; return }
        text = updated
        message = "Relationship updated. Save to keep it."
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
        guard let updated = DebateNotes.removeProject(path, in: text) else { message = "Could not remove the resolution."; return }
        text = updated; message = "Resolution removed from the draft. Save to keep it."
    }
}

private struct DebateBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notesFolder") private var notesFolder = ""
    @AppStorage("saveFolder") private var saveFolder = ""
    @Binding var text: String
    let currentURL: URL?
    let onOpen: (URL) -> Bool
    let onNew: (String, DebateParentReference?) -> Bool
    @State private var query = ""
    @State private var selected: String?
    @State private var projectPath: String?
    @State private var hasLoaded = false
    @State private var loading = false
    @State private var focusMode = false
    @State private var explanation = ""
    @State private var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @State private var message = "Choose a notes folder to browse debate cards."
    @State private var scanID = UUID()

    private var folder: String {
        if !notesFolder.isEmpty { return notesFolder }
        if !saveFolder.isEmpty { return saveFolder }
        return currentURL?.deletingLastPathComponent().path ?? ""
    }
    private var current: LibraryCard? { snapshot.cards.first { $0.path == selected } }
    private var currentInfo: DebateInfo { DebateNotes.parse(text) }
    private var projects: [LibraryCard] { DebateHierarchy.projects(in: snapshot) }
    private var hierarchy: DebateHierarchy { DebateHierarchy.build(snapshot: snapshot, projectPath: projectPath) }
    private var searchResults: [LibraryCard] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return hierarchy.visibleCards.filter { LibrarySearch.matches($0, query: term) }
    }
    private func samePath(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
    private func parentLabel(_ path: String) -> String {
        let matches = snapshot.cards.filter {
            path.contains("/") ? samePath($0.path, path) : samePath(($0.path as NSString).lastPathComponent, path)
        }
        guard (path.contains("/") || snapshot.unreadable == 0), matches.count == 1, let card = matches.first else { return path }
        return DebateHierarchy.displayName(card)
    }
    private func roleName(_ role: DebateRole?) -> String {
        switch role {
        case .project: return "Resolution"
        case .aff: return "AFF"
        case .def: return "DEF"
        case .evidence: return "Evidence"
        case .objection: return "Objection"
        case .argument: return "Argument"
        case .reply: return "Reply"
        case nil: return "Card"
        }
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
        linkable(card) && card.url.resolvingSymlinksInPath().standardizedFileURL != currentURL?.resolvingSymlinksInPath().standardizedFileURL
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Argument map").font(.title2.bold())
                Spacer()
                Button("New resolution") { newResolution() }.disabled(folder.isEmpty || !hasLoaded)
                Button("Choose Folder…", action: chooseFolder)
                Button("Refresh", action: scan).disabled(folder.isEmpty)
            }
            if folder.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Choose a notes folder").font(.headline)
                    Text("Cardify uses this folder to save and connect your debate cards as Markdown.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Choose Notes Folder…", action: chooseFolder).buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else if !hasLoaded {
                VStack(spacing: 10) {
                    if loading { ProgressView() }
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !loading {
                        HStack {
                            Button("Try Again", action: scan)
                            Button("Choose Another Folder…", action: chooseFolder)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
            HStack(spacing: 12) {
                Picker("Resolution", selection: Binding(get: { projectPath }, set: { path in
                    projectPath = path; selected = path; query = ""
                })) {
                    Text("Unassigned").tag(Optional<String>.none)
                    ForEach(projects) { project in Text(DebateHierarchy.displayName(project)).tag(Optional(project.path)) }
                }.frame(maxWidth: 320)
                Picker("View", selection: $focusMode) {
                    Text("Full map").tag(false)
                    Text("Focus").tag(true).disabled(selected == nil)
                }.pickerStyle(.segmented).frame(width: 150)
                    .help("Focus follows the selected card's branch.")
                TextField("Search this map", text: $query).frame(maxWidth: 220)
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Menu("\(searchResults.count) results") {
                        ForEach(searchResults.prefix(100)) { card in
                            Button(DebateHierarchy.displayName(card)) { selected = card.path }
                        }
                    }.disabled(searchResults.isEmpty)
                }
                Spacer()
            }
            Text(message).font(.caption).foregroundStyle(.secondary)
            HSplitView {
                DebateHierarchyView(hierarchy: hierarchy, hasResolutions: !projects.isEmpty, selectedPath: selected,
                                    isFocused: focusMode, onSelect: { selected = $0.path }, onOpen: { open($0) },
                                    onNewResolution: { newResolution() },
                                    onNewPoint: { role, project in newParent(role, project: project) })
                    .frame(minWidth: 520, minHeight: 350)
                ScrollView {
                    if let card = current {
                        let parsed = DebateNotes.parse(card.content)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(roleName(parsed.role)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                if let id = card.cardID, !id.isEmpty {
                                    Text(id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            Text(card.title).font(.headline).help(card.path)
                            Button("Open card") { open(card) }.buttonStyle(.borderedProminent)
                            if !linkable(card) {
                                Text("A connection cannot be safely resolved. Check the filename, duplicate note names, and whether all notes are readable.").font(.caption).foregroundStyle(.secondary)
                            }
                            if parsed.role == .project {
                                Divider()
                                Text("Add a major point").font(.subheadline.bold())
                                Text("Choose a side to start building this resolution.").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("New AFF") { newParent(.aff, project: card) }.disabled(!linkable(card))
                                    Button("New DEF") { newParent(.def, project: card) }.disabled(!linkable(card))
                                }
                                DisclosureGroup("Link the current AFF or DEF draft") {
                                    Button("Add current point to this resolution") { changeProject(card) }
                                        .disabled(!canUse(card) || !currentInfo.valid || (currentInfo.role != .aff && currentInfo.role != .def))
                                }
                            } else if parsed.role == .aff || parsed.role == .def || parsed.primary != nil {
                                if let parent = parsed.primary {
                                    Text("Parent: \(parentLabel(parent.path))").font(.caption).foregroundStyle(.secondary)
                                    Text("Relationship: \(debateStanceLabel(parsed.primaryStance))")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .help("Open this card to change its relationship to its parent.")
                                } else if let project = hierarchy.project {
                                    Text("Resolution: \(DebateHierarchy.displayName(project))").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(parsed.projects.isEmpty ? "No resolution assigned" : "Resolution unavailable")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                                Text("Develop this point").font(.subheadline.bold())
                                Text("Create a card connected to this one.").font(.caption).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 6) {
                                    Button("Add objection or counterargument") { newChild(card, role: .objection, stance: .challenges) }
                                    Button("Add supporting evidence") { newChild(card, role: .evidence, stance: .supports) }
                                    Button("Add response") { newChild(card, role: .reply, stance: nil) }
                                    Button("Add supporting argument") { newChild(card, role: .argument, stance: .supports) }
                                }.disabled(!linkable(card))
                                DisclosureGroup("More options") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Button("Add challenging evidence") { newChild(card, role: .evidence, stance: .challenges) }.disabled(!linkable(card))
                                        Button("Add another kind of note") { newChild(card, role: nil, stance: nil) }.disabled(!linkable(card))
                                        Text("Link the current draft to this card:").font(.caption).foregroundStyle(.secondary)
                                        TextField("Connection explanation (optional)", text: $explanation)
                                        Button("Use this as its primary parent") { setPrimary(card) }
                                            .disabled(!canUse(card) || !currentInfo.valid || currentInfo.role == .project || currentInfo.role == .aff || currentInfo.role == .def)
                                        Button("Link as a related parent") { addRelated(card) }
                                            .disabled(!canUse(card) || !currentInfo.valid || currentInfo.primary == nil || currentInfo.role == .project)
                                            .help("Choose a primary parent before adding related parents.")
                                    }.padding(.top, 4)
                                }
                            } else {
                                if let parent = parsed.primary {
                                    Text("Parent: \(parentLabel(parent.path))").font(.caption).foregroundStyle(.secondary)
                                }
                                if !parsed.related.isEmpty {
                                    Text("Related to \(parsed.related.count) other point\(parsed.related.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("Open this card to read or edit it.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    } else {
                        Text("Select a card on the map to open it or add to its argument.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
                    }
                }.frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
            }
            Text("The map shows saved notes. Save your draft and refresh to see new connections.").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(minWidth: 900, minHeight: 570)
            .onAppear { if !folder.isEmpty { scan() } }
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
    private func newResolution() {
        guard let draft = DebateNotes.setRole(.project, in: DebateTemplates.body(for: .project)) else { message = "Could not create a resolution."; return }
        if onNew(draft, nil) { dismiss() }
    }
    private func newChild(_ parent: LibraryCard, role: DebateRole?, stance: DebateStance?) {
        guard safe(parent, requireRole: true),
              let latest = try? String(contentsOf: parent.url, encoding: .utf8) else { return }
        let latestInfo = DebateNotes.parse(latest)
        guard latestInfo.valid, latestInfo.role == DebateNotes.parse(parent.content).role else {
            message = "This parent changed. Refresh and try again."; return
        }
        let parentID = DebateIDs.parentID(in: latest, at: parent.url)
        if parentID == nil {
            guard !CardMetadata.hasNonemptyID(latest) else { message = "Fix the parent's card ID before creating a linked card."; return }
            let alert = NSAlert()
            alert.messageText = "This parent has no card ID"
            alert.informativeText = "Add an ID to the parent first for an inherited label, or create this card without a parent-based ID."
            alert.addButton(withTitle: "Continue without parent ID")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let template = DebateTemplates.body(for: role)
        let marked = role.flatMap { DebateNotes.setRole($0, in: template) } ?? template
        guard let linked = DebateNotes.setPrimary(parent.path, explanation: "", in: marked),
              let draft = DebateNotes.setStance(stance, in: linked) else { message = "Could not create a linked card."; return }
        let reference = DebateParentReference(url: parent.url, root: URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                                              path: parent.path, expectedID: parentID, expectedRole: latestInfo.role)
        if onNew(draft, reference) { dismiss() }
    }
    private func newParent(_ role: DebateRole, project: LibraryCard) {
        guard linkable(project) else {
            message = "This resolution cannot be linked safely. Check duplicate names and unreadable notes, then refresh."
            return
        }
        guard safe(project, requireRole: true) else { return }
        guard let marked = DebateNotes.setRole(role, in: DebateTemplates.body(for: role)),
              let draft = DebateNotes.addProject(project.path, in: marked) else { message = "Could not create a parent in this resolution."; return }
        let reference = DebateParentReference(url: project.url, root: URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                                              path: project.path, expectedID: DebateIDs.parentID(in: project.content, at: project.url), expectedRole: .project)
        if onNew(draft, reference) { dismiss() }
    }
    private func setPrimary(_ parent: LibraryCard) {
        guard safe(parent, requireRole: true) else { return }
        guard DebateHierarchy.canSetPrimary(snapshot: snapshot, currentURL: currentURL, proposedParent: parent) else {
            message = "This parent would create a cycle or its chain cannot be resolved. Refresh and check the links."
            return
        }
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
        guard let updated = DebateNotes.addProject(project.path, in: text) else { message = "Could not add the resolution. Check for duplicate or invalid links."; return }
        text = updated
        message = "Resolution added to the current draft. Save to keep it."
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { notesFolder = url.path; hasLoaded = false; scan() }
    }
    private func scan() {
        guard !folder.isEmpty else { return }
        let url = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let id = UUID(); scanID = id; loading = true; message = "Searching notes…"
        let previousSelection = selected, previousProject = projectPath, firstLoad = !hasLoaded
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LibrarySnapshot.load(folder: url)
            DispatchQueue.main.async {
                guard scanID == id else { return }
                loading = false
                guard let found else { hasLoaded = false; message = "Could not open this folder. Choose it again."; return }
                snapshot = found
                let availableProjects = DebateHierarchy.projects(in: found)
                if firstLoad {
                    let currentFile = currentURL?.resolvingSymlinksInPath().standardizedFileURL
                    let openCard = found.cards.first { $0.url.resolvingSymlinksInPath().standardizedFileURL == currentFile }
                    if let openCard {
                        let info = DebateNotes.parse(openCard.content)
                        if info.role == .project || info.role == .aff || info.role == .def || info.primary != nil {
                            projectPath = DebateHierarchy.projectsForCard(snapshot: found, cardPath: openCard.path).first
                        } else { projectPath = availableProjects.first?.path }
                    } else { projectPath = availableProjects.first?.path }
                } else if let previousProject, !availableProjects.contains(where: { samePath($0.path, previousProject) }) {
                    projectPath = nil
                } else { projectPath = previousProject }
                let map = DebateHierarchy.build(snapshot: found, projectPath: projectPath)
                let visible = map.visibleCards.map(\.path)
                let openPath = currentURL.flatMap { current in found.cards.first { $0.url.resolvingSymlinksInPath().standardizedFileURL == current.resolvingSymlinksInPath().standardizedFileURL }?.path }
                selected = [previousSelection, firstLoad ? openPath : nil, projectPath].compactMap { $0 }.first { visible.contains($0) }
                hasLoaded = true
                let count = availableProjects.count
                message = count == 0 ? "Create a resolution to begin, then add AFF and DEF points." : "\(count) saved resolution\(count == 1 ? "" : "s")."
                if found.unreadable > 0 { message += " Some notes could not be read." }
            }
        }
    }
}
