import AppKit
import Foundation
import PDFKit

@main struct Check {
 static func main() {
  _ = NSApplication.shared
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
  let content = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 540))
  let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 500))
  let preview = StablePDFPreviewView(frame: NSRect(x: 100, y: 0, width: 600, height: 500))
  content.addSubview(editor); content.addSubview(preview); window.contentView = content
  content.layoutSubtreeIfNeeded()
  func key(_ value: String, _ path: String = "/vault/A.md") -> PDFPreviewRevision {
   PDFPreviewRevision(mode: "markdown", content: value, portrait: false, fontSize: 9, dotGrid: false, filePath: path)
  }
  func document(_ text: String) -> Data {
   let linked = (0..<5).map { "Paragraph \($0) includes a [[Linked Note]] for research." }.joined(separator: "\n\n")
   return CardDocument(text: text + "\n\n" + linked, portrait: false, fontSize: 9).pdf(includeLinks: true)!
  }
  func currentText() -> String { preview.visiblePDFView.document?.page(at: 0)?.string ?? "" }
  func tick() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.18)) }
  let a = document("# A old"), b = document("# B new"), c = document("# C other")
  let ka = key("A"), kb = key("B"), kc = key("C", "/vault/C.md")
  var followed: [CardLinkTarget] = []
  let descriptor = PDFPreview(data: a, revision: ka, onFollowLink: { followed.append($0) })
  let coordinator = descriptor.makeCoordinator(); coordinator.container = preview; preview.setDelegate(coordinator)
  let action = CardPreviewLinks.action(for: .wiki("Target"))!
  preview.update(data: a, revision: ka)
  let first = preview.visiblePDFView
  precondition(currentText().contains("A old") && preview.canFollowLinks(from: first), "first card appears immediately")
  precondition(preview.subviews.compactMap { $0 as? PDFView }.count == 1, "only one PDFView is active")
  preview.update(data: b, revision: ka)
  precondition(preview.visiblePDFView === first && currentText().contains("A old"), "same revision must not replace PDF even with different bytes")
  preview.update(data: b, revision: kb)
  precondition(preview.visiblePDFView === first && currentText().contains("A old") && !preview.canFollowLinks(from: first), "previous card stays visible while stale links are blocked")
  coordinator.pdfViewWillClick(onLink: first, with: action)
  precondition(followed.isEmpty, "stale preview action must be ignored")
  preview.update(data: a, revision: ka); tick()
  precondition(preview.visiblePDFView === first && preview.canFollowLinks(from: first), "A to B to A cancels pending B")
  preview.update(data: b, revision: kb); preview.update(data: nil, revision: kb); tick()
  precondition(preview.visiblePDFView === first && !preview.canFollowLinks(from: first), "nil cancels pending PDF and disables stale actions")
  preview.update(data: a, revision: ka)
  coordinator.pdfViewWillClick(onLink: first, with: action)
  precondition(followed == [.wiki("Target")], "current preview action dispatched")
  preview.update(data: b, revision: kb); preview.update(data: c, revision: kc); tick()
  precondition(currentText().contains("C other") && preview.canFollowLinks(from: preview.visiblePDFView), "different file cancels old pending update")
  let many = (0..<120).map { "Paragraph \($0) with research text and extra words." }.joined(separator: "\n\n")
  let longA = document("# Long card\n\n" + many), longB = document("# Long card edited\n\n" + many)
  let longKeyA = key("long-a", "/vault/long.md"), longKeyB = key("long-b", "/vault/long.md")
  preview.update(data: longA, revision: longKeyA)
  let oldView = preview.visiblePDFView
  oldView.autoScales = false; oldView.scaleFactor = 1.2
  oldView.layoutSubtreeIfNeeded()
  let page = oldView.document!.page(at: 3)!
  oldView.go(to: page)
  oldView.layoutSubtreeIfNeeded()
  guard let oldScroll = oldView.documentView?.enclosingScrollView else { fatalError("no PDF scroll view") }
  let oldOrigin = oldScroll.contentView.bounds.origin
  _ = window.makeFirstResponder(editor)
  let editorHadFocus = window.firstResponder === editor
  preview.update(data: longB, revision: longKeyB); tick()
  let newView = preview.visiblePDFView
  guard let newScroll = newView.documentView?.enclosingScrollView else { fatalError("no new PDF scroll view") }
  let newOrigin = newScroll.contentView.bounds.origin
  precondition(abs(newView.scaleFactor - 1.2) < 0.01 && !newView.autoScales, "manual zoom preserved")
  precondition(abs(newOrigin.y - oldOrigin.y) < 2, "vertical scroll preserved: \(oldOrigin) vs \(newOrigin)")
  if editorHadFocus { precondition(window.firstResponder === editor, "updating preview must not steal editor focus") }
  precondition(preview.subviews.compactMap { $0 as? PDFView }.count == 1 && oldView === newView, "updates reuse one PDFView")
  coordinator.pdfViewWillClick(onLink: PDFView(frame: .zero), with: action)
  precondition(followed == [.wiki("Target")], "other PDF views cannot dispatch actions")
  coordinator.pdfViewWillClick(onLink: newView, with: action)
  precondition(followed == [.wiki("Target"), .wiki("Target")], "new preview dispatches actions")
  for index in 0..<8 {
   let nextText = "# Swap \(index)"
   preview.update(data: document(nextText), revision: key(nextText, "/vault/long.md")); tick()
   precondition(currentText().contains("Swap \(index)"), "repeated update must show latest content")
  }
  preview.cancelPending(); window.close()
  print("Preview latest-wins, single-view snapshot, stale-link guard, scroll and zoom checks passed")
 }
}
