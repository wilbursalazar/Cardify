import SwiftUI
import AppKit
import PDFKit

// Read-only access to Zotero's local Web API. No account key or remote service is used.
struct ZoteroCreator: Decodable {
    let firstName: String?
    let lastName: String?
    let name: String?
    var display: String { [firstName, lastName].compactMap { $0 }.joined(separator: " ").isEmpty ? (name ?? "") : [firstName, lastName].compactMap { $0 }.joined(separator: " ") }
}
struct ZoteroData: Decodable {
    let title: String?
    let date: String?
    let creators: [ZoteroCreator]?
}
struct ZoteroItem: Decodable, Identifiable {
    let key: String
    let data: ZoteroData
    /// Zotero's formatted citation (HTML) in the requested style, when asked for.
    var citation: String? = nil
    var id: String { key }
    static func clean(_ value: String) -> String { value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
    var title: String { let t = Self.clean(data.title ?? ""); return t.isEmpty ? "Untitled" : t }
    var authors: String { (data.creators ?? []).map { Self.clean($0.display) }.filter { !$0.isEmpty }.joined(separator: ", ") }
    var description: String { [authors, title, Self.clean(data.date ?? "")].filter { !$0.isEmpty }.joined(separator: ", ") }
}

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

struct ZoteroCollection: Decodable, Identifiable, Hashable {
    struct Details: Decodable, Hashable { let name: String; let parentCollection: ParentValue? }
    /// Zotero sends `false` for top-level collections and a key string otherwise.
    enum ParentValue: Decodable, Hashable {
        case none, key(String)
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let key = try? container.decode(String.self) { self = .key(key) } else { self = .none }
        }
    }
    let key: String
    let data: Details
    var id: String { key }
    var parent: String? { if case .key(let key) = data.parentCollection { return key }; return nil }
}

struct ZoteroChild: Decodable {
    struct Details: Decodable { let itemType: String; let contentType: String?; let linkMode: String? }
    let key: String
    let data: Details
}

/// One item from an `include=bib` request: its formatted bibliography entry as HTML.
struct ZoteroBibEntry: Decodable {
    let key: String
    let bib: String?
}

enum ZoteroSearchAPI {
    static func request(_ path: String, _ params: [URLQueryItem] = [], timeout: TimeInterval = 15) -> URLRequest {
        var components = URLComponents(string: "http://127.0.0.1:23119/api/" + path)!
        if !params.isEmpty { components.queryItems = params }
        var request = URLRequest(url: components.url!)
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.timeoutInterval = timeout
        return request
    }
    static func collectionsRequest(library: ZoteroLibrary) -> URLRequest { request("\(library.prefix)/collections", timeout: 10) }
    static func childrenRequest(library: ZoteroLibrary, key: String) -> URLRequest { request("\(library.prefix)/items/\(key)/children", timeout: 10) }

    /// The first PDF or EPUB attachment Zotero can open in its reader.
    static func readableAttachment(in children: [ZoteroChild]) -> String? {
        let files = children.filter { $0.data.itemType == "attachment" && $0.data.linkMode != "linked_url" }
        return (files.first { $0.data.contentType == "application/pdf" } ?? files.first { $0.data.contentType == "application/epub+zip" })?.key
    }

