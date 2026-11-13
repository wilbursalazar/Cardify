import Foundation
import AppKit
import PDFKit

@main struct Check {
 static func main() {
  var followed: [CardLinkTarget] = []
  let previewView = PDFPreview(data: nil, onFollowLink: { followed.append($0) })
  let coordinator = previewView.makeCoordinator()
  precondition(coordinator.responds(to: NSSelectorFromString("PDFViewWillClickOnLink:withURL:")), "PDFKit delegate selector is unavailable")
  let sender = PDFView(frame: .zero)
  coordinator.pdfViewWillClick(onLink: sender, with: CardPreviewLinks.action(for: .wiki("Books/Note|label"))!)
  coordinator.pdfViewWillClick(onLink: sender, with: CardPreviewLinks.action(for: .url("https://example.org"))!)
  coordinator.pdfViewWillClick(onLink: sender, with: URL(string: "https://example.org/not-an-internal-action")!)
  precondition(followed == [.wiki("Books/Note|label"), .url("https://example.org")], "preview callback dispatch failed")
  let longLabel = (0..<250).map { "Segment\($0)" }.joined(separator: " ")
  let source = CardMetadata.frontmatter("1a") + "# [[first|Identical]] [Identical](https://second.example/path)\n\nSource: https://clip.example/article\n\n**[[styled|bold target]]**\n\n[\(longLabel)](https://long.example/target)\n\n`[[not-a-link]]`\n```\n[hidden](https://hidden.example)\n```"
  for portrait in [false, true] {
   let card = CardDocument(text: source, portrait: portrait, fontSize: 12)
   guard let plainData = card.pdf(), let previewData = card.pdf(includeLinks: true), let plain = PDFDocument(data: plainData), let preview = PDFDocument(data: previewData) else { fatalError("missing PDF") }
   precondition(plain.pageCount == preview.pageCount && preview.pageCount > 1)
   var targets: [CardLinkTarget] = []
   var longPages = Set<Int>()
   for p in 0..<preview.pageCount {
    let page = preview.page(at: p)!, original = plain.page(at: p)!
    precondition(original.annotations.isEmpty, "print PDF gained annotations")
    precondition(original.string == page.string, "preview changed printed text on page \(p)")
    let safe = page.bounds(for: .mediaBox).insetBy(dx: 26, dy: 26)
    for annotation in page.annotations {
     guard let action = annotation.action as? PDFActionURL, let url = action.url, let target = CardPreviewLinks.target(from: url) else { fatalError("invalid action") }
     precondition(safe.contains(annotation.bounds), "annotation out of bounds: \(annotation.bounds)")
     targets.append(target)
     if target == .url("https://long.example/target") { longPages.insert(p) }
    }
   }
   precondition(targets.contains(.wiki("first|Identical")))
   precondition(targets.contains(.url("https://second.example/path")))
   precondition(targets.contains(.url("https://clip.example/article")))
   precondition(targets.contains(.wiki("styled|bold target")))
   precondition(longPages.count > 1, "wrapped link not annotated on multiple cards")
   precondition(!targets.contains(.wiki("not-a-link")) && !targets.contains(.url("https://hidden.example")))
   let page = preview.page(at: 0)!, text = page.string! as NSString
   let first = text.range(of: "Identical")
   let second = text.range(of: "Identical", options: [], range: NSRange(location: NSMaxRange(first), length: text.length - NSMaxRange(first)))
   guard let firstSel = page.selection(for: first), let secondSel = page.selection(for: second) else { fatalError("duplicate labels missing") }
   func annotationTargets(_ rect: CGRect) -> [CardLinkTarget] { page.annotations.compactMap { a in
    guard a.bounds.intersects(rect), let url = (a.action as? PDFActionURL)?.url else { return nil }; return CardPreviewLinks.target(from: url)
   } }
   let firstTargets = annotationTargets(firstSel.bounds(for: page)), secondTargets = annotationTargets(secondSel.bounds(for: page))
   precondition(firstTargets.contains(.wiki("first|Identical")) && !firstTargets.contains(.url("https://second.example/path")), "wrong first link rectangle")
   precondition(secondTargets.contains(.url("https://second.example/path")) && !secondTargets.contains(.wiki("first|Identical")), "wrong second link rectangle")
   print("\(portrait ? "portrait" : "landscape"): \(preview.pageCount) cards; exact link targets and bounds, wrapped links, raw URL, code exclusion; print PDF unannotated")
  }
 }
}
