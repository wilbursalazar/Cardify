import AppKit
_ = NSApplication.shared
let text = "---\r\ncard_id: 1a\r\n---\r\n# Title\r\nBody\r\n"
let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
view.string = text
precondition(view.string == text, "Opening the editor must preserve CRLF bytes")
view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
view.insertText("x", replacementRange: view.selectedRange())
precondition(view.string == text + "x", "Editing must preserve existing CRLF bytes")
print("CRLF editor round-trip and editing passed")