    static func itemsRequest(library: ZoteroLibrary, query: String, fullText: Bool, start: Int, limit: Int = 100, collection: String? = nil, style: String? = nil) -> URLRequest {
        let path = collection.map { "\(library.prefix)/collections/\($0)/items/top" } ?? "\(library.prefix)/items/top"
        var components = URLComponents(string: "http://127.0.0.1:23119/api/\(path)")!
        var params = [URLQueryItem(name: "sort", value: "dateModified"), URLQueryItem(name: "direction", value: "desc"), URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "start", value: String(start))]
        if let style {
            params.append(URLQueryItem(name: "include", value: "data,citation"))
            params.append(URLQueryItem(name: "style", value: style))
        }
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
    /// Full bibliography entries (formatted HTML) for up to 50 items of one library.
    static func bibliographyRequest(library: ZoteroLibrary, keys: [String], style: String) -> URLRequest {
        request("\(library.prefix)/items", [URLQueryItem(name: "itemKey", value: keys.prefix(50).joined(separator: ",")),
                                            URLQueryItem(name: "include", value: "bib"), URLQueryItem(name: "style", value: style),
                                            URLQueryItem(name: "limit", value: "50")], timeout: 10)
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
}

/// A chosen source: what goes into the card and the page typed in the picker.
struct ZoteroPick { let source: ZoteroSource; let location: String }

struct ZoteroPicker: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (ZoteroPick) -> Void
    @AppStorage(ZoteroStyle.key) private var storedStyle = ""
    @State private var collections: [ZoteroCollection] = []
    @State private var collectionKey = ""
    @State private var adding = false
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
    private var searchKey: String { "\(libraryID)|\(collectionKey)|\(fullText)|\(query)|\(refreshID)" }
    private var style: String { ZoteroStyle.current(stored: storedStyle) }
    /// Collections as an indented outline (projects and their sub-collections).
    private var collectionRows: [(ZoteroCollection, Int)] {
        var rows: [(ZoteroCollection, Int)] = []
        func add(parent: String?, depth: Int) {
            for collection in collections.filter({ $0.parent == parent }).sorted(by: { $0.data.name.localizedStandardCompare($1.data.name) == .orderedAscending }) {
                rows.append((collection, depth)); add(parent: collection.key, depth: depth + 1)
            }
        }
        add(parent: nil, depth: 0)
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Zotero source").font(.title2.bold())
            HStack {
                Picker("Library", selection: $libraryID) {
                    ForEach(libraries) { library in Text(library.name).tag(library.id) }
                }.frame(maxWidth: 230)
                Picker("Collection", selection: $collectionKey) {
                    Text("All items").tag("")
                    ForEach(collectionRows, id: \.0.key) { row in
                        Text(String(repeating: "   ", count: row.1) + row.0.data.name).tag(row.0.key)
                    }
                }.frame(maxWidth: 240).help("Limit the search to one project collection")
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
                Button(adding ? "Adding…" : "Add source") {
                    if let item = items.first(where: { $0.key == selection }) { Task { await add(item) } }
                }.disabled(selection == nil || adding).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 640, height: 520)
        .task { loadGroups(); loadCollections() }
        .onChange(of: libraryID) { _ in collectionKey = ""; loadCollections() }
        .task(id: searchKey) {
            // Invalidate earlier requests immediately, even during the debounce period.
            requestID = UUID()
            selection = nil
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            await search(append: false)
        }
    }
    private func loadCollections() {
        let library = currentLibrary
        URLSession.shared.dataTask(with: ZoteroSearchAPI.collectionsRequest(library: library)) { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
                  let found = try? JSONDecoder().decode([ZoteroCollection].self, from: data) else { return }
            DispatchQueue.main.async { if library == currentLibrary { collections = found } }
        }.resume()
    }

