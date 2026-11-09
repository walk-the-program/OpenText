import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Finder double-clicks, "Open With", and opentext:// URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in urls.forEach { AppModel.shared.handle($0) } }
    }
    /// Menu bar app feel: closing the last window keeps the quick-create item alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
