import SwiftUI
import AppKit

// A compact research toolbar. The content remains Markdown regardless of
// presentation mode; these controls operate on the editor's actual text.
struct AdaptiveFormattingToolbar: View {
    let editor: EditorState
    @Binding var presentation: EditorPresentationMode
    let onLinkNote: () -> Void
    let onZotero: () -> Void
    let onInsertImage: () -> Void

    private let purple = Color(red: 0.43, green: 0.20, blue: 0.76)

    @ViewBuilder private var formatting: some View {
        Menu {
            Button("Heading 1") { editor.prefix("# ") }
            Button("Heading 2") { editor.prefix("## ") }
            Button("Heading 3") { editor.prefix("### ") }
        } label: {
            HStack(spacing: 3) { Text("Heading"); Image(systemName: "chevron.down").font(.system(size: 9)) }
        }.help("Insert heading")

        Divider().frame(height: 16)
        Button { editor.wrap("**") } label: { Text("B").bold() }.help("Bold")
        Button { editor.wrap("*") } label: { Text("I").italic() }.help("Italic")
        Button { editor.wrap("<u>") } label: { Text("U").underline() }.help("Underline (HTML)")
        Button { editor.wrap("~~") } label: { Text("S").strikethrough() }.help("Strikethrough")
        Button(action: onLinkNote) { Image(systemName: "link") }.help("Link note")
        Button(action: onInsertImage) { Image(systemName: "photo") }.help("Insert image")
        Button {
            editor.insert("| Column 1 | Column 2 |\n| --- | --- |\n| Text | Text |\n")
        } label: { Image(systemName: "tablecells") }.help("Insert Markdown table")
        Divider().frame(height: 16)
        Button { editor.prefix("1. ") } label: { Image(systemName: "list.number") }.help("Numbered list")
        Button { editor.prefix("- ") } label: { Image(systemName: "list.bullet") }.help("Bulleted list")
        Menu {
            Button("Task list") { editor.prefix("- [ ] ") }
            Button("Inline code") { editor.wrap("`") }
            Button("Zotero source", action: onZotero)
        } label: { Image(systemName: "ellipsis") }.help("More formatting")
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) { formatting }
                .font(.system(size: 11))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 6)
            HStack(spacing: 1) {
                ForEach(EditorPresentationMode.allCases, id: \.self) { item in
                    Button(item.label) { presentation = item }
                        .font(.system(size: 10, weight: presentation == item ? .semibold : .medium))
                        .foregroundStyle(presentation == item ? Color.white : Color.primary)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(presentation == item ? purple : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .help(item.description)
                }
            }
            .padding(2)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).frame(height: 36)
        .background(Color(red: 0.977, green: 0.975, blue: 0.983))
    }
}
