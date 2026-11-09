import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Finder double-clicks, "Open With", and opentext:// URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in urls.forEach { AppModel.shared.handle($0) } }
    }
    /// Quit asks Save / Don't Save / Cancel for every document with unsaved changes (after flushing pending text autosaves).
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard DocumentSession.openSessions.contains(where: { $0.hasUnsavedChanges }) else { return .terminateNow }
        Task { @MainActor in
            var proceed = true
            for session in DocumentSession.openSessions {
                await session.flushAutosave()
                if !(await session.confirmClose()) { proceed = false; break }
            }
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    /// Menu bar app feel: closing the last window keeps the quick-create item alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
