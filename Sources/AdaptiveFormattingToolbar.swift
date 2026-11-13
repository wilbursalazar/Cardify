import SwiftUI
import AppKit

// Prefer one compact row; on narrower editors keep controls legible on two
// rows. The last resort scrolls rather than clipping at unusually small sizes.
struct AdaptiveFormattingToolbar: View {
    let editor: EditorState
    let onLinkNote: () -> Void
    let onZotero: () -> Void

    @ViewBuilder private var formattingButtons: some View {
        Button("B") { editor.wrap("**") }.fontWeight(.bold).help("Bold").accessibilityLabel("Bold")
        Button("I") { editor.wrap("*") }.italic().help("Italic").accessibilityLabel("Italic")
        Button("H1") { editor.prefix("# ") }.help("Heading").accessibilityLabel("Heading")
        Button("H2") { editor.prefix("## ") }.help("Subheading").accessibilityLabel("Subheading")
        Button("• List") { editor.prefix("- ") }.help("Bullet list").accessibilityLabel("Bullet list")
        Button("☐ Task") { editor.prefix("- [ ] ") }.help("Task").accessibilityLabel("Task")
    }

    @ViewBuilder private var sourceButtons: some View {
        Button("Link Note", action: onLinkNote).help("Search your notes folder").accessibilityLabel("Link Note")
        Button("Add Zotero Source", action: onZotero).help("Find a source in Zotero").accessibilityLabel("Add Zotero Source")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                formattingButtons
                sourceButtons
            }.fixedSize(horizontal: true, vertical: false)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) { formattingButtons }
                    HStack(spacing: 14) { sourceButtons }
                }.fixedSize(horizontal: true, vertical: false)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }
}
