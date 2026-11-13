import AppKit
import Combine
import SwiftUI

@main struct EditorWindowsTests {
@MainActor static func main() {
_ = NSApplication.shared
let coordinator = EditorWindowCoordinator.shared
let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
let second = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
first.isReleasedWhenClosed = false
second.isReleasedWhenClosed = false

precondition(coordinator.claim(first), "The first editor must be admitted")
precondition(coordinator.claim(first), "Repeated attachment of the same editor must be safe")
precondition(!coordinator.claim(second), "A second editor must never be admitted")
precondition(coordinator.window === first, "A second editor must not replace the first")

// A clip can arrive before the editor view exists. A later subscriber must receive it.
let clip = URL(string: "cardifyresearch://clip?title=example")!
coordinator.pendingURL = clip
var received: URL?
let subscription = coordinator.$pendingURL.sink { received = $0 }
precondition(received == clip, "A clip received before mounting must be retained")
coordinator.pendingURL = nil
precondition(received == nil, "A consumed clip must be cleared")

first.close()
precondition(coordinator.window == nil, "Closing the editor must release the claim")
subscription.cancel()
let reopenedClip = URL(string: "cardifyresearch://clip?title=reopened")!
coordinator.pendingURL = reopenedClip
precondition(coordinator.claim(second), "A new editor must be allowed after closing")
var reopenedReceived: URL?
let reopenedSubscription = coordinator.$pendingURL.sink { reopenedReceived = $0 }
precondition(reopenedReceived == reopenedClip, "A clip received while the editor is closed must survive reopening")
second.close()
precondition(coordinator.window == nil, "The reopened editor must also release its claim")
withExtendedLifetime(reopenedSubscription) {}
print("Editor window lifecycle and clip buffering passed")
}
}
