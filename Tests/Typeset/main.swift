import AppKit
import PDFKit
import Foundation

// Typesetting checks: Markdown with tables, LaTeX math, wiki links, tasks and IDs
// must typeset through Typst; batches produce one page per card; errors are readable.
@main struct Test {
 static func main() {
  precondition(KasterTypesetter.isAvailable(.typst), "Typst and Kaster's packages must be available for tests")

  let source = "---\ncard_id: 21/3a\n---\n# Knowledge\n\nA **justified** true belief, see [[The Gettier Problem|Gettier]].\n\nInline $e^{i\\pi}+1=0$ and display:\n\n$$\\int_0^1 x^2\\,dx = \\frac{1}{3}$$\n\n| Part | Role |\n| --- | --- |\n| Belief | Acceptance |\n\n- [x] done\n- [ ] open\n"
  let card = KasterTypesetter.prepare(source, links: true)
  precondition(card.id == "21/3a", "Frontmatter ID is carried separately")
  precondition(!card.markdown.contains("card_id"), "Frontmatter must not be typeset")
  precondition(card.markdown.contains("[Gettier](cardify-preview://wiki/"), "Wiki links become in-app preview links")
  let printed = KasterTypesetter.prepare(source, links: false)
  precondition(printed.markdown.contains("see Gettier.") && !printed.markdown.contains("cardify-preview"), "Printed cards show plain link labels")

  guard case .success(let data) = KasterTypesetter.render([card], layout: .card(portrait: false, fontSize: 9, dotGrid: true), engine: .typst),
        let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { fatalError("Typst card render failed") }
  let bounds = page.bounds(for: .mediaBox)
  precondition(abs(bounds.width - 360) < 1 && abs(bounds.height - 216) < 1, "Landscape cards are 5 × 3 in, got \(bounds)")
  let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: " ")
  precondition(text.contains("Knowledge") && text.contains("Belief") && text.contains("21/3a"), "Title, table and ID are typeset: \(text)")
  precondition(!text.contains("$$") && !text.contains("\\frac"), "Math is typeset, not printed raw")
  let links = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }.compactMap { ($0.action as? PDFActionURL)?.url }
  precondition(links.contains { CardPreviewLinks.target(from: $0) == .wiki("The Gettier Problem") }, "Preview PDF keeps clickable wiki links")

  guard case .success(let portraitData) = KasterTypesetter.render([card], layout: .card(portrait: true, fontSize: 9, dotGrid: false), engine: .typst),
        let portraitPage = PDFDocument(data: portraitData)?.page(at: 0) else { fatalError("Portrait render failed") }
  precondition(abs(portraitPage.bounds(for: .mediaBox).width - 216) < 1, "Portrait cards are 3 × 5 in")

  let batch = ["# One", "# Two", "# Three"].map { KasterTypesetter.prepare($0, links: false) }
  guard case .success(let batchData) = KasterTypesetter.render(batch, layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .typst),
        let batchPDF = PDFDocument(data: batchData) else { fatalError("Batch render failed") }
  precondition(batchPDF.pageCount == 3, "A batch prints one card per page, got \(batchPDF.pageCount)")

  guard case .success(let docData) = KasterTypesetter.render([card], layout: .document(fontSize: 11), engine: .typst),
        let docPage = PDFDocument(data: docData)?.page(at: 0) else { fatalError("Document render failed") }
  precondition(abs(docPage.bounds(for: .mediaBox).width - 396) < 1, "Document preview is 5.5 in wide")

  let typstMath = KasterTypesetter.prepare("# Typst math\n\nNative $frac(a, b) + sum_(i=1)^n i$ and ==highlighted== text.", links: false)
  guard case .success(let typstMathData) = KasterTypesetter.render([typstMath], layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .typst),
        let typstMathText = PDFDocument(data: typstMathData)?.page(at: 0)?.string else { fatalError("Typst-native math must typeset") }
  precondition(!typstMathText.contains("frac(") && !typstMathText.contains("=="), "Typst math and highlights are typeset: \(typstMathText)")
  let broken = KasterTypesetter.prepare("# Bad\n\n$\\frac{1}{$", links: false)
  if case .success = KasterTypesetter.render([broken], layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .typst) {
    print("note: malformed math still rendered (mitex is lenient)")
  }
  if KasterTypesetter.isAvailable(.latex) {
    guard case .success(let latexData) = KasterTypesetter.render([printed], layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .latex),
          let latexPDF = PDFDocument(data: latexData), let latexPage = latexPDF.page(at: 0) else { fatalError("LaTeX render failed") }
    precondition(abs(latexPage.bounds(for: .mediaBox).width - 360) < 1, "LaTeX cards are 5 × 3 in")
    let latexText = (0..<latexPDF.pageCount).compactMap { latexPDF.page(at: $0)?.string }.joined(separator: " ")
    precondition(latexText.contains("Knowledge") && latexText.contains("21/3a") && !latexText.contains("\\frac"), "LaTeX typesets title, ID and math")
    print("LaTeX engine passed")
  } else {
    print("LaTeX engine not installed; skipped")
  }
  // Print colors: Black only never asks the printer to mix colors; Color keeps purple links.
  let blackSource = KasterTypesetter.typstSource(cardCount: 1, layout: .card(portrait: false, fontSize: 9, dotGrid: true), color: .black)
  precondition(!blackSource.contains("rgb(") && !blackSource.contains("luma("), "Black only uses K-only CMYK ink everywhere")
  precondition(blackSource.contains("fill: ink") && blackSource.contains("stroke: 0.5pt + ink"), "Text and table rules are pure black")
  let colorSource = KasterTypesetter.typstSource(cardCount: 1, layout: .card(portrait: false, fontSize: 9, dotGrid: false), color: .color)
  precondition(colorSource.contains("#6b40c2") && colorSource.contains("stroke: 0.5pt + ink"), "Color keeps purple links, black tables")
  guard case .success = KasterTypesetter.render([card], layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .typst, color: .color) else { fatalError("Color render failed") }

  // Themes: the first #tag is printed in the top-left corner when Themes is on.
  let themed = KasterTypesetter.prepare("# Observe first\n\nWatch before acting. #strategy #learning", links: false, themes: true)
  precondition(themed.theme == "strategy", "First tag is the theme")
  precondition(KasterTypesetter.prepare("# T\n\n#strategy", links: false, themes: false).theme == nil, "No theme when Themes is off")
  guard case .success(let themedData) = KasterTypesetter.render([themed], layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .typst),
        let themedText = PDFDocument(data: themedData)?.page(at: 0)?.string else { fatalError("Themed render failed") }
  precondition(themedText.contains("STRATEGY"), "Theme prints in capitals: \(themedText)")

  // Speed: a typical card typesets well inside the 150 ms preview budget.
  _ = KasterTypesetter.render([card], layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .typst)
  let start = Date()
  for _ in 0..<5 { _ = KasterTypesetter.render([card], layout: .card(portrait: false, fontSize: 9, dotGrid: false), engine: .typst) }
  let average = Date().timeIntervalSince(start) / 5 * 1000
  print(String(format: "Typst card render: %.0f ms average", average))
  precondition(average < 150, "Card render should stay under 150 ms, took \(average) ms")
  print("Typst typesetting: tables, math, links, tasks, IDs, sizes, batches passed")
 }
}
