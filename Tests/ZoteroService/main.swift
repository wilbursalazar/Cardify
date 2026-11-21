@testable import KasterCore
import Foundation

// ZoteroService against canned local-API answers (no Zotero needed): libraries, PDFs, picked
// sources, bibliography entries in 50-item batches, and the failures Kaster explains.
func respond(_ routes: [(String, Int, String)], log: Log? = nil) -> (URLRequest) async throws -> (Data, URLResponse) {
    { request in
        let url = request.url!.absoluteString
        log?.urls.append(url)
        guard let route = routes.first(where: { url.contains($0.0) }) else { throw URLError(.cannotConnectToHost) }
        return (Data(route.2.utf8), HTTPURLResponse(url: request.url!, statusCode: route.1, httpVersion: nil, headerFields: nil)!)
    }
}
final class Log { var urls: [String] = [] }

@main struct Checks {
    static func main() async throws {
        var zotero = ZoteroService()
        zotero.fetch = respond([("/users/0/groups", 200, #"[{"id":12,"data":{"name":"Seminar"}},{"id":3,"data":{"name":"Archive"}}]"#)])
        let libraries = await zotero.libraries()
        precondition(libraries.map(\.name) == ["My Library", "Archive", "Seminar"] && libraries[1].id == "3")
        zotero.fetch = respond([])
        let offlineLibraries = await zotero.libraries()
        precondition(offlineLibraries == [.personal], "Without Zotero: just My Library")

        zotero.fetch = respond([("/items/K/children", 200, #"[{"key":"N","data":{"itemType":"note"}},{"key":"P","data":{"itemType":"attachment","contentType":"application/pdf","linkMode":"imported_file"}}]"#)])
        let pdf = await zotero.attachment(for: ZoteroSource(key: "K", cite: "x"))
        precondition(pdf == "P")
        zotero.fetch = respond([("/items/K/children", 403, "")])
        let noPDF = await zotero.attachment(for: ZoteroSource(key: "K", cite: "x"))
        precondition(noPDF == nil)

        let item = try JSONDecoder().decode(ZoteroItem.self, from: Data(#"{"key":"K","data":{"title":"How Was the Canon Formed?","creators":[{"lastName":"Lim","firstName":"Timothy"}]},"citation":"<span>Lim, <i>How Was the Canon Formed?</i></span>"}"#.utf8))
        zotero.fetch = respond([("/groups/12/items/K/children", 200, #"[{"key":"P","data":{"itemType":"attachment","contentType":"application/pdf","linkMode":"imported_file"}}]"#)])
        let picked = await zotero.source(for: item, in: ZoteroLibrary(id: "12", name: "Seminar"))
        precondition(picked == ZoteroSource(key: "K", library: "12", pdf: "P", cite: "Lim, *How Was the Canon Formed?*"), "\(picked)")

        zotero.fetch = respond([("/items/top", 403, "")])
        do { _ = try await zotero.search(library: .personal, query: "", fullText: false, start: 0, collection: nil, style: "apa"); preconditionFailure("refused") }
        catch let failure as ZoteroService.Failure { if case .refused(let reason) = failure { precondition(reason.contains("Allow other applications")) } else { preconditionFailure("\(failure)") } }
        zotero.fetch = respond([])
        do { _ = try await zotero.search(library: .personal, query: "", fullText: false, start: 0, collection: nil, style: "apa"); preconditionFailure("unreachable") }
        catch let failure as ZoteroService.Failure { precondition(failure == .unreachable) }

        // Bibliography: per library, 50 keys per request; a failed batch is reported, others kept.
        let log = Log()
        let many = (0..<51).map { ZoteroSource(key: "K\($0)", cite: "c") } + [ZoteroSource(key: "G", library: "12", cite: "g")]
        zotero.fetch = respond([("/users/0/items?", 200, #"[{"key":"K0","bib":"<div class=\"csl-entry\">Lim, <i>Canon</i>.</div>"}]"#), ("/groups/12/items?", 500, "")], log: log)
        let bibliography = await zotero.bibliography(for: many, style: "chicago-notes-bibliography")
        precondition(bibliography.entries == ["personal/K0": "Lim, *Canon*."] && bibliography.reachedZotero && bibliography.someFailed, "\(bibliography)")
        precondition(log.urls.filter { $0.contains("/users/0/items?") }.count == 2 && log.urls.contains { $0.contains("itemKey=K50") }, "\(log.urls)")
        zotero.fetch = respond([])
        let offline = await zotero.bibliography(for: [ZoteroSource(key: "K", cite: "c")], style: "apa")
        precondition(!offline.reachedZotero && offline.someFailed && offline.entries.isEmpty)
        print("Zotero service: libraries, PDFs, picked sources, searches, bibliography batches and failures passed")
    }
}
