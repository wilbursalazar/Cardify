import SwiftUI
import AppKit

// MARK: Editor tabs

struct EditorTab: Identifiable, Equatable {
    let url: URL?          // nil = the unsaved draft
    let title: String
    var id: String { url.map(KasterPathList.key) ?? "draft" }
}

struct EditorTabBar: View {
    let tabs: [EditorTab]
    let currentID: String
    let onSelect: (EditorTab) -> Void
    let onClose: (EditorTab) -> Void
    let onNew: () -> Void
    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in tabView(tab) }
                }
                .padding(.horizontal, 8)
            }
            Button(action: onNew) { Image(systemName: "plus").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("New Card").padding(.horizontal, 10)
        }
        .frame(height: 36)
    }

    private func tabView(_ tab: EditorTab) -> some View {
        let selected = tab.id == currentID
        let accent = AppearancePreference.accent(for: appearance) ?? AppearancePreference.kasterPurple
        return HStack(spacing: 6) {
            Image(systemName: tab.url == nil ? "square.and.pencil" : "doc.text")
                .font(.system(size: 11)).foregroundStyle(selected ? accent : .secondary)
            Text(tab.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            Button { onClose(tab) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Close Tab")
                .opacity(tabs.count > 1 || tab.url != nil ? 1 : 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Color(nsColor: .textBackgroundColor) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .bottom) { if selected { Rectangle().fill(accent).frame(height: 2).padding(.horizontal, 6) } }
        .contentShape(Rectangle())
        .onTapGesture { if !selected { onSelect(tab) } }
        .help(tab.url?.path ?? "Unsaved draft")
    }
}

// MARK: Formatting toolbar

enum KasterEditorMode: String, CaseIterable {
    case live, source
    var title: String { self == .live ? "Live" : "Source" }
}

struct KasterFormatBar: View {
    let editor: EditorState
    @Binding var mode: String
    let onLinkNote: () -> Void
    let onZotero: () -> Void
    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue

    var body: some View {
        HStack(spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) { headingMenu; divider; emphasis; divider; inserts; divider; lists; moreMenu(compact: false); Spacer(minLength: 8) }
                HStack(spacing: 2) { headingMenu; emphasis; icon("link", "Link a card ([[ ]])", action: onLinkNote); moreMenu(compact: true); Spacer(minLength: 4) }
                HStack(spacing: 2) { moreMenu(compact: true); Spacer(minLength: 4) }
            }
            Button(action: onZotero) { Label("Zotero", systemImage: "books.vertical").font(.system(size: 12)) }
                .buttonStyle(.borderless).fixedSize().help("Add a source from your Zotero library").padding(.trailing, 6)
            KasterModePicker(mode: $mode).fixedSize()
        }
        .padding(.horizontal, 10).frame(height: 38)
    }

    private var headingMenu: some View {
            Menu {
                Button("Heading 1") { heading(1) }
                Button("Heading 2") { heading(2) }
                Button("Heading 3") { heading(3) }
                Divider()
                Button("Body Text") { heading(0) }
            } label: { Text("Heading").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).fixedSize().padding(.trailing, 6).help("Paragraph style")
    }
    @ViewBuilder private var emphasis: some View {
            icon("bold", "Bold (⌘B)") { editor.wrap("**") }.keyboardShortcut("b", modifiers: .command)
            icon("italic", "Italic (⌘I)") { editor.wrap("*") }.keyboardShortcut("i", modifiers: .command)
            icon("underline", "Underline (⌘U)") { wrap("<u>", "</u>") }.keyboardShortcut("u", modifiers: .command)
            icon("strikethrough", "Strikethrough") { editor.wrap("~~") }
    }
    @ViewBuilder private var inserts: some View {
            icon("link", "Link a card ([[ ]])", action: onLinkNote)
            icon("photo", "Insert image") { insertImage() }
            icon("tablecells", "Insert table") { editor.insert("\n| Column | Column | Column |\n| --- | --- | --- |\n|  |  |  |\n") }
    }
    @ViewBuilder private var lists: some View {
            icon("list.bullet", "Bulleted list") { editor.prefix("- ") }
            icon("list.number", "Numbered list") { editor.prefix("1. ") }
    }
    private func moreMenu(compact: Bool) -> some View {
            Menu {
                if compact {
                    Button("Underline") { wrap("<u>", "</u>") }
                    Button("Strikethrough") { editor.wrap("~~") }
                    Button("Link a Card…", action: onLinkNote)
                    Button("Insert Image…") { insertImage() }
                    Button("Insert Table") { editor.insert("\n| Column | Column | Column |\n| --- | --- | --- |\n|  |  |  |\n") }
                    Button("Bulleted List") { editor.prefix("- ") }
                    Button("Numbered List") { editor.prefix("1. ") }
                    Divider()
                }
                Button("Task") { editor.prefix("- [ ] ") }
                Button("Quote") { editor.prefix("> ") }
                Button("Inline Code") { editor.wrap("`") }
                Button("Divider") { editor.insert("\n---\n") }
                Divider()
                Button("Add Zotero Source…", action: onZotero)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.horizontal, 6).help("More formatting")
    }

    private var divider: some View { Divider().frame(height: 16).padding(.horizontal, 5) }

    private func icon(_ name: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 13)).frame(width: 26, height: 24).contentShape(Rectangle()) }
            .buttonStyle(.borderless).foregroundStyle(.primary).help(help).accessibilityLabel(help)
    }

    private func heading(_ level: Int) {
        guard let view = editor.view else { return }
        let ns = view.string as NSString
        let line = ns.lineRange(for: NSRange(location: view.selectedRange().location, length: 0))
        let content = ns.substring(with: line)
        let stripped = content.replacingOccurrences(of: "^#{1,6} +", with: "", options: .regularExpression)
        let prefix = level == 0 ? "" : String(repeating: "#", count: level) + " "
        let replacement = prefix + stripped
        guard replacement != content else { return }
        view.insertText(replacement, replacementRange: line)
        view.setSelectedRange(NSRange(location: line.location + (replacement as NSString).length - (replacement.hasSuffix("\n") ? 1 : 0), length: 0))
        view.window?.makeFirstResponder(view)
    }

    private func wrap(_ open: String, _ close: String) {
        guard let view = editor.view else { return }
        let range = view.selectedRange()
        let selected = (view.string as NSString).substring(with: range)
        view.insertText(open + selected + close, replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + (open as NSString).length, length: range.length))
        view.window?.makeFirstResponder(view)
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alt = url.deletingPathExtension().lastPathComponent
        let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        editor.insert("![\(alt)](\(path))")
    }
}

