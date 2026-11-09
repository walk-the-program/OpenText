import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static weak var instance: AppDelegate?
    override init() { super.init(); Self.instance = self }

    /// AppKit delivers launch-time opens (files and URLs) before this runs, so the model knows by now whether
    /// launch was for files. The home window is shown here, by code, only when it was not.
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.finishLaunching()
        SelfTest.start()
    }

    /// Finder double-clicks, "Open With", and opentext:// URLs. The only entry point for external opens.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            AppModel.shared.noteExternalOpen()
            urls.forEach { AppModel.shared.handle($0) }
        }
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

    /// Dock icon click with nothing on screen brings the home window back. `flag` can't be trusted alone: the
    /// invisible bridge window counts as visible, so the model checks for real windows too.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || !AppModel.shared.hasUserWindow { AppModel.shared.showHome() }
        return true
    }

    /// Menu bar app feel: closing the last window keeps the quick-create item alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
