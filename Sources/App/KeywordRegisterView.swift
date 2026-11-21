import SwiftUI
import AppKit

/// The register as a list: keywords A–Z, each with its entry cards.
struct KeywordRegisterView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [KeywordRegister.Entry]
    let indexCardsToImport: [LibraryCard]
    let state: (String) -> RegisterService.LinkState
    let cards: [LibraryCard]
    let onOpen: (URL) -> Void
    let onRemove: (_ link: String?, _ keyword: String) -> Void
    let onChoose: (_ card: LibraryCard, _ link: String, _ keyword: String) -> Void
    let onImportIndexCards: () -> Void
    let onPrint: () -> Void
    let onOpenFile: () -> Void
    @State private var query = ""
    @State private var onlyBroken = false

    private func isBroken(_ link: String) -> Bool { if case .card = state(link) { return false }; return true }
    private var brokenCount: Int { entries.filter { $0.links.contains(where: isBroken) }.count }

    private var shown: [KeywordRegister.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let base = onlyBroken ? entries.filter { $0.links.contains(where: isBroken) } : entries
        return q.isEmpty ? base : base.filter { $0.keyword.localizedCaseInsensitiveContains(q) || $0.links.contains { $0.localizedCaseInsensitiveContains(q) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyword Register").font(.title2.bold())
                Spacer()
                Button("Open Register.md", action: { onOpenFile(); dismiss() }).help("Edit the register as a card")
                Button("Print Register Cards", action: onPrint).disabled(entries.isEmpty)
            }
            Text("Luhmann's index: a few keywords, each pointing to 1–3 entry cards where a line of thought begins. Add a card from its ⋯ menu or by right-clicking it in the sidebar. Printed register cards show each card's ID, so you can find it in the box.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Search keywords", text: $query)
                if brokenCount > 0 {
                    Toggle("\(brokenCount) need attention", isOn: $onlyBroken).toggleStyle(.button).tint(.orange)
                        .help("Entries whose card is missing or whose name now matches several cards")
                }
            }
            if !indexCardsToImport.isEmpty {
                DisclosureGroup("\(indexCardsToImport.count) index card\(indexCardsToImport.count == 1 ? "" : "s") no keyword reaches yet") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(indexCardsToImport) { card in
                            Button { onOpen(card.url); dismiss() } label: { Label(card.title, systemImage: "list.bullet.rectangle").font(.system(size: 12)) }
                                .buttonStyle(.plain)
                        }
                        Button("Add Them as Keywords", action: onImportIndexCards)
                            .help("Each becomes a keyword (its title) pointing to the index card")
                    }.padding(.top, 4)
                }.font(.system(size: 12))
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
                        FlowLinks(links: entry.links, state: state, cards: cards, onOpen: { onOpen($0); dismiss() },
                                  onRemove: { onRemove($0, entry.keyword) }, onChoose: { card, link in onChoose(card, link, entry.keyword) })
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
    let state: (String) -> RegisterService.LinkState
    let cards: [LibraryCard]
    let onOpen: (URL) -> Void
    let onRemove: (String) -> Void
    let onChoose: (LibraryCard, String) -> Void
    @State private var choosing: String?
    var body: some View {
        HStack(spacing: 6) {
            ForEach(links, id: \.self) { link in
                let current = state(link)
                let label = CardSyntax.WikiTarget(link).alias ?? CardSyntax.WikiTarget(link).name
                Button {
                    if case .card(let url) = current { onOpen(url) } else { choosing = link }
                } label: {
                    HStack(spacing: 3) {
                        if case .card = current {} else { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)) }
                        Text(label).font(.system(size: 12)).lineLimit(1)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(chipColor(current).opacity(0.15), in: Capsule())
                    .foregroundStyle(isCard(current) ? Color.primary : Color.orange)
                }
                .buttonStyle(.plain)
                .help(help(current, link))
                .popover(isPresented: Binding(get: { choosing == link }, set: { if !$0 { choosing = nil } })) {
                    CardChooser(link: link, suggestions: suggestions(current), cards: cards) { card in onChoose(card, link); choosing = nil }
                }
                .contextMenu {
                    if !isCard(current) { Button("Choose Card…") { choosing = link } }
                    Button("Remove from This Keyword") { onRemove(link) }
                }
            }
        }
    }
    private func isCard(_ state: RegisterService.LinkState) -> Bool { if case .card = state { return true }; return false }
    private func chipColor(_ state: RegisterService.LinkState) -> Color { isCard(state) ? .accentColor : .orange }
    private func suggestions(_ state: RegisterService.LinkState) -> [URL] { if case .ambiguous(let urls) = state { return urls }; return [] }
    private func help(_ state: RegisterService.LinkState, _ link: String) -> String {
        switch state {
        case .card: return "Open \(link)"
        case .missing: return "No card named \(link). Click to choose the card it should point to."
        case .ambiguous(let urls): return "\(urls.count) cards are named \(link). Click to choose which one."
        }
    }
}

/// Picks the card a broken register entry should point to.
private struct CardChooser: View {
    let link: String
    let suggestions: [URL]
    let cards: [LibraryCard]
    let onPick: (LibraryCard) -> Void
    @State private var query = ""
    private var shown: [LibraryCard] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty, !suggestions.isEmpty { return cards.filter { card in suggestions.contains { $0.standardizedFileURL == card.url.standardizedFileURL } } }
        return Array((q.isEmpty ? cards : cards.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q) }).prefix(60))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Point “\(CardSyntax.WikiTarget(link).name)” to…").font(.headline)
            TextField("Search cards", text: $query)
            List(shown) { card in
                Button { onPick(card) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text([card.cardID, card.title].compactMap { $0 }.joined(separator: "  ")).font(.system(size: 12))
                        Text(card.path).font(.caption2).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }.frame(minHeight: 180)
        }
        .padding(12).frame(width: 340, height: 300)
        .onAppear { if suggestions.isEmpty { query = CardSyntax.WikiTarget(link).name } }
    }
}
