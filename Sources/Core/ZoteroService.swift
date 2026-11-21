import Foundation

/// Everything Kaster asks the running Zotero (its local API at 127.0.0.1:23119): libraries,
/// collections, searches, an item's PDF, and formatted bibliography entries. Read-only.
struct ZoteroService {
    /// Sends a request (replaceable in tests).
    var fetch: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    enum Failure: Error, Equatable {
        /// Zotero isn't running or doesn't allow local access.
        case unreachable
        /// Zotero answered with an error (the message says what to do).
        case refused(String)
        case unreadable
    }

    private func get<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data, response: URLResponse
        do { (data, response) = try await fetch(request) } catch { throw Failure.unreachable }
        guard let http = response as? HTTPURLResponse else { throw Failure.unreadable }
        guard http.statusCode == 200 else { throw Failure.refused(ZoteroSearchAPI.responseError(http.statusCode)) }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Failure.unreadable }
    }

    /// My Library followed by the group libraries, A–Z.
    func libraries() async -> [ZoteroLibrary] {
        let groups = (try? await get(ZoteroSearchAPI.groupsRequest(), as: [ZoteroGroup].self)) ?? []
        return [.personal] + groups.map { ZoteroLibrary(id: String($0.id), name: $0.title) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func collections(in library: ZoteroLibrary) async -> [ZoteroCollection] {
        (try? await get(ZoteroSearchAPI.collectionsRequest(library: library), as: [ZoteroCollection].self)) ?? []
    }

    /// One page of top-level items, newest first, with citations in `style`.
    func search(library: ZoteroLibrary, query: String, fullText: Bool, start: Int, collection: String?, style: String) async throws -> [ZoteroItem] {
        try await get(ZoteroSearchAPI.itemsRequest(library: library, query: query, fullText: fullText, start: start, collection: collection, style: style), as: [ZoteroItem].self)
    }

    /// The item's PDF (or EPUB) attachment key, so a page can open in Zotero's reader.
    func attachment(for source: ZoteroSource, timeout: TimeInterval = 10) async -> String? {
        var request = ZoteroSearchAPI.childrenRequest(library: source.zoteroLibrary, key: source.key)
        request.timeoutInterval = timeout
        guard let children = try? await get(request, as: [ZoteroChild].self) else { return nil }
        return ZoteroSearchAPI.readableAttachment(in: children)
    }

    /// A picked search result as a source: Zotero's short citation (or a plain description) and its PDF.
    func source(for item: ZoteroItem, in library: ZoteroLibrary) async -> ZoteroSource {
        let cite = item.citation.map { ZoteroCitation.markdown(fromHTML: $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? item.description
        let draft = ZoteroSource(key: item.key, library: library.id, cite: cite)
        return ZoteroSource(key: item.key, library: library.id, pdf: await attachment(for: draft), cite: cite)
    }

    struct Bibliography: Equatable {
        /// "library/KEY" → the full entry as Markdown.
        var entries: [String: String] = [:]
        var reachedZotero = false
        var someFailed = false
    }

    /// Full bibliography entries in `style` for these sources, 50 per request, per library.
    func bibliography(for sources: [ZoteroSource], style: String) async -> Bibliography {
        var result = Bibliography()
        for (library, items) in Dictionary(grouping: sources, by: \.library) {
            for start in stride(from: 0, to: items.count, by: 50) {
                let chunk = Array(items[start..<min(start + 50, items.count)])
                do {
                    let found = try await get(ZoteroSearchAPI.bibliographyRequest(library: chunk[0].zoteroLibrary, keys: chunk.map(\.key), style: style), as: [ZoteroBibEntry].self)
                    for item in found {
                        guard let bib = item.bib else { continue }
                        let text = ZoteroCitation.markdown(fromHTML: bib, trimPeriod: false)
                        if !text.isEmpty { result.entries["\(library)/\(item.key)"] = text }
                    }
                    result.reachedZotero = true
                } catch { result.someFailed = true }
            }
        }
        return result
    }
}
