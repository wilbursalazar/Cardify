import SwiftUI
import AppKit

/// "Open Beside": a second, fully editable card next to the main editor.
/// It autosaves to its own file and never overwrites a file changed elsewhere.
struct SideEditorPane: View {
    @Binding var tab: LinkedCardTab
    let tabs: [LinkedCardTab]
    let onSelect: (UUID) -> Void
    let onClose: () -> Void
    let onMakeMain: () -> Void
    let onFollowLink: (CardLinkTarget) -> Void
    let onSaved: () -> Void
    @StateObject private var editor = EditorState()
    @AppStorage("kasterEditorMode") private var editorMode = KasterEditorMode.live.rawValue
    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    @State private var saveTask: Task<Void, Never>?
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1").foregroundStyle(.secondary)
                if tabs.count > 1 {
                    Menu {
                        ForEach(tabs) { other in Button(other.title) { onSelect(other.id) } }
                    } label: { Text(tab.title).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
                        .menuStyle(.borderlessButton).fixedSize().help("Cards open beside")
                } else {
                    Text(tab.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Button(action: onMakeMain) { Image(systemName: "arrow.left.square") }
                    .buttonStyle(.borderless).help("Edit this card in the main editor")
                Button(action: { flush(); onClose() }) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Close this side card")
            }
            .padding(.horizontal, 10).frame(height: 36)
            Divider()
            MarkdownEditor(text: $tab.content, editor: editor, onFollowLink: onFollowLink,
                           live: (KasterEditorMode(rawValue: editorMode) ?? .live) == .live)
                .id(tab.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppearancePreference.foreground(for: appearance) == nil ? Color(nsColor: .textBackgroundColor) : Color.clear)
        .onChange(of: tab.content) { _ in scheduleSave() }
        .onDisappear { flush() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard tab.content != tab.savedContent else { return }
        note = "Editing…"
        saveTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Writes the side card only if its file still holds what was loaded (or last saved).
    private func flush() {
        saveTask?.cancel()
        guard tab.content != tab.savedContent else { return }
        let disk = (try? String(contentsOf: tab.url, encoding: .utf8)) ?? ""
        guard disk == tab.savedContent else {
            note = "Changed elsewhere — not saved"
            return
        }
        do {
            try Data(tab.content.utf8).write(to: tab.url, options: .atomic)
            tab.savedContent = tab.content
            note = "Saved"
            onSaved()
        } catch {
            note = "Could not save: \(error.localizedDescription)"
        }
    }
}
