import SwiftUI
import AppKit

// A read-only view of the chosen notes folder. Opening a note goes through
// the editor's existing unsaved-draft guard; the sidebar never writes files.
struct CardSidebar: View {
    let currentURL: URL?
    let draftTitle: String
    let draftID: String?
    let notesFolder: String
    let saveFolder: String
    let refreshToken: UUID
    let onOpen: (URL) -> Bool
    let onNew: () -> Void
    let onChooseFolder: () -> Void

    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    @State private var query = ""
    @State private var snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
    @State private var loading = false
    @State private var message = "Choose a notes folder."
    @State private var scanID = UUID()
    @State private var loadedFolder = ""

    private var folder: String { notesFolder.isEmpty ? saveFolder : notesFolder }
    private var matches: [LibraryCard] {
        snapshot.cards.filter { LibrarySearch.matches($0, query: query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Notes").font(.headline)
                    .foregroundColor(AppearancePreference.foreground(for: appearance))
                Spacer(minLength: 0)
                Button(action: onChooseFolder) { Image(systemName: "folder") }
                    .help("Choose Notes Folder").accessibilityLabel("Choose Notes Folder")
                Button(action: scan) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh Notes").accessibilityLabel("Refresh Notes").disabled(folder.isEmpty || loading)
            }
            .buttonStyle(.borderless)
            Button("New Card", action: onNew)
                .frame(maxWidth: .infinity, alignment: .leading)
            if currentURL == nil {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draftTitle).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(draftID.map { "Draft · \($0)" } ?? "Draft").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((AppearancePreference.accent(for: appearance) ?? Color.accentColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current unsaved draft, \(draftTitle)")
                .accessibilityAddTraits(.isSelected)
            }
            if folder.isEmpty {
                Text("Choose a notes folder to see your cards here.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Choose Notes Folder", action: onChooseFolder)
            } else {
                Text(URL(fileURLWithPath: folder, isDirectory: true).lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(folder)
                TextField("Search notes", text: $query)
                    .textFieldStyle(.roundedBorder)
                if loading {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Loading notes") }
                        .font(.caption).foregroundStyle(.secondary)
                } else if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !matches.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(matches) { card in
                                Button { open(card) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(card.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if let id = card.cardID, !id.isEmpty {
                                            Text(id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        } else if card.path.contains("/") {
                                            Text((card.path as NSString).deletingLastPathComponent)
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(isCurrent(card) ? (AppearancePreference.accent(for: appearance) ?? Color.accentColor).opacity(0.22) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(card.path)
                                .accessibilityLabel(card.cardID.map { "\(card.title), ID \($0)" } ?? card.title)
                            }
                        }
                    }
                } else if !loading && message.isEmpty {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Markdown notes in this folder." : "No matching notes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .onAppear(perform: scan)
        .onChange(of: folder) { _ in scan() }
        .onChange(of: refreshToken) { _ in scan() }
        .onDisappear { scanID = UUID() }
    }

    private func isCurrent(_ card: LibraryCard) -> Bool {
        guard let currentURL else { return false }
        return currentURL.resolvingSymlinksInPath().standardizedFileURL == card.url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func open(_ card: LibraryCard) {
        guard !folder.isEmpty else { return }
        if isCurrent(card) { return }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard CardGraph.canOpen(card.url, in: root) else {
            message = "This note is no longer available. Refresh and try again."
            return
        }
        _ = onOpen(card.url)
    }

    private func scan() {
        let id = UUID(); scanID = id
        guard !folder.isEmpty else {
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
            loadedFolder = ""; loading = false; message = "Choose a notes folder."; return
        }
        let root = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        if root.path != loadedFolder {
            snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
        }
        loading = true; message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LibrarySnapshot.load(folder: root)
            DispatchQueue.main.async {
                guard scanID == id else { return }
                loading = false
                guard let found else {
                    snapshot = LibrarySnapshot(cards: [], outgoing: [:], incoming: [:], unreadable: 0)
                    loadedFolder = ""
                    message = "Can't read this folder. Choose it again."
                    return
                }
                snapshot = found; loadedFolder = root.path
                message = found.unreadable > 0 ? "Some notes could not be read." : ""
            }
        }
    }
}
