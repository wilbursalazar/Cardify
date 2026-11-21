import SwiftUI
import AppKit

/// The register as a list: keywords A–Z, each with its entry cards.
struct KeywordRegisterView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [KeywordRegister.Entry]
    let indexCardsToImport: Int
    let resolve: (String) -> URL?
    let onOpen: (URL) -> Void
    let onRemove: (_ link: String?, _ keyword: String) -> Void
    let onImportIndexCards: () -> Void
    let onPrint: () -> Void
    let onOpenFile: () -> Void
    @State private var query = ""

    private var shown: [KeywordRegister.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? entries : entries.filter { $0.keyword.localizedCaseInsensitiveContains(q) || $0.links.contains { $0.localizedCaseInsensitiveContains(q) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyword Register").font(.title2.bold())
                Spacer()
                Button("Open Register.md", action: { onOpenFile(); dismiss() }).help("Edit the register as a card")
                Button("Print Register Cards", action: onPrint).disabled(entries.isEmpty)
            }
            Text("Luhmann's index: a few keywords, each pointing to 1–3 entry cards where a line of thought begins. Add a card from its ⋯ menu or by right-clicking it in the sidebar.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Search keywords", text: $query)
            if indexCardsToImport > 0 {
                Button("Add \(indexCardsToImport) Index Card\(indexCardsToImport == 1 ? "" : "s") as Keywords", action: onImportIndexCards)
                    .help("Each card marked as an index card becomes a keyword pointing to it")
            }
            if shown.isEmpty {
                Text(entries.isEmpty ? "No keywords yet." : "No keywords match.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.keyword).font(.system(size: 13, weight: .semibold))
                            if entry.links.count > KeywordRegister.suggestedLinks {
                                Text("\(entry.links.count) entries").font(.caption2).foregroundStyle(.orange)
                                    .help("Luhmann kept 1–3 entry cards per keyword; consider pointing to a hub card instead")
                            }
                        }
                        FlowLinks(links: entry.links, resolve: resolve, onOpen: { onOpen($0); dismiss() }, onRemove: { onRemove($0, entry.keyword) })
                    }
                    .padding(.vertical, 2)
                    .contextMenu { Button("Remove Keyword", role: .destructive) { onRemove(nil, entry.keyword) } }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 560, height: 520)
    }
}

private struct FlowLinks: View {
    let links: [String]
    let resolve: (String) -> URL?
    let onOpen: (URL) -> Void
    let onRemove: (String) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(links, id: \.self) { link in
                let url = resolve(link)
                Button { if let url { onOpen(url) } } label: {
                    Text((link.split(separator: "|").last.map(String.init) ?? link).components(separatedBy: "/").last ?? link)
                        .font(.system(size: 12)).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(url == nil ? 0.05 : 0.12), in: Capsule())
                        .foregroundStyle(url == nil ? Color.secondary : Color.primary)
                }
                .buttonStyle(.plain)
                .help(url == nil ? "No card named \(link) was found" : "Open \(link)")
                .contextMenu { Button("Remove from This Keyword") { onRemove(link) } }
            }
        }
    }
}
