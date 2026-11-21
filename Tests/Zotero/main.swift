import Foundation
import PDFKit

// Zotero as the system of record: inline citations, page links, styles. No network needed
// unless KASTER_LIVE_ZOTERO=1 (then it also asks the running Zotero for a real citation).
@main struct Checks {
    static func main() async throws {
        // Zotero's HTML citations, exactly as Zotero 10 returns them.
        precondition(ZoteroCitation.markdown(fromHTML: "<ol>\n\t<li>Lim, <i>How Was the Canon Formed?</i></li>\n</ol>") == "Lim, *How Was the Canon Formed?*")
        precondition(ZoteroCitation.markdown(fromHTML: "<ol>\n\t<li>Timothy H. Lim, <i>How Was the Canon Formed?</i>, n.d.</li>\n</ol>") == "Timothy H. Lim, *How Was the Canon Formed?*, n.d")
        precondition(ZoteroCitation.markdown(fromHTML: "(Lim &amp; Smith, n.d.)") == "(Lim & Smith, n.d.)")

        // The visible line, with and without a page; parenthetical styles keep the page inside.
        let note = "Lim, *How Was the Canon Formed?*"
        precondition(ZoteroSource.line(cite: note, page: "42") == "Lim, *How Was the Canon Formed?*, 42.")
        precondition(ZoteroSource.line(cite: note, page: " ") == "Lim, *How Was the Canon Formed?*.")
        precondition(ZoteroSource.line(cite: "(Lim, n.d.)", page: "42") == "(Lim, n.d., 42).")
        let wiki = "*Wikipedia*, \u{201C}Jewish–Christian gospels.\u{201D}"
        precondition(ZoteroSource.line(cite: wiki, page: "42") == "*Wikipedia*, \u{201C}Jewish–Christian gospels,\u{201D} 42.", ZoteroSource.line(cite: wiki, page: "42"))
        precondition(ZoteroSource.page(in: "Source: " + ZoteroSource.line(cite: wiki, page: "42"), cite: wiki) == "42")

        // Writing, reading, changing and removing a source on a Research card.
        let card = "---\nuid: abc\n---\n# On the canon\n\n> A quotation.\n\nMy response.\n\nSource: Old, *Thing*\nZotero: [Open source](zotero://select/library/items/OLD)\n"
        let source = ZoteroSource(key: "D9QP9N8Q", pdf: "DWMEC776", cite: note)
        let cited = ZoteroSource.apply(source, page: "42", to: card)
        precondition(ZoteroSource.read(cited) == source, "Round trip: \(String(describing: ZoteroSource.read(cited)))")
        precondition(cited.contains("\nSource: Lim, *How Was the Canon Formed?*, 42.\n") && !cited.contains("Zotero: [Open source]"), cited)
        precondition(cited.hasPrefix("---\nuid: abc\nzotero: D9QP9N8Q\nzotero-pdf: DWMEC776\nzotero-cite: \"Lim, *How Was the Canon Formed?*\"\n---\n"), cited)
        precondition(!cited.contains("zotero-library"), "My Library needs no library field")
        precondition(ZoteroSource.page(in: cited, cite: note) == "42")
        let moved = ZoteroSource.apply(source, page: "43–45", to: cited)
        precondition(ZoteroSource.page(in: moved, cite: note) == "43–45" && moved.components(separatedBy: "Source:").count == 2, "Changing the page edits the one Source line")
        let removed = ZoteroSource.apply(nil, page: nil, to: moved)
        precondition(ZoteroSource.read(removed) == nil && !removed.contains("Source:") && removed.contains("uid: abc"), removed)
        let fresh = ZoteroSource.apply(ZoteroSource(key: "K", library: "123", cite: "(Lim, n.d.)"), page: "7", to: "# Card\n\nText")
        precondition(fresh.hasPrefix("---\nzotero: K\nzotero-library: 123\nzotero-cite: \"(Lim, n.d.)\"\n---\n") && fresh.hasSuffix("\n\nSource: (Lim, n.d., 7).\n"), fresh)
        precondition(ZoteroSource.page(in: fresh, cite: "(Lim, n.d.)") == "7" && ZoteroSource.read(fresh)?.library == "123")
        precondition(ZoteroSource.read(fresh)?.selectURL?.absoluteString == "zotero://select/groups/123/items/K")
        let quotes = ZoteroSource.apply(ZoteroSource(key: "Q", cite: "Doe, \"A \\ B\""), page: nil, to: "# T\n")
        precondition(ZoteroSource.read(quotes)?.cite == "Doe, \"A \\ B\"", "Quotes in titles survive: \(String(describing: ZoteroSource.read(quotes)?.cite))")

        // Page links: printed page → PDF page via labels; "ch. 4" or no PDF → select the item.
        precondition(ZoteroPageOpener.firstPage("42") == "42" && ZoteroPageOpener.firstPage("p. 42–44") == "42" && ZoteroPageOpener.firstPage("xii") == "xii")
        precondition(ZoteroPageOpener.firstPage("ch. 4") == nil)
        precondition(ZoteroPageOpener.url(for: source, page: "42", pdfFile: nil)?.absoluteString == "zotero://open-pdf/library/items/DWMEC776?page=42")
        precondition(ZoteroPageOpener.url(for: source, page: "ch. 4", pdfFile: nil)?.absoluteString == "zotero://select/library/items/D9QP9N8Q")
        precondition(ZoteroPageOpener.url(for: ZoteroSource(key: "D9QP9N8Q", cite: note), page: "42", pdfFile: nil)?.absoluteString == "zotero://select/library/items/D9QP9N8Q")
        precondition(ZoteroPageOpener.url(for: ZoteroSource(key: "K", library: "9", pdf: "P", cite: note), page: "3", pdfFile: nil)?.absoluteString == "zotero://open-pdf/groups/9/items/P?page=3")
        // A PDF whose pages are labelled i, ii, 1, 2…: printed page 2 is the 4th PDF page.
        let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-labels-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        try labelledPDF().write(to: pdfURL)
        if let document = PDFDocument(url: pdfURL), document.page(at: 3)?.label == "2" {
            precondition(ZoteroPageOpener.pageIndex(label: "2", in: document) == 3)
            precondition(ZoteroPageOpener.url(for: source, page: "2", pdfFile: pdfURL)?.absoluteString == "zotero://open-pdf/library/items/DWMEC776?page=4", "Book page 2 opens PDF page 4")
            print("Page labels: book page → PDF page passed")
        } else { print("Page labels: this PDFKit build does not read labels from the test PDF; skipped") }

        // Attachments: prefer a stored PDF, then EPUB; never a web link.
        let children = try JSONDecoder().decode([ZoteroChild].self, from: Data("""
        [{"key":"L","data":{"itemType":"attachment","contentType":"application/pdf","linkMode":"linked_url"}},
         {"key":"E","data":{"itemType":"attachment","contentType":"application/epub+zip","linkMode":"imported_file"}},
         {"key":"N","data":{"itemType":"note"}},
         {"key":"P","data":{"itemType":"attachment","contentType":"application/pdf","linkMode":"imported_url"}}]
        """.utf8))
        precondition(ZoteroSearchAPI.readableAttachment(in: children) == "P")
        let collections = try JSONDecoder().decode([ZoteroCollection].self, from: Data(#"[{"key":"A","data":{"name":"Catholicism","parentCollection":false}},{"key":"B","data":{"name":"Sub","parentCollection":"A"}}]"#.utf8))
        precondition(collections[0].parent == nil && collections[1].parent == "A")
        let request = ZoteroSearchAPI.itemsRequest(library: .personal, query: "canon", fullText: false, start: 0, collection: "A", style: "apa")
        precondition(request.url!.absoluteString.contains("/api/users/0/collections/A/items/top?") && request.url!.absoluteString.contains("include=data,citation") && request.url!.absoluteString.contains("style=apa"))

        // Styles: the installed ones, preferring short Chicago notes.
        let styles = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-styles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: styles) }
        try Data("<style><info><title>Chicago Manual of Style 18th edition (shortened notes and bibliography)</title></info></style>".utf8).write(to: styles.appendingPathComponent("chicago-shortened-notes-bibliography.csl"))
        try Data("<style><info><title>American Psychological Association 7th edition</title></info></style>".utf8).write(to: styles.appendingPathComponent("apa.csl"))
        let installed = ZoteroStyle.installed(in: styles)
        precondition(installed.map(\.id) == ["apa", "chicago-shortened-notes-bibliography"], "\(installed)")
        precondition(ZoteroStyle.current(stored: "", installed: installed) == "chicago-shortened-notes-bibliography")
        precondition(ZoteroStyle.current(stored: "apa", installed: installed) == "apa")
        precondition(ZoteroStyle.current(stored: "removed-style", installed: installed) == "chicago-shortened-notes-bibliography")

        if ProcessInfo.processInfo.environment["KASTER_LIVE_ZOTERO"] == "1" {
            let (data, _) = try await URLSession.shared.data(for: ZoteroSearchAPI.itemsRequest(library: .personal, query: "", fullText: false, start: 0, limit: 3, style: ZoteroStyle.current(stored: "")))
            let items = try JSONDecoder().decode([ZoteroItem].self, from: data)
            for item in items { print("Live:", ZoteroSource.line(cite: ZoteroCitation.markdown(fromHTML: item.citation ?? ""), page: "42")) }
            precondition(items.allSatisfy { $0.citation?.isEmpty == false }, "Zotero returned citations")
        }
        print("Zotero inline citations, sources, page links, attachments and styles passed")
    }

    /// A 5-page PDF with page labels i, ii, 1, 2, 3.
    static func labelledPDF() -> Data {
        var objects: [String] = []
        let pages = (0..<5).map { 4 + $0 }
        objects.append("<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [0 << /S /r >> 2 << /S /D >>] >> >>")
        objects.append("<< /Type /Pages /Kids [\(pages.map { "\($0) 0 R" }.joined(separator: " "))] /Count 5 >>")
        objects.append("<< >>")
        for _ in pages { objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources 3 0 R >>") }
        var output = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(output.utf8.count)
            output += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = output.utf8.count
        output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n" + offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        output += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(output.utf8)
    }
}
