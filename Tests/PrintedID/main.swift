import AppKit
import PDFKit
import Foundation

@main struct Test {
 static func main() {
  let indexText = "---\ncardify_index: true\n---\n# Memory Index\n\nA useful starting point."
  guard let indexData = CardDocument(text: indexText, portrait: false, fontSize: 9).pdf(),
        let indexOutput = PDFDocument(data: indexData)?.page(at: 0)?.string else { fatalError("Index card PDF missing") }
  precondition(indexOutput.contains("Memory Index") && !indexOutput.contains("cardify_index"), "Index metadata must not print")
  let prose = "---\nOrdinary prose survives\n---\nMore content"
  guard let proseData = CardDocument(text: prose, portrait: false, fontSize: 9).pdf(),
        let proseOutput = PDFDocument(data: proseData)?.page(at: 0)?.string else { fatalError("Prose PDF missing") }
  precondition(proseOutput.contains("Ordinary prose survives"), "Markdown between horizontal rules must not disappear")
  for debateID in ["AFF-01", "DEF-01", "AFF-01-OB-01", "AFF-01-OB-01-RE-01"] {
   for portrait in [false, true] {
    let draft = CardMetadata.frontmatter(debateID) + "# A major debate point\n\nSupporting argument."
    guard let data = CardDocument(text: draft, portrait: portrait, fontSize: 9).pdf(),
          let page = PDFDocument(data: data)?.page(at: 0), let text = page.string else { fatalError("Debate ID PDF missing") }
    let range = (text as NSString).range(of: debateID)
    guard range.location != NSNotFound, let selection = page.selection(for: range) else { fatalError("Debate ID missing") }
    let bounds = selection.bounds(for: page), paper = page.bounds(for: .mediaBox)
    precondition(bounds.midX > paper.midX && bounds.midY > paper.midY, "Debate ID must appear in the upper right")
   }
  }
  let id = "IDCHECK987"
  for portrait in [false,true] {
   for size in [7.0, 9.0, 14.0, 18.0] {
    for long in [false,true] {
     let title = long ? "FIRST A long heading with many words designed to wrap safely before it approaches the printed identifier ENDTITLE" : "FIRST"
     let paragraphs = (0..<100).map { "Line\(String(format: "%03d",$0)) useful research material." }.joined(separator:"\n\n")
     let input = CardMetadata.frontmatter(id) + "# \(title)\n\n" + paragraphs
     guard let data = CardDocument(text:input,portrait:portrait,fontSize:size).pdf(), let pdf=PDFDocument(data:data) else { fatalError("PDF missing \(portrait) \(size)") }
     var all = ""
     for pageNumber in 0..<pdf.pageCount {
      guard let page=pdf.page(at:pageNumber), let s=page.string else { fatalError("page missing") }
      let ns = s as NSString
      let idRange = ns.range(of:id)
      guard idRange.location != NSNotFound, let idSelection = page.selection(for:idRange) else { fatalError("ID missing on page \(pageNumber): \(s)") }
      let idBounds = idSelection.bounds(for:page).insetBy(dx:0.2,dy:0.2)
      let safe=page.bounds(for:.mediaBox).insetBy(dx:27,dy:27).insetBy(dx:-1,dy:-1)
      for i in 0..<ns.length where !NSLocationInRange(i,idRange) {
       let c = ns.substring(with:NSRange(location:i,length:1))
       if c.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { continue }
       guard let charSelection=page.selection(for:NSRange(location:i,length:1)) else { continue }
       let rect=charSelection.bounds(for:page)
       if !rect.isNull && rect.width > 0 && rect.height > 0 {
        if rect.intersects(idBounds) { fatalError("ID overlap p\(pageNumber) \(portrait) \(size) \(c) \(rect) vs \(idBounds)") }
        if !safe.contains(rect) { fatalError("Out of safe bounds p\(pageNumber) \(portrait) \(size) \(c) \(rect)") }
       }
      }
      if pageNumber == 0 {
       let range=ns.range(of:"FIRST")
       guard range.location != NSNotFound,let sel=page.selection(for:range) else { fatalError("title missing") }
       let titleBounds=sel.bounds(for:page)
       if titleBounds.minY > idBounds.maxY || titleBounds.maxY < idBounds.minY { fatalError("title and ID do not share a row: \(portrait) \(size) title \(titleBounds) id \(idBounds)") }
      }
      all += s + "\n"
     }
     for i in 0..<100 {
      let compact=all.replacingOccurrences(of:"\\s+",with:"",options:.regularExpression)
      let label="Line\(String(format:"%03d",i))"
      if !compact.contains(label) { fatalError("Lost \(label) \(portrait) \(size) \(long)") }
     }
     if long && !all.replacingOccurrences(of:"\\s+",with:"",options:.regularExpression).contains("ENDTITLE") { fatalError("Lost heading") }
     let pairInput=CardMetadata.frontmatter(id) + "# FIRST\nSECONDLINE"
     guard let pairData=CardDocument(text:pairInput,portrait:portrait,fontSize:size).pdf(), let pairPage=PDFDocument(data:pairData)?.page(at:0), let pairText=pairPage.string else { fatalError("pair missing") }
     let pair=pairText as NSString
     let firstRange=pair.range(of:"FIRST"), secondRange=pair.range(of:"SECONDLINE")
     guard firstRange.location != NSNotFound, secondRange.location != NSNotFound, let first=pairPage.selection(for:firstRange), let second=pairPage.selection(for:secondRange) else { fatalError("pair text missing") }
     if first.bounds(for:pairPage).intersects(second.bounds(for:pairPage)) { fatalError("first and second lines overlap") }
     print("\(portrait ? "portrait" : "landscape") \(Int(size)) \(long ? "long" : "short"): \(pdf.pageCount) pages clear")
    }
   }
  let longID=String(repeating:"M",count:32)
  let data=CardDocument(text:CardMetadata.frontmatter(longID)+"# FIRST\n\nTEXT",portrait:true,fontSize:18).pdf()!
  let pg=PDFDocument(data:data)!.page(at:0)!, str=pg.string! as NSString
  let ir=str.range(of:longID), tr=str.range(of:"FIRST")
  guard ir.location != NSNotFound, tr.location != NSNotFound, let idSel=pg.selection(for:ir),let titleSel=pg.selection(for:tr) else { fatalError("extreme ID or title missing") }
  if idSel.bounds(for:pg).intersects(titleSel.bounds(for:pg)) { fatalError("extreme ID overlap") }
  print("Long ID fallback is legible and avoids overlap")
  }
 }
}
