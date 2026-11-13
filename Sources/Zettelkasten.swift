import SwiftUI
import AppKit

// card_id is stored in ordinary YAML frontmatter; existing files are never renamed.
enum CardMetadata {
    static func parse(_ text: String) -> (id: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return (nil, text) }
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("card_id:") else { continue }
            let value = String(trimmed.dropFirst("card_id:".count)).trimmingCharacters(in: .whitespaces)
            let id: String
            if value.hasPrefix("\"") {
                guard let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) else { return (nil, text) }
                id = decoded
            } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                id = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            } else {
                id = value.components(separatedBy: " #").first?.trimmingCharacters(in: .whitespaces) ?? ""
            }
            guard !id.isEmpty else { return (nil, text) }
            return (id, lines.dropFirst(end + 1).joined(separator: "\n"))
        }
        return (nil, text)
    }
    static func hasNonemptyID(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return false }
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("card_id:") {
                let raw = String(trimmed.dropFirst("card_id:".count)).trimmingCharacters(in: .whitespaces)
                return !raw.isEmpty && raw != "\"\"" && raw != "''" && !raw.hasPrefix("#")
            }
        }
        return false
    }
    static func frontmatter(_ id: String) -> String {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, let data = try? JSONEncoder().encode(id), let encoded = String(data: data, encoding: .utf8) else { return "" }
        return "---\ncard_id: \(encoded)\n---\n\n"
    }
}

enum CardIDIndex {
    enum ScanError: LocalizedError {
        case inaccessible
        case invalidMetadata(String)
        var errorDescription: String? {
            switch self {
            case .inaccessible: return "The notes folder could not be fully read."
            case .invalidMetadata(let file): return "The card_id in \(file) could not be read."
            }
        }
    }
    static func ids(in root: URL, excluding target: URL? = nil) throws -> [(String, URL)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        var encounteredError = false
        guard FileManager.default.isReadableFile(atPath: root.path),
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in encounteredError = true; return false }) else { throw ScanError.inaccessible }
        var result: [(String, URL)] = []
        for case let url as URL in enumerator {
            let properties = try url.resourceValues(forKeys: Set(keys))
            if properties.isSymbolicLink == true || properties.isRegularFile != true || url.pathExtension.lowercased() != "md" { continue }
            if url.standardizedFileURL == target?.standardizedFileURL { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if let id = CardMetadata.parse(text).id { result.append((id, url)) }
            else if CardMetadata.hasNonemptyID(text) { throw ScanError.invalidMetadata(url.lastPathComponent) }
        }
        if encounteredError { throw ScanError.inaccessible }
        return result
    }
    static func suggest(in root: URL?) -> String {
        let existing = (root.flatMap { try? ids(in: $0) } ?? []).map { $0.0.lowercased() }
        var n = 1
        while existing.contains(String(format: "c-%04d", n)) { n += 1 }
        return String(format: "C-%04d", n)
    }
}

struct CardRelation: Identifiable {
    let id = UUID()
    var link: String
    var explanation = ""
}

struct ZettelEditor: View {
    enum Kind: String, CaseIterable, Identifiable { case idea = "Idea", reading = "Reading", index = "Index"; var id: String { rawValue } }
    @Environment(\.dismiss) private var dismiss
    let kind: Kind
    let hasDraft: Bool
    let onUse: (String) -> Void
    @State var cardID: String
    @State private var title = ""
    @State private var bodyText = ""
    @State private var response = ""
    @State private var source = ""
    @State private var page = ""
    @State private var zoteroLink = ""
    @State private var relations: [CardRelation] = []
    @State private var showNotes = false
    @State private var showZotero = false
    @State private var confirmReplace = false

    var markdown: String {
        let heading = title.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [CardMetadata.frontmatter(cardID) + "# " + (heading.isEmpty ? "Untitled \(kind.rawValue)" : heading)]
        if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append((kind == .reading ? "## Quotation or summary\n" : "") + bodyText)
        }
        if kind == .reading && !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("## My response\n" + response) }
        let citation = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = page.trimmingCharacters(in: .whitespacesAndNewlines)
        if !citation.isEmpty || !location.isEmpty {
            parts.append("Source: " + [citation, location].filter { !$0.isEmpty }.joined(separator: ", ") + (zoteroLink.isEmpty ? "" : "\n" + zoteroLink))
        }
        if !relations.isEmpty {
            parts.append("## Related cards\n" + relations.map { "- " + $0.link + ($0.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " — " + $0.explanation.trimmingCharacters(in: .whitespacesAndNewlines)) }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(kind.rawValue) card").font(.title2.bold())
            HStack { TextField("Card ID (optional)", text: $cardID).frame(width: 165); TextField("Title", text: $title) }
            Text(kind == .reading ? "Quotation or summary" : kind == .index ? "Notes (optional)" : "Idea").font(.caption)
            TextEditor(text: $bodyText).font(.system(size: 13)).border(Color.secondary.opacity(0.25)).frame(minHeight: 65, maxHeight: 110)
            if kind == .reading {
                Text("My response").font(.caption)
                TextEditor(text: $response).font(.system(size: 13)).border(Color.secondary.opacity(0.25)).frame(minHeight: 50, maxHeight: 75)
                HStack {
                    TextField("Source", text: $source)
                    TextField("Page / location", text: $page).frame(width: 135)
                    Button("Zotero…") { showZotero = true }
                }
                if !zoteroLink.isEmpty { Text("Zotero link attached").font(.caption).foregroundStyle(.secondary) }
            }
            HStack { Text("Related cards").fontWeight(.medium); Spacer(); Button("Add link…") { showNotes = true } }
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach($relations) { $relation in
                        HStack {
                            Text(relation.link).lineLimit(1).frame(width: 180, alignment: .leading)
                            TextField("Why is it related?", text: $relation.explanation)
                            Button { relations.removeAll { $0.id == relation.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        }
                    }
                }
            }.frame(minHeight: 35, maxHeight: 100)
            Text(cardID.contains(where: { $0.isNewline }) ? "Card IDs must be a single line." : "ID is optional. The current draft is replaced only if you confirm.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Create card") { if hasDraft { confirmReplace = true } else { onUse(markdown); dismiss() } }.buttonStyle(.borderedProminent).disabled(cardID.contains(where: { $0.isNewline })) }
        }.padding(20).frame(width: 610, height: kind == .reading ? 610 : 500)
        .alert("Replace the current Markdown draft?", isPresented: $confirmReplace) {
            Button("Cancel", role: .cancel) {}
            Button("Replace Draft", role: .destructive) { onUse(markdown); dismiss() }
        } message: { Text("Save it first if you want to keep it. The existing file is not changed.") }
        .sheet(isPresented: $showNotes) { NotePicker { link in relations.append(CardRelation(link: link)) } }
        .sheet(isPresented: $showZotero) {
            ZoteroPicker { value in
                let lines = value.components(separatedBy: "\n")
                source = lines.first.map { $0.hasPrefix("Source: ") ? String($0.dropFirst(8)) : $0 } ?? ""
                zoteroLink = lines.first(where: { $0.hasPrefix("Zotero: ") }) ?? ""
            }
        }
    }
}