    /// Looks up the item's PDF so the page can open in Zotero's reader, then hands back the source.
    @MainActor private func add(_ item: ZoteroItem) async {
        adding = true
        let library = currentLibrary
        var pdf: String?
        if let (data, response) = try? await URLSession.shared.data(for: ZoteroSearchAPI.childrenRequest(library: library, key: item.key)),
           (response as? HTTPURLResponse)?.statusCode == 200, let children = try? JSONDecoder().decode([ZoteroChild].self, from: data) {
            pdf = ZoteroSearchAPI.readableAttachment(in: children)
        }
        let cite = item.citation.map { ZoteroCitation.markdown(fromHTML: $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? item.description
        adding = false
        onPick(ZoteroPick(source: ZoteroSource(key: item.key, library: library.id, pdf: pdf, cite: cite), location: location))
        dismiss()
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
            let (data, response) = try await URLSession.shared.data(for: ZoteroSearchAPI.itemsRequest(library: library, query: term, fullText: fullText, start: start, collection: collectionKey.isEmpty ? nil : collectionKey, style: style))
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

// MARK: Sources (Zotero is the system of record; citations live in each card's footnotes)

/// A Zotero item as cited in a footnote: item key, library ("personal" or a group ID),
/// the PDF/EPUB attachment key when known, and the short citation without a page.
struct ZoteroSource: Equatable {
    var key: String
    var library: String = "personal"
    var pdf: String?
    var cite: String

    var itemPath: String { library == "personal" ? "library/items/\(key)" : "groups/\(library)/items/\(key)" }
    var selectURL: URL? { URL(string: "zotero://select/\(itemPath)") }
    func attachmentPath(_ attachment: String) -> String { library == "personal" ? "library/items/\(attachment)" : "groups/\(library)/items/\(attachment)" }
    var zoteroLibrary: ZoteroLibrary { library == "personal" ? .personal : ZoteroLibrary(id: library, name: library) }
}

enum ZoteroCitation {
    /// Zotero's HTML citation ("<ol><li>Lim, <i>Title</i></li></ol>") as Markdown ("Lim, *Title*").
    /// `trimPeriod` drops the final period (citations get a page after them); bibliography entries keep it.
    static func markdown(fromHTML html: String, trimPeriod: Bool = true) -> String {
        var text = html.replacingOccurrences(of: "</div>", with: " ")
        for (tag, mark) in [("i", "*"), ("em", "*"), ("b", "**"), ("strong", "**")] {
            text = text.replacingOccurrences(of: "<\(tag)>", with: mark).replacingOccurrences(of: "</\(tag)>", with: mark)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities (CSL writes "&#38;" for "&"); &amp; last so "&amp;lt;" stays literal.
        while let range = text.range(of: "&#[0-9]{1,6};", options: .regularExpression) {
            let number = UInt32(text[range].dropFirst(2).dropLast()) ?? 0
            text.replaceSubrange(range, with: Unicode.Scalar(number).map { String(Character($0)) } ?? "")
        }
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return trimPeriod ? text.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : text
    }
}

/// Citation styles installed in Zotero (its data folder's styles/*.csl), so Kaster never asks
/// Zotero for a style it would have to download.
struct ZoteroStyle: Identifiable, Hashable {
    let id: String
    let title: String
    static let key = "kasterZoteroStyle"
    static let preferred = ["chicago-shortened-notes-bibliography", "chicago-notes-bibliography"]

    static func dataDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let profiles = home.appendingPathComponent("Library/Application Support/Zotero/Profiles")
        if let profile = try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil).first,
           let prefs = try? String(contentsOf: profile.appendingPathComponent("prefs.js"), encoding: .utf8),
           let line = prefs.components(separatedBy: "\n").first(where: { $0.contains("\"extensions.zotero.dataDir\"") }),
           let start = line.range(of: ", \""), let end = line.range(of: "\")", options: .backwards), start.upperBound < end.lowerBound {
            return URL(fileURLWithPath: String(line[start.upperBound..<end.lowerBound]), isDirectory: true)
        }
        return home.appendingPathComponent("Zotero", isDirectory: true)
    }

    static func installed(in folder: URL = dataDirectory().appendingPathComponent("styles")) -> [ZoteroStyle] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "csl" }.map { file in
            let xml = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            var title = file.deletingPathExtension().lastPathComponent
            if let open = xml.range(of: "<title>"), let close = xml.range(of: "</title>", range: open.upperBound..<xml.endIndex) {
                title = String(xml[open.upperBound..<close.lowerBound]).replacingOccurrences(of: "&amp;", with: "&")
            }
            return ZoteroStyle(id: file.deletingPathExtension().lastPathComponent, title: title)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The chosen style if still installed; otherwise short Chicago notes, then any installed style.
    static func current(stored: String, installed: [ZoteroStyle] = installed()) -> String {
        let ids = Set(installed.map(\.id))
        if !stored.isEmpty, ids.contains(stored) { return stored }
        return preferred.first { ids.contains($0) } ?? installed.first?.id ?? "chicago-notes-bibliography"
    }
}

/// Opens a cited page in Zotero's reader. Book page numbers are matched against the PDF's own
/// page labels, so printed page 42 opens even when it is the PDF's 60th page.
enum ZoteroPageOpener {
    static func pageIndex(label: String, in document: PDFDocument) -> Int? {
        let wanted = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return nil }
        for index in 0..<document.pageCount where document.page(at: index)?.label?.lowercased() == wanted { return index }
        return nil
    }

    /// First page number in a location like "42", "p. 42", "42–44"; nil for "ch. 4".
    static func firstPage(_ location: String) -> String? {
        var text = location.trimmingCharacters(in: .whitespaces)
        for prefix in ["pp.", "p."] where text.lowercased().hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        let first = text.split(whereSeparator: { "–—-, ".contains($0) }).first.map(String.init) ?? ""
        guard !first.isEmpty, first.allSatisfy({ $0.isNumber }) || first.range(of: "^[ivxlcdm]+$", options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return first
    }

    static func url(for source: ZoteroSource, page: String?, pdfFile: URL?) -> URL? {
        guard let pdf = source.pdf, let page = page.flatMap(firstPage) else { return source.selectURL }
        let attachmentPath = source.attachmentPath(pdf)
        var number = Int(page)
        if let pdfFile, let document = PDFDocument(url: pdfFile), let index = pageIndex(label: page, in: document) { number = index + 1 }
        guard let number else { return URL(string: "zotero://open-pdf/\(attachmentPath)") }
        return URL(string: "zotero://open-pdf/\(attachmentPath)?page=\(number)")
    }

    /// The attachment's file in Zotero's storage folder (no network or running Zotero needed).
    static func localFile(for source: ZoteroSource) -> URL? {
        guard let pdf = source.pdf else { return nil }
        let folder = ZoteroStyle.dataDirectory().appendingPathComponent("storage").appendingPathComponent(pdf)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.pathExtension.lowercased() == "pdf" }
    }
}

/// Zotero sources as Markdown footnotes: a `[^n]` marker where you're writing and, at the bottom
/// of the card, `[^n]: [Lim, *Title*](zotero://select/…), [42](zotero://open-pdf/…?page=42).`
/// Everything lives in the card's own text, so it also works in Obsidian; several sources per card.
enum ZoteroFootnote {
    private static let labelPattern = try! NSRegularExpression(pattern: "\\[\\^([^\\]\\s]+)\\]")
    private static let definitionPattern = try! NSRegularExpression(pattern: "^\\[\\^[^\\]\\s]+\\]:", options: .anchorsMatchLines)

    /// The next free number: one more than the highest numeric footnote label in the card.
    static func nextLabel(in text: String) -> String {
        let ns = text as NSString
        let numbers = labelPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        return String((numbers.max() ?? 0) + 1)
    }

    static func escapeLabel(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    /// The footnote text for a source and page.
    static func citation(_ source: ZoteroSource, page rawPage: String?) -> String {
        let page = rawPage?.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        let cite = source.cite.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let select = source.selectURL?.absoluteString ?? ""
        let pdfURL: String? = {
            guard let pdf = source.pdf, !page.isEmpty, ZoteroPageOpener.firstPage(page) != nil,
                  let encoded = page.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
            return "zotero://open-pdf/\(source.attachmentPath(pdf))?page=\(encoded)"
        }()
        let pageText = pdfURL.map { "[\(escapeLabel(page))](\($0))" } ?? escapeLabel(page)
        if page.isEmpty {
            // A citation ending in a quoted title closes with the period inside: “Title.”
            for quote in ["\u{201D}", "\""] where cite.hasSuffix("." + quote) || cite.hasSuffix("," + quote) {
                return "[\(escapeLabel(String(cite.dropLast(2)) + "." + quote))](\(select))"
            }
            return "[\(escapeLabel(cite))](\(select))."
        }
        // Author-date styles: "(Lim, n.d., 42)" — the page goes inside the parentheses.
        if cite.hasPrefix("("), cite.hasSuffix(")") {
            return "([\(escapeLabel(String(cite.dropFirst().dropLast())))](\(select)), \(pageText))."
        }
        // Chicago puts the comma inside a closing quotation mark: “Title,” 42.
        for quote in ["\u{201D}", "\""] where cite.hasSuffix("." + quote) || cite.hasSuffix("," + quote) {
            return "[\(escapeLabel(String(cite.dropLast(2)) + "," + quote))](\(select)) \(pageText)."
        }
        return "[\(escapeLabel(cite))](\(select)), \(pageText)."
    }

    /// What to append at the end of the card for a new definition, so footnotes stay together at
    /// the bottom: one newline after an existing footnote, a blank line after anything else.
    static func appendix(label: String, citation: String, to text: String) -> String {
        let definition = "[^\(label)]: \(citation)\n"
        let trailingNewlines = text.reversed().prefix { $0 == "\n" || $0 == "\r\n" }.count
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return definition }
        let lastLine = body.components(separatedBy: "\n").last ?? ""
        let afterFootnote = lastLine.range(of: "^\\[\\^[^\\]\\s]+\\]:", options: .regularExpression) != nil
        let wanted = afterFootnote ? 1 : 2
        return String(repeating: "\n", count: max(0, wanted - trailingNewlines)) + definition
    }

    /// The whole card with a footnote marker inserted at `location` and its definition appended.
    static func inserting(_ source: ZoteroSource, page: String?, into text: String, at location: Int) -> (text: String, caret: Int) {
        let label = nextLabel(in: text)
        let marker = "[^\(label)]"
        let ns = text as NSString
        let at = min(max(0, location), ns.length)
        let withMarker = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: marker)
        return (withMarker + appendix(label: label, citation: citation(source, page: page), to: withMarker), at + (marker as NSString).length)
    }
}

extension ZoteroPageOpener {
    /// Any zotero:// link clicked in a card. open-pdf links with a page are matched to the PDF's
    /// own page labels (book page 42 → the right PDF page); everything else opens as written.
    static func resolve(_ raw: String) -> URL? {
        guard let components = URLComponents(string: raw), components.scheme?.lowercased() == "zotero" else { return nil }
        guard components.host?.lowercased() == "open-pdf" else { return URL(string: raw) }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let items = parts.firstIndex(of: "items"), items + 1 < parts.count else { return URL(string: raw) }
        let library = parts.first == "groups" && parts.count > 1 ? parts[1] : "personal"
        let page = components.queryItems?.first { $0.name == "page" }?.value
        let source = ZoteroSource(key: "", library: library, pdf: parts[items + 1], cite: "")
        guard page != nil else { return URL(string: raw) }
        return url(for: source, page: page, pdfFile: localFile(for: source)) ?? URL(string: raw)
    }
}
