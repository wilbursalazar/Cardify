@testable import KasterApp
import AppKit

// Live editor: footnote markers become small raised numbers and link addresses hide,
// except on the line holding the cursor.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let view = LinkCompletionTextView(frame: NSRect(x: 0, y: 0, width: 450, height: 800))
view.isRichText = false
view.textContainer?.containerSize = NSSize(width: 450, height: 2000)
let text = "# Canon\n\nThe canon closed early.[^1] More.\n\n[^1]: [Lim, *Title*](zotero://select/library/items/K), [42](zotero://open-pdf/library/items/P?page=42).\nEnd"
view.string = text
view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))   // cursor on the last line
view.applyKasterStyle(live: true)
let ns = text as NSString
func font(_ needle: String, offset: Int = 0) -> NSFont {
    let at = ns.range(of: needle).location + offset
    return view.textStorage!.attribute(.font, at: at, effectiveRange: nil) as! NSFont
}
func hidden(_ needle: String, offset: Int = 0) -> Bool { font(needle, offset: offset).pointSize < 1 }
let markerAt = ns.range(of: "early.[^1]").location + "early.".count
precondition(view.textStorage!.attribute(.font, at: markerAt, effectiveRange: nil).map { ($0 as! NSFont).pointSize < 1 } == true, "[^ hidden away from the cursor")
let labelAt = markerAt + 2
precondition((view.textStorage!.attribute(.baselineOffset, at: labelAt, effectiveRange: nil) as? CGFloat ?? 0) > 0, "the footnote number is raised")
precondition(hidden("](zotero://select"), "a link address is hidden away from the cursor")
precondition(!hidden("Lim, *Title*", offset: 1), "the link label stays visible")
precondition(!hidden("[^1]: ", offset: 0), "footnote definitions keep their label")
// Cursor on the definition line: its link addresses show.
view.setSelectedRange(NSRange(location: ns.range(of: "[42]").location, length: 0))
view.updateMarkerVisibility()
precondition(!hidden("](zotero://select"), "addresses show on the cursor's line")
print("Live editor: raised footnote numbers and hidden link addresses passed")
