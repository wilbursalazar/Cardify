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
  preview.layoutSubtreeIfNeeded()
  func key(_ value: String, _ path: String = "/vault/A.md") -> PDFPreviewRevision {
   PDFPreviewRevision(mode: "markdown", content: value, portrait: false, fontSize: 9, dotGrid: false, filePath: path)
  }
  func document(_ text: String) -> Data {
   CardDocument(text: text, portrait: false, fontSize: 9).pdf(includeLinks: true)!
  }
  // Draw the actual preview page into a bitmap, without PDFKit's tiled PDFView.
  // This verifies rendered ink and page contents, not an on-screen animation.
  func renderedPage(_ index: Int) -> (bytes: Data, dark: Int, white: Int) {
   let view = preview.pagesView, rect = view.pageRects[index]
   let width = Int(ceil(rect.width)), height = Int(ceil(rect.height))
   let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
   let context = NSGraphicsContext(bitmapImageRep: bitmap)!
   NSGraphicsContext.saveGraphicsState()
   NSGraphicsContext.current = context
   context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
   view.draw(rect)
   context.flushGraphics()
   NSGraphicsContext.restoreGraphicsState()
   let bytes = Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * height)
   var dark = 0, white = 0
   bytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
    let pixels = buffer.bindMemory(to: UInt8.self)
    for y in 0..<height { for x in 0..<width {
     let p = y * bitmap.bytesPerRow + x * 4
     let r = pixels[p], g = pixels[p + 1], b = pixels[p + 2]
     if r < 100 && g < 100 && b < 100 { dark += 1 }
     if r > 245 && g > 245 && b > 245 { white += 1 }
    } }
   }
   return (bytes, dark, white)
  }
  func checkRendered(_ index: Int) -> Data {
   let image = renderedPage(index)
   precondition(image.white > 10000 && image.dark > 20, "page must contain white paper and visible text, not a blank frame: \(image.white) white, \(image.dark) dark")
   return image.bytes
  }
  let initial = "# First card\n\nResearch with a [[Linked Note]] and a sentence."
  let firstKey = key(initial)
  let firstData = document(initial)
  preview.update(data: firstData, revision: firstKey)
  precondition(preview.pagesView.document?.page(at: 0)?.string?.contains("First card") == true)
  let firstPixels = checkRendered(0)
  func assertFits(_ label: String) {
   let size = preview.scrollView.contentSize, rect = preview.pagesView.pageRects[0]
   precondition(rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= size.width && rect.maxY <= size.height, "\(label) single card must fit the preview viewport")
  }
  assertFits("Landscape")
  let portraitText = "# Portrait card\n\nSome research."
  let portraitKey = PDFPreviewRevision(mode: "markdown", content: portraitText, portrait: true, fontSize: 9, dotGrid: false, filePath: "/vault/A.md")
  let portraitPDF = CardDocument(text: portraitText, portrait: true, fontSize: 9).pdf(includeLinks: true)!
  preview.update(data: portraitPDF, revision: portraitKey)
  precondition(preview.pagesView.document?.pageCount == 1)
  assertFits("Portrait")
  _ = checkRendered(0)
  preview.update(data: firstData, revision: firstKey)
  preview.update(data: document("# Ignored"), revision: firstKey)
  precondition(preview.pagesView.document?.page(at: 0)?.string?.contains("First card") == true, "same revision is not replaced")
  precondition(checkRendered(0) == firstPixels)
  let page = preview.pagesView.document!.page(at: 0)!
  let annotation = page.annotations.first { $0.action is PDFActionURL }!
  let card = preview.pagesView.pageRects[0], bounds = page.bounds(for: .mediaBox), a = annotation.bounds
  let location = NSPoint(x: card.minX + (a.midX - bounds.minX) * card.width / bounds.width,
                         y: card.maxY - (a.midY - bounds.minY) * card.height / bounds.height)
  precondition(preview.pagesView.link(at: location) == .wiki("Linked Note"), "link hit must resolve on the displayed card")
  var followed: [CardLinkTarget] = []
  preview.setLinkHandler { followed.append($0) }
  func click(_ point: NSPoint) {
   let inWindow = preview.pagesView.convert(point, to: nil)
   let down = NSEvent.mouseEvent(with: .leftMouseDown, location: inWindow, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
   let up = NSEvent.mouseEvent(with: .leftMouseUp, location: inWindow, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
   preview.pagesView.mouseDown(with: down); preview.pagesView.mouseUp(with: up)
  }
  click(location)
  precondition(followed == [.wiki("Linked Note")], "click invokes the link handler")
  preview.update(data: nil, revision: key("unavailable"))
  precondition(preview.pagesView.document?.page(at: 0)?.string?.contains("First card") == true, "unavailable update retains last card")
  precondition(preview.pagesView.link(at: location) == nil, "links on an unavailable card must not be followed")
  click(location)
  precondition(followed == [.wiki("Linked Note")], "unavailable card must not invoke link handler")
  precondition(checkRendered(0) == firstPixels, "unavailable update must not blank the preview")
  preview.update(data: firstData, revision: firstKey)
  precondition(preview.pagesView.link(at: location) == .wiki("Linked Note"))
  _ = window.makeFirstResponder(editor)
  let editorHadFocus = window.firstResponder === editor
  var previousPixels = firstPixels
  for index in 0..<12 {
   let next = "# Edit \(index)\n\nUpdated research text number \(index), with [[Linked Note]]."
   preview.update(data: document(next), revision: key(next))
   precondition(preview.pagesView.document?.page(at: 0)?.string?.contains("Edit \(index)") == true, "latest edit must be rendered immediately")
   let pixels = checkRendered(0)
   precondition(pixels != previousPixels, "rendered text must change after each edit")
   previousPixels = pixels
   if editorHadFocus { precondition(window.firstResponder === editor, "preview update must not steal editor focus") }
  }
  let paragraphs = (0..<120).map { "Paragraph \($0) with research text and extra words." }.joined(separator: "\n\n")
  let longA = "# Long card\n\n" + paragraphs
  preview.update(data: document(longA), revision: key(longA, "/vault/long.md"))
  precondition(preview.pagesView.pageRects.count > 3, "long note should have multiple preview cards")
  _ = checkRendered(0); _ = checkRendered(3)
  let clip = preview.scrollView.contentView
  clip.scroll(to: NSPoint(x: 0, y: preview.pagesView.pageRects[3].minY))
  preview.scrollView.reflectScrolledClipView(clip)
  let oldY = clip.bounds.origin.y
  precondition(oldY > 0, "test must scroll to a later card")
  let longB = "# Edited card\n\n" + paragraphs
  preview.update(data: document(longB), revision: key(longB, "/vault/long.md"))
  precondition(abs(clip.bounds.origin.y - oldY) < 2, "updating the same card preserves scroll position")
  _ = checkRendered(3)
  preview.update(data: document("# Different note"), revision: key("Different note", "/vault/other.md"))
  precondition(clip.bounds.origin.y < 2, "changing files resets scroll")
  _ = checkRendered(0)
  let unzoomedWidth = preview.pagesView.pageRects[0].width
  let wheel = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                      wheelCount: 1, wheel1: 2, wheel2: 0, wheel3: 0)!)!
  preview.scrollView.scrollWheel(with: wheel)
  precondition(preview.pagesView.pageRects[0].width > unzoomedWidth, "wheel zooms the on-screen page")
  preview.update(data: document("# Another note"), revision: key("Another note", "/vault/another.md"))
  precondition(abs(preview.pagesView.pageRects[0].width - unzoomedWidth) < 2, "changing cards resets preview zoom")
  preview.cancelPending(); window.close()
  print("Synchronous preview pixel rendering, rapid edits, links, focus, multipage scrolling and wheel zoom passed")
 }
}