struct KasterModePicker: View {
    @Binding var mode: String
    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    var body: some View {
        let accent = AppearancePreference.accent(for: appearance) ?? AppearancePreference.kasterPurple
        HStack(spacing: 0) {
            ForEach(KasterEditorMode.allCases, id: \.rawValue) { option in
                let selected = (KasterEditorMode(rawValue: mode) ?? .live) == option
                Button { mode = option.rawValue } label: {
                    Text(option.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? .white : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(selected ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option == .live ? "Styled Markdown: headings, emphasis, and links shown as you write" : "Plain Markdown source")
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: Status bar

struct KasterStatusBar: View {
    let location: String
    let words: Int
    let status: String
    let autosaved: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(location).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            Text(status).lineLimit(1).truncationMode(.tail).foregroundStyle(.tertiary)
            Spacer(minLength: 12)
            Text("\(words) \(words == 1 ? "word" : "words")").monospacedDigit()
            Divider().frame(height: 12)
            HStack(spacing: 4) {
                Image(systemName: autosaved ? "checkmark" : "circle.fill").font(.system(size: autosaved ? 10 : 6, weight: .bold))
                    .foregroundStyle(autosaved ? Color.green : Color.orange)
                Text(autosaved ? "Autosaved" : "Draft")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).frame(height: 26)
    }
}
