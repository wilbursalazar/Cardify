import SwiftUI
import AppKit

// Read-only access to Zotero's local Web API. No account key or remote service is used.
struct ZoteroGroup: Decodable, Identifiable {
    struct Details: Decodable { let name: String? }
    let id: Int
    let data: Details
    var title: String { data.name?.isEmpty == false ? data.name! : "Group \(id)" }
}

struct ZoteroLibrary: Hashable, Identifiable {
    let id: String
    let name: String
    var prefix: String { id == "personal" ? "users/0" : "groups/\(id)" }
    var linkPrefix: String { id == "personal" ? "zotero://select/library/items/" : "zotero://select/groups/\(id)/items/" }
    static let personal = ZoteroLibrary(id: "personal", name: "My Library")
}

enum ZoteroSearchAPI {
    static func itemsRequest(library: ZoteroLibrary, query: String, fullText: Bool, start: Int, limit: Int = 100) -> URLRequest {
        var components = URLComponents(string: "http://127.0.0.1:23119/api/\(library.prefix)/items/top")!
        var params = [URLQueryItem(name: "sort", value: "dateModified"), URLQueryItem(name: "direction", value: "desc"), URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "start", value: String(start))]
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            params.append(URLQueryItem(name: "q", value: term))
            params.append(URLQueryItem(name: "qmode", value: fullText ? "everything" : "titleCreatorYear"))
        }
        components.queryItems = params
        var request = URLRequest(url: components.url!)
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.timeoutInterval = 15
        return request
    }
    static func groupsRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:23119/api/users/0/groups")!)
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.timeoutInterval = 10
        return request
    }
    static func responseError(_ status: Int) -> String {
        if status == 403 { return "Zotero's local access is disabled. In Zotero, enable Settings → Advanced → Allow other applications on this computer to communicate with Zotero." }
        return "Zotero returned error \(status). Try Refresh or check Zotero's local API settings."
    }
    static func markdown(item: ZoteroItem, location: String, library: ZoteroLibrary) -> String {
        item.markdown(location: location).replacingOccurrences(of: "zotero://select/library/items/", with: library.linkPrefix)
    }
}

struct ZoteroPicker: View {
    @Environment(\.dismiss) private var dismiss
    var onInsert: (String) -> Void
    @State private var query = ""
    @State private var location = ""
    @State private var items: [ZoteroItem] = []
    @State private var selection: String?
    @State private var libraries: [ZoteroLibrary] = [.personal]
    @State private var libraryID = "personal"
    @State private var fullText = false
    @State private var message = "Connecting to Zotero…"
    @State private var searching = false
    @State private var hasMore = false
    @State private var requestID = UUID()
    @State private var refreshID = UUID()
    private var currentLibrary: ZoteroLibrary { libraries.first { $0.id == libraryID } ?? .personal }
    private var searchKey: String { "\(libraryID)|\(fullText)|\(query)|\(refreshID)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Zotero source").font(.title2.bold())
            HStack {
                Picker("Library", selection: $libraryID) {
                    ForEach(libraries) { library in Text(library.name).tag(library.id) }
                }.frame(maxWidth: 270)
                Spacer()
                Button("Refresh") { refreshID = UUID(); loadGroups() }
            }
            HStack {
                TextField("Search title, author, or year", text: $query)
                if !query.isEmpty { Button("Clear") { query = "" } }
            }
            Toggle("Search all fields and full text", isOn: $fullText)
            Text(message).font(.caption).foregroundStyle(.secondary)
            List(items, selection: $selection) { item in
                VStack(alignment: .leading) {
                    Text(item.title).fontWeight(.medium)
                    Text([item.authors, ZoteroItem.clean(item.data.date ?? "")].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }.tag(item.key)
            }.frame(minHeight: 200)
            if hasMore {
                HStack { Spacer(); Button("Load More") { Task { await search(append: true) } }.disabled(searching); Spacer() }
            }
            TextField("Page or location (optional), e.g. p. 42", text: $location)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add source") {
                    if let item = items.first(where: { $0.key == selection }) {
                        onInsert(ZoteroSearchAPI.markdown(item: item, location: location, library: currentLibrary)); dismiss()
                    }
                }.disabled(selection == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 590, height: 500)
        .task { loadGroups() }
        .task(id: searchKey) {
            // Invalidate earlier requests immediately, even during the debounce period.
            requestID = UUID()
            selection = nil
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            await search(append: false)
        }
    }
    private func loadGroups() {
        URLSession.shared.dataTask(with: ZoteroSearchAPI.groupsRequest()) { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
                  let groups = try? JSONDecoder().decode([ZoteroGroup].self, from: data) else { return }
            let found = groups.map { ZoteroLibrary(id: String($0.id), name: $0.title) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { libraries = [.personal] + found }
        }.resume()
    }
    @MainActor private func search(append: Bool) async {
        let id = UUID(); requestID = id
        let library = currentLibrary
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = append ? items.count : 0
        if !append { items = []; selection = nil; hasMore = false }
        searching = true; message = term.isEmpty ? "Loading recently modified sources…" : "Searching Zotero…"
        do {
            let (data, response) = try await URLSession.shared.data(for: ZoteroSearchAPI.itemsRequest(library: library, query: term, fullText: fullText, start: start))
            guard requestID == id, !Task.isCancelled else { return }
            guard let http = response as? HTTPURLResponse else { searching = false; message = "Unexpected response from Zotero."; return }
            guard http.statusCode == 200 else { searching = false; message = ZoteroSearchAPI.responseError(http.statusCode); return }
            let found = try JSONDecoder().decode([ZoteroItem].self, from: data)
            if append { items.append(contentsOf: found) } else { items = found }
            hasMore = found.count == 100
            searching = false
            message = items.isEmpty ? (term.isEmpty ? "No sources found in this library." : "No matches. Try fewer words or enable full-text search.") : "\(items.count) sources shown\(hasMore ? "; more available" : "")."
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            searching = false; hasMore = false
            message = "Can't connect to Zotero. Open it and enable Settings → Advanced → Allow other applications on this computer to communicate with Zotero."
        }
    }
}
