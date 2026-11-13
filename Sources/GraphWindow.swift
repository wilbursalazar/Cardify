import AppKit
import SwiftUI

// A separate window owned by the editor that opened it. Closing either window
// releases the callback and the graph's read-only snapshot.
final class GraphWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(currentURL: URL?, onOpen: @escaping (URL) -> Void) {
        let view = GraphView(currentURL: currentURL, onOpen: onOpen)
        let host = NSHostingController(rootView: view)
        if let window {
            window.contentViewController = host
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: host)
        window.title = "Cardify Graph"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.minSize = NSSize(width: 840, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) { window = nil }
}
