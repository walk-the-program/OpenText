import AppKit
import SwiftUI
import OpenTextAppLogic

/// Central app state: settings, hotkey, and routing of files / opentext:// URLs to windows.
/// Window opening is injected by `RouterBridge` (SwiftUI's openWindow is only available in views).
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: StandInSettings = .load()
    @Published var lastError: String?
    @Published var hotkeyValid = true

    private var openDocument: ((URL) -> Void)?
    private var openNamed: ((String) -> Void)?
    private var pending: [() -> Void] = []
    private var lastHandled: (url: URL, at: Date)?
    private var started = false

    // MARK: lifecycle

    /// Called by the first bridge view that appears. Never touches Keychain or system state.
    func start() {
        guard !started else { return }
        started = true
        HotkeyManager.shared.start { [weak self] in self?.showQuickCreate() }
        syncHotkeyFromFile()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadSettingsFromDisk() }
        }
        let flushed = pending
        pending = []
        flushed.forEach { $0() }
        if !UserDefaults.standard.bool(forKey: "setupShown") && flushed.isEmpty {
            UserDefaults.standard.set(true, forKey: "setupShown")
            showSetup()
        }
    }

    func attach(openDocument: @escaping (URL) -> Void, openNamed: @escaping (String) -> Void) {
        self.openDocument = openDocument
        self.openNamed = openNamed
        start()
    }

    private func whenReady(_ work: @escaping () -> Void) {
        if openDocument == nil { pending.append(work) } else { work() }
    }

    // MARK: settings

    func update(_ change: (inout StandInSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        let hotkeyChanged = s.hotkey != settings.hotkey
        settings = s
        do { try s.save() } catch { lastError = "Could not save settings: \(error.localizedDescription)" }
        if hotkeyChanged { hotkeyValid = HotkeyManager.shared.apply(s.hotkey) }
    }

    /// Called by the shortcut recorder after the user picks a new shortcut: mirror into settings.json.
    func shortcutRecorded() {
        guard let str = HotkeyManager.shared.currentString else { return }
        hotkeyValid = true
        if str != settings.hotkey { update { $0.hotkey = str } }
    }

    /// File wins when it differs from what KeyboardShortcuts stored (hand/AI edits).
    private func syncHotkeyFromFile() {
        if settings.hotkey != HotkeyManager.shared.currentString {
            hotkeyValid = HotkeyManager.shared.apply(settings.hotkey)
        }
    }

    private func reloadSettingsFromDisk() {
        let s = StandInSettings.load()
        guard s != settings else { return }
        settings = s
        syncHotkeyFromFile()
    }

    // MARK: windows

    func showQuickCreate() { whenReady { [self] in NSApp.activate(); openNamed?("quick-create") } }
    func showSetup() { whenReady { [self] in NSApp.activate(); openNamed?("setup") } }

    func openFile(_ url: URL) {
        guard FileRouting.kind(for: url) != .unsupported else { NSSound.beep(); return }
        whenReady { [self] in NSApp.activate(); openDocument?(url) }
    }

    // MARK: URL / file entry point

    /// Handles file URLs and opentext:// URLs from application(_:open:) and .onOpenURL.
    func handle(_ url: URL) {
        if let last = lastHandled, last.url == url, Date().timeIntervalSince(last.at) < 1 { return }
        lastHandled = (url, Date())
        if url.isFileURL { openFile(url); return }
        do {
            switch try URLRouter.parse(url) {
            case .new(let format, let dir): createNew(format: format, in: dir)
            case .convert(let to, let file): convert(file, to: to)
            case .lock(let file): openFile(file); requestLock(file)
            }
        } catch {
            lastError = "Ignored \(url.absoluteString): \(error)"
        }
    }

    func createNew(format: String, in dir: URL? = nil) {
        do {
            let url = try EngineAdapter.newFile(format: format, in: dir ?? settings.defaultFolderURL)
            update { $0.lastNewFileFormat = format }
            openFile(url)
        } catch { lastError = "Could not create the file: \(error.localizedDescription)" }
    }

    func convert(_ file: URL, to format: String) {
        do { _ = try EngineAdapter.convert(file, to: format) }
        catch { lastError = error.localizedDescription }
    }

    /// Finder "Lock" lands here; the document window shows the lock sheet for this URL.
    @Published var lockRequest: URL?
    func requestLock(_ file: URL) { lockRequest = file }
}
