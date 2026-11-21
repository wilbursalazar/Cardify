import SwiftUI
import AppKit

// Each indexed topic is an ordinary Markdown note with the explicit marker above.
struct CuratedIndexView: View {
    let cards: [LibraryCard]
    let onOpen: (URL) -> Void
    let onRefresh: () -> Void
    @State private var query = ""
    private var indexCards: [LibraryCard] {
        let all = cards.filter { IndexCardMetadata.isIndex($0.content) }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? all : all.filter {
            $0.title.localizedStandardContains(search) || $0.path.localizedStandardContains(search) || ($0.cardID?.localizedStandardContains(search) ?? false) || $0.content.localizedStandardContains(search)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search index cards", text: $query)
                Button("Refresh", action: onRefresh)
            }
            Text("Index cards hold selected links to starting points for a topic.")
                .font(.caption).foregroundStyle(.secondary)
            if indexCards.isEmpty {
                Text(query.isEmpty ? "No index cards yet. Use the Index Card template, or mark an open note as an index card, then save it." : "No index cards match this search.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(indexCards) { card in
                    Button { onOpen(card.url) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title).fontWeight(.medium)
                            Text(card.cardID.map { "\($0) · \(card.path)" } ?? card.path)
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
