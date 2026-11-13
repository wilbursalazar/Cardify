import AppKit
import Foundation
import PDFKit

@main struct Check {
 static func main() {
  let lines = (0..<90).map { index in
   "- Row \(index) 😀 [[Folder/Note\(index)#Heading|idea \(index)]] and [source \(index)](https://example.test/item/\(index))"
  }.joined(separator: "\n\n")
  let lf = "# Café 😀\n\n" + lines + "\n"
  let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
  let left = MarkdownRendering.render(lf, fontSize: 9), right = MarkdownRendering.render(crlf, fontSize: 9)
  precondition(left.string == right.string, "CRLF added whitespace or changed rendered text")
  func linkRuns(_ value: NSAttributedString) -> [String] {
   var result: [String] = []
   value.enumerateAttribute(CardPreviewLinks.attribute, in: NSRange(location: 0, length: value.length)) { target, range, _ in
    if let target = target as? String { result.append("\(range.location):\(range.length):\(target)") }
   }
   return result
  }
  let a = linkRuns(left), b = linkRuns(right)
  precondition(a.count == 180 && a == b, "CRLF shifted or lost a link's UTF-16 range")
  for portrait in [false, true] {
   let lCard = CardDocument(text: lf, portrait: portrait, fontSize: 9)
   let rCard = CardDocument(text: crlf, portrait: portrait, fontSize: 9)
   guard let lData = lCard.pdf(includeLinks: true), let rData = rCard.pdf(includeLinks: true),
         let lPDF = PDFDocument(data: lData), let rPDF = PDFDocument(data: rData) else { fatalError("Could not generate PDFs") }
   precondition(lPDF.pageCount > 1 && lPDF.pageCount == rPDF.pageCount, "CRLF changed pagination")
   for number in 0..<lPDF.pageCount {
    guard let lPage = lPDF.page(at: number), let rPage = rPDF.page(at: number) else { fatalError("Missing PDF page") }
    precondition(lPage.string == rPage.string, "CRLF changed card text on page \(number)")
    let expectedSize = portrait ? CGSize(width: 216, height: 360) : CGSize(width: 360, height: 216)
    precondition(lPage.bounds(for: .mediaBox).size == expectedSize && rPage.bounds(for: .mediaBox).size == expectedSize, "Card dimensions changed")
    let lLinks = lPage.annotations, rLinks = rPage.annotations
    precondition(lLinks.count == rLinks.count, "CRLF lost link annotations on page \(number)")
    for (a, b) in zip(lLinks, rLinks) {
     guard let aURL = (a.action as? PDFActionURL)?.url, let bURL = (b.action as? PDFActionURL)?.url else { fatalError("Invalid preview link") }
     precondition(CardPreviewLinks.target(from: aURL) == CardPreviewLinks.target(from: bURL), "CRLF changed a link target")
     precondition(abs(a.bounds.minX - b.bounds.minX) < 0.01 && abs(a.bounds.minY - b.bounds.minY) < 0.01 && abs(a.bounds.width - b.bounds.width) < 0.01 && abs(a.bounds.height - b.bounds.height) < 0.01, "CRLF shifted a link rectangle")
    }
   }
   print("\(portrait ? "portrait" : "landscape"): matching \(lPDF.pageCount)-card LF/CRLF text and link geometry")
  }
  for role in ["project", "aff", "def", "evidence", "objection", "argument", "reply"] {
   for ending in ["\n", "\r\n"] {
    let draft = ["<!-- cardify:debate=\(role) -->", "# Debate point", "", "Primary parent: [[Research/Parent]] — supports the argument"].joined(separator: ending)
    guard let data = CardDocument(text: draft, portrait: false, fontSize: 9).pdf(includeLinks: true),
          let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { fatalError("Could not create debate card") }
    let output = page.string ?? ""
    precondition(!output.contains("cardify:debate") && output.contains("Debate point") && output.contains("Primary parent"), "Debate marker must be hidden while the note remains readable on paper")
    precondition(page.annotations.contains { annotation in
     guard let url = (annotation.action as? PDFActionURL)?.url else { return false }
     return CardPreviewLinks.target(from: url) == .wiki("Research/Parent")
    }, "Debate relation must remain clickable in preview")
   }
  }
  let bomMarker = "\u{FEFF}<!-- cardify:debate=aff -->\r\n# Debate point"
  precondition(!MarkdownRendering.render(bomMarker, fontSize: 9).string.contains("cardify:debate"), "A BOM must not expose a debate marker")
  let commentMarker = "<!-- example\n<!-- cardify:debate=aff -->\n-->"
  precondition(MarkdownRendering.render(commentMarker, fontSize: 9).string.contains("cardify:debate=aff"), "A marker inside another comment is not debate metadata")
  let quotedMarker = "```\n<!-- cardify:debate=aff -->\n```"
  precondition(MarkdownRendering.render(quotedMarker, fontSize: 9).string.contains("cardify:debate=aff"), "A literal marker in a code fence must not be hidden")
  print("Debate role markers stay off printed cards and links remain clickable")
 }
}
