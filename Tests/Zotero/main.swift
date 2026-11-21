@testable import KasterCore
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

        // Bibliography entries keep their period; numeric entities and numbered styles read cleanly.
        precondition(ZoteroCitation.markdown(fromHTML: "<div class=\"csl-bib-body\">\n  <div class=\"csl-entry\">Lim, Timothy H. <i>How Was the Canon Formed?</i> Oxford: OUP &#38; Co., 2013.</div>\n</div>", trimPeriod: false)
                     == "Lim, Timothy H. *How Was the Canon Formed?* Oxford: OUP & Co., 2013.")
        precondition(ZoteroCitation.markdown(fromHTML: "<div class=\"csl-entry\"><div class=\"csl-left-margin\">1.</div><div class=\"csl-right-inline\">Doe, <i>A</i>.</div></div>", trimPeriod: false) == "1. Doe, *A*.")
        let bibURL = ZoteroSearchAPI.bibliographyRequest(library: ZoteroLibrary(id: "12", name: "G"), keys: ["A", "B"], style: "apa").url!.absoluteString
        precondition(bibURL.contains("/api/groups/12/items?") && bibURL.contains("itemKey=A,B") && bibURL.contains("include=bib") && bibURL.contains("style=apa"), bibURL)

        let note = "Lim, *How Was the Canon Formed?*"
        let source = ZoteroSource(key: "D9QP9N8Q", pdf: "DWMEC776", cite: note)
        precondition(source.selectURL?.absoluteString == "zotero://select/library/items/D9QP9N8Q")
        precondition(ZoteroSource(key: "K", library: "123", cite: "x").selectURL?.absoluteString == "zotero://select/groups/123/items/K")

        // Footnote sources: Zotero footnotes in every style Kaster writes, read back exactly.
        let wiki = ZoteroSource(key: "W", cite: "*Wikipedia*, \u{201C}Jewish–Christian gospels.\u{201D}")
        let paren = ZoteroSource(key: "K", library: "123", cite: "(Lim, n.d.)")
        for (zotero, page) in [(source, "42"), (source, "43–45"), (source, nil), (source, "ch. 4"), (ZoteroSource(key: "N", cite: note), "42"),
                               (wiki, "3"), (wiki, nil), (paren, "7"), (paren, nil), (ZoteroSource(key: "B", cite: "Doe, [Brackets]"), "9")] as [(ZoteroSource, String?)] {
            let card = "# Card\n\nClaim.[^1]\n\n[^1]: " + ZoteroFootnote.citation(zotero, page: page) + "\n"
            let found = FootnoteSources.parse(card)
            precondition(found.count == 1 && found[0].label == "1" && found[0].pageEditable, "\(zotero) \(String(describing: page)): \(found)")
            precondition(found[0].page == page, "Page read back: \(String(describing: found[0].page)) for \(String(describing: page))")
            var expected = zotero
            if ZoteroPageOpener.firstPage(page ?? "") == nil { expected.pdf = nil }   // no page link, so the PDF isn't in the text
            if page == nil, zotero == wiki { expected.cite = "*Wikipedia*, \u{201C}Jewish–Christian gospels.\u{201D}" }
            precondition(found[0].zotero?.key == expected.key && found[0].zotero?.library == expected.library && found[0].zotero?.pdf == expected.pdf, "\(String(describing: found[0].zotero))")
            precondition(ZoteroFootnote.citation(found[0].zotero!, page: found[0].page) == found[0].text, "Lossless: \(found[0].text)")
        }
        precondition(ZoteroFootnote.citation(wiki, page: nil) == "[*Wikipedia*, \u{201C}Jewish–Christian gospels.\u{201D}](zotero://select/library/items/W)", "No doubled period after a quoted title")
        precondition(ZoteroFootnote.citation(ZoteroSource(key: "W", cite: "*Wikipedia*, \u{201C}Gospels,\u{201D}"), page: " ") == "[*Wikipedia*, \u{201C}Gospels.\u{201D}](zotero://select/library/items/W)", "Removing the page restores the period")
        // The footnote already in Wilbur's vault (an older Kaster wrote an extra period).
        let schmidt = "[^2]: [Schmidt, \u{201C}10 NIKLAS LUHMANN\u{2019}S CARD INDEX The Fabrication of Serendipity.\u{201D}](zotero://select/library/items/ZMLSK5KF)."
        let old = FootnoteSources.parse("Text.[^2]\n\n" + schmidt + "\n")
        precondition(old.count == 1 && old[0].pageEditable && old[0].page == nil && old[0].zotero?.key == "ZMLSK5KF", "\(old)")
        precondition(old[0].title == "Schmidt, \u{201C}10 NIKLAS LUHMANN\u{2019}S CARD INDEX The Fabrication of Serendipity.\u{201D}", old[0].title)
        let paged = FootnoteSources.apply([FootnoteSources.settingPage("12", label: "2", in: "Text.[^2]\n\n" + schmidt + "\n")!], to: "Text.[^2]\n\n" + schmidt + "\n")
        precondition(paged == "Text.[^2]\n\n[^2]: [Schmidt, \u{201C}10 NIKLAS LUHMANN\u{2019}S CARD INDEX The Fabrication of Serendipity,\u{201D}](zotero://select/library/items/ZMLSK5KF) 12.\n", paged)
        // Hand-edited Zotero footnotes are shown but never rewritten.
        let edited = FootnoteSources.parse("A[^1]\n\n[^1]: [Lim](zotero://select/library/items/K), 42. See also chapter 3 for the argument.\n")
        precondition(edited.count == 1 && !edited[0].pageEditable && edited[0].page == nil)
        precondition(FootnoteSources.settingPage("50", label: "1", in: "A[^1]\n\n[^1]: [Lim](zotero://select/library/items/K), 42. See also chapter 3.\n") == nil)
        // Typed citations are sources; card links and explanatory notes are not.
        let mixed = """
        # Septuagint
        A.[^1] B.[^2] C.[^3] D.[^4] E.[^5] F.[^6]

        [^1]: Tov, Emanuel. \u{201C}The Septuagint.\u{201D} In _The Literature of the Jewish People_. 
        [^2]: [[The Early Church believed in the Sacraments and Holy Tradition]]
        [^3]: Most fundamentally, 
        [^4]: G. Archer and G. C. Chirichigno, _Old Testament Quotations in the New Testament: A Complete Survey_, 25-32
        [^5]:  Another reason has been the flood of mediocre AI-writing, devoid of spirit and verve (_it\u{2019}s not just bad_).
        [^6]: [Ali Abdaal, *How to Study for Exams*](zotero://select/library/items/BTJ2IRPZ).
        [^1]: A duplicate label is ignored.
        """
        let sources = FootnoteSources.parse(mixed)
        precondition(sources.map(\.label) == ["1", "4", "6"], "\(sources.map(\.label))")
        precondition(sources[0].kind == .typed && sources[0].page == nil && !sources[0].pageEditable && sources[0].text.hasSuffix("People_."))
        precondition(sources[1].title == "G. Archer and G. C. Chirichigno, Old Testament Quotations in the New Testament: A Complete Survey, 25-32", sources[1].title)
        precondition(sources[2].zotero?.key == "BTJ2IRPZ" && sources[2].title == "Ali Abdaal, How to Study for Exams")
        precondition((mixed as NSString).substring(with: sources[2].range) == sources[2].text, "Ranges point at the definition text")
        precondition(FootnoteSources.looksLikeCitation("[Kaster docs](https://example.com/docs)") && !FootnoteSources.looksLikeCitation("See [[A card]] and *B*"))
        precondition(FootnoteSources.parse("No footnotes here.").isEmpty && FootnoteSources.parse("Text[^1] without a definition").isEmpty)

        // Page edits rewrite only that footnote; the PDF is linked once Zotero names it.
        var research = "# On the canon\n\n> A quotation.[^1]\n\nMy response.[^2]\n\n[^1]: " + ZoteroFootnote.citation(ZoteroSource(key: "D9QP9N8Q", cite: note), page: nil) + "\n[^2]: " + ZoteroFootnote.citation(paren, page: "7") + "\n"
        let before2 = FootnoteSources.parse(research)[1].text
        research = FootnoteSources.apply([FootnoteSources.settingPage("42", label: "1", in: research)!], to: research)
        precondition(FootnoteSources.parse(research)[0].page == "42" && FootnoteSources.parse(research)[0].zotero?.pdf == nil && FootnoteSources.parse(research)[1].text == before2, research)
        precondition(research.contains("[^1]: [Lim, *How Was the Canon Formed?*](zotero://select/library/items/D9QP9N8Q), 42.\n"), research)
        research = FootnoteSources.apply([FootnoteSources.linkingPDF("DWMEC776", label: "1", key: "D9QP9N8Q", in: research)!], to: research)
        precondition(research.contains("[^1]: " + ZoteroFootnote.citation(source, page: "42") + "\n"), research)
        precondition(FootnoteSources.linkingPDF("OTHER", label: "1", key: "D9QP9N8Q", in: research) == nil, "A known PDF is kept")
        precondition(FootnoteSources.linkingPDF("P", label: "1", key: "SOMETHINGELSE", in: research) == nil, "Only the item that was looked up")
        precondition(FootnoteSources.settingPage("42", label: "1", in: research) == nil, "Same page: no edit")
        let cleared = FootnoteSources.apply([FootnoteSources.settingPage("", label: "1", in: research)!], to: research)
        precondition(FootnoteSources.parse(cleared)[0].page == nil && cleared.contains("[^1]: [Lim, *How Was the Canon Formed?*](zotero://select/library/items/D9QP9N8Q).\n"), cleared)
        precondition(FootnoteSources.settingPage("9", label: "missing", in: research) == nil)
        // Removing a footnote takes its markers and its definition line.
        let removed = FootnoteSources.apply(FootnoteSources.removing(label: "1", in: research + "Again.[^1]\n"), to: research + "Again.[^1]\n")
        precondition(!removed.contains("[^1]") && removed.contains("[^2]: ") && removed.contains("> A quotation.\n") && removed.hasSuffix("Again.\n"), removed)

        // Older Research cards (frontmatter fields + a Source line) convert to a footnote on the quotation.
        let legacyCard = "---\nuid: gun3d7qa\nzotero: D9QP9N8Q\nzotero-pdf: DWMEC776\nzotero-cite: \"Lim, *How Was the Canon Formed?*\"\n---\n# Link to zotero\n\n## Quotation\n\n> this is a test\n\n## Response\n\nMine.\n\nSource: Lim, *How Was the Canon Formed?*, 11.\n"
        precondition(FootnoteSources.legacy(in: legacyCard)?.source == source && FootnoteSources.legacy(in: legacyCard)?.page == "11")
        let converted = FootnoteSources.convertingLegacy(legacyCard)!
        precondition(converted.text == "---\nuid: gun3d7qa\n---\n# Link to zotero\n\n## Quotation\n\n> this is a test[^1]\n\n## Response\n\nMine.\n\n[^1]: " + ZoteroFootnote.citation(source, page: "11") + "\n", converted.text)
        precondition((converted.text as NSString).substring(with: converted.marker) == "[^1]" && FootnoteSources.legacy(in: converted.text) == nil)
        let spoils = "---\nuid: g\nzotero: AUMTBS34\nzotero-pdf: HBWWF99L\nzotero-cite: \"Yan et al., \u{201C}Why Does Guessing Incorrectly Enhance?\u{201D}\"\n---\n# War spoils\n\n> And let this city be an anathema.\n>\n> -- Joshua 6:17 (DRB)\n\nMy note. \n\n[1] Source: Yan et al., \u{201C}Why Does Guessing Incorrectly Enhance?\u{201D}.\n"
        let spoilsConverted = FootnoteSources.convertingLegacy(spoils)!.text
        precondition(spoilsConverted.contains("> -- Joshua 6:17 (DRB)[^1]\n\nMy note.\n\n[^1]: [Yan et al., \u{201C}Why Does Guessing Incorrectly Enhance?\u{201D}](zotero://select/library/items/AUMTBS34).\n") && !spoilsConverted.contains("Source:"), spoilsConverted)
        precondition(FootnoteSources.legacyPage("(Lim, n.d., 42).", cite: "(Lim, n.d.)") == "42" && FootnoteSources.legacyPage("*W*, \u{201C}Gospels,\u{201D} 3.", cite: "*W*, \u{201C}Gospels.\u{201D}") == "3")
        precondition(FootnoteSources.convertingLegacy("# Plain card\n\nSource: [[Book]], p. 4\n") == nil, "Typed Source lines are left alone")

        // The bibliography: one entry per Zotero item or typed citation, with its citing cards.
        func libraryCard(_ path: String, _ content: String) -> LibraryCard {
            LibraryCard(url: URL(fileURLWithPath: "/vault/" + path), path: path, title: (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""), cardID: nil, content: content)
        }
        let bibliography = FootnoteBibliography.collect([
            libraryCard("Research/B card.md", research),
            libraryCard("Zettel/A card.md", "X[^1] Y[^2]\n\n[^1]: " + ZoteroFootnote.citation(source, page: "50") + "\n[^2]: G. Archer, _Quotations_, 25-32\n"),
            libraryCard("Quick/C card.md", "Z[^7]\n\n[^7]: G. Archer, _Quotations_, p. 40.\n[^8]: [[Just a link]]\n"),
            libraryCard("Quick/D.md", "No sources."),
        ])
        precondition(bibliography.map(\.text) == ["G. Archer, _Quotations_.", "Lim, *How Was the Canon Formed?*", "(Lim, n.d.)"], "\(bibliography.map(\.text))")
        precondition(bibliography[0].cards.map(\.title) == ["A card", "C card"], "Typed citations group across pages")
        precondition(bibliography[1].id == "zotero:personal/D9QP9N8Q" && bibliography[1].cards.map(\.title) == ["A card", "B card"] && bibliography[1].zotero?.pdf == "DWMEC776")
        precondition(bibliography[2].zotero?.library == "123")
        precondition(FootnoteBibliography.withoutPage("Tov, *Septuagint*, xii–xiv.") == "Tov, *Septuagint*." && FootnoteBibliography.withoutPage("Smith, *Method*") == "Smith, *Method*.")
        let printCards = FootnoteBibliography.printCards((1...7).map { "\($0 < 4 ? "Adams" : "Zahn"), *Book*." }, perCard: 5)
        precondition(printCards.count == 2 && printCards[0].hasPrefix("# Bibliography A–Z\n\nAdams, *Book*.\n\n") && printCards[1].hasPrefix("# Bibliography Z\n"), "\(printCards)")
        precondition(FootnoteBibliography.printCards(["Doe, *A*."]) == ["# Bibliography\n\nDoe, *A*.\n"])

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

        let raw = "zotero://open-pdf/library/items/DWMEC776?page=42"
        if case .external = CardLinkNavigation.resolve(.url(raw), folder: nil, currentFile: nil) {} else { preconditionFailure("open-pdf links are allowed") }

        // Footnotes: [^n] at the cursor, numbered definitions together at the bottom.
        let lim = ZoteroSource(key: "D9QP9N8Q", pdf: "DWMEC776", cite: "Lim, *How Was the Canon Formed?*")
        precondition(ZoteroFootnote.citation(lim, page: "42") == "[Lim, *How Was the Canon Formed?*](zotero://select/library/items/D9QP9N8Q), [42](zotero://open-pdf/library/items/DWMEC776?page=42).")
        precondition(ZoteroFootnote.citation(lim, page: nil) == "[Lim, *How Was the Canon Formed?*](zotero://select/library/items/D9QP9N8Q).")
        precondition(ZoteroFootnote.citation(lim, page: "ch. 4") == "[Lim, *How Was the Canon Formed?*](zotero://select/library/items/D9QP9N8Q), ch. 4.", "Non-page locations aren't PDF links")
        precondition(ZoteroFootnote.citation(ZoteroSource(key: "K", cite: "(Lim, n.d.)"), page: "7") == "([Lim, n.d.](zotero://select/library/items/K), 7).")
        precondition(ZoteroFootnote.citation(ZoteroSource(key: "W", cite: "*Wikipedia*, \u{201C}Gospels.\u{201D}"), page: "3") == "[*Wikipedia*, \u{201C}Gospels,\u{201D}](zotero://select/library/items/W) 3.")
        precondition(ZoteroFootnote.citation(ZoteroSource(key: "B", cite: "Doe, [Brackets]"), page: nil) == "[Doe, \\[Brackets\\]](zotero://select/library/items/B).", "Brackets in titles are escaped")
        precondition(ZoteroFootnote.nextLabel(in: "No notes") == "1" && ZoteroFootnote.nextLabel(in: "A[^1] B[^lim] C[^3]\n\n[^1]: x\n[^3]: y") == "4")
        var footCard = "# Canon\n\nThe canon closed early. Others disagree.\n"
        let first = ZoteroFootnote.inserting(lim, page: "42", into: footCard, at: ("# Canon\n\nThe canon closed early." as NSString).length)
        precondition(first.text == "# Canon\n\nThe canon closed early.[^1] Others disagree.\n\n[^1]: " + ZoteroFootnote.citation(lim, page: "42") + "\n", first.text.debugDescription)
        precondition((first.text as NSString).substring(to: first.caret).hasSuffix("early.[^1]"), "The cursor lands after the marker")
        footCard = first.text
        let second = ZoteroFootnote.inserting(lim, page: "50", into: footCard, at: (footCard as NSString).range(of: "disagree.").upperBoundLocation)
        precondition(second.text.hasSuffix("[^1]: " + ZoteroFootnote.citation(lim, page: "42") + "\n[^2]: " + ZoteroFootnote.citation(lim, page: "50") + "\n"), "Footnotes stay together: \(second.text.debugDescription)")
        precondition(ZoteroFootnote.appendix(label: "1", citation: "c", to: "") == "[^1]: c\n")
        precondition(ZoteroFootnote.appendix(label: "1", citation: "c", to: "Text") == "\n\n[^1]: c\n")
        precondition(ZoteroFootnote.appendix(label: "2", citation: "c", to: "Text\n\n[^1]: a\n") == "[^2]: c\n")
        // Clicks: book page → PDF page through labels; other zotero links open as written.
        precondition(ZoteroPageOpener.resolve("zotero://open-pdf/library/items/NOPDFHERE?page=42")?.absoluteString == "zotero://open-pdf/library/items/NOPDFHERE?page=42")
        precondition(ZoteroPageOpener.resolve("zotero://select/library/items/D9QP9N8Q")?.absoluteString == "zotero://select/library/items/D9QP9N8Q")
        precondition(ZoteroPageOpener.resolve("https://example.com") == nil)
        // Preview vs print.
        let markdown = "Text.[^1]\n\n[^1]: [Lim](zotero://select/library/items/K), [42](zotero://open-pdf/library/items/P?page=42) and [web](https://x.org)."
        let printed = KasterTypesetter.rewriteZoteroLinks(markdown, links: false)
        precondition(printed == "Text.[^1]\n\n[^1]: Lim, 42 and [web](https://x.org).", printed)
        let previewed = KasterTypesetter.rewriteZoteroLinks(markdown, links: true)
        precondition(previewed.contains("[42](cardify-preview://url/") && !previewed.contains("](zotero://"), previewed)
        precondition(LibraryIndex.zoteroItems(in: markdown + " [x](zotero://select/groups/12/items/G)") == ["personal/K", "12/G"])

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
            for item in items { print("Live:", ZoteroFootnote.citation(ZoteroSource(key: item.key, cite: ZoteroCitation.markdown(fromHTML: item.citation ?? "")), page: "42")) }
            precondition(items.allSatisfy { $0.citation?.isEmpty == false }, "Zotero returned citations")
        }
        print("Zotero footnotes: numbering, citations, placement, clicks, preview and print passed")
        print("Zotero footnote sources, page edits, bibliography, page links, attachments and styles passed")
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

extension NSRange { var upperBoundLocation: Int { location + length } }
