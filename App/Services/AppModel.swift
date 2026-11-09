import AppKit
import SwiftUI
import OpenTextKit
import OpenTextUI
import OpenTextAppLogic

extension OpenTextSettings {
    func same(as o: OpenTextSettings) -> Bool {
        defaultFolder == o.defaultFolder && hotkey == o.hotkey && recoveryPublicKey == o.recoveryPublicKey
            && useTouchID == o.useTouchID && txtMonospace == o.txtMonospace && lastNewFileFormat == o.lastNewFileFormat
            && setupShown == o.setupShown
    }
}

/// A message shown in the small "notice" window (result of a Finder-initiated action, or an error).
struct Notice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var revealURL: URL?
}

/// Central app state: settings, hotkey, and routing of files / opentext:// URLs to windows.
/// Window opening is injected by `RouterBridge` (SwiftUI's openWindow is only available in views).
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: OpenTextSettings = .load()
    @Published var notice: Notice?
    @Published var hotkeyValid = true
    /// Finder "Lock" lands here; the matching document window shows its lock sheet.
    @Published var lockRequest: URL?

    private var openDocument: ((URL) -> Void)?
    private var openNamed: ((String) -> Void)?
    private var pending: [() -> Void] = []
    private var lastHandled: (url: URL, at: Date)?
    private var started = false
    private var confirmGate = OneAtATime()
    /// Random per-launch secret shared with the Finder extension through the app-group container.
    private var urlToken: String?
    private let engine = ConversionEngine()

    // MARK: lifecycle

    /// Called by the first bridge view that appears. Never touches Keychain or system state.
    func start() {
        guard !started else { return }
        started = true
        publishURLToken()
        HotkeyManager.shared.start { [weak self] in self?.showQuickCreate() }
        syncHotkeyFromFile()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadSettingsFromDisk() }
        }
        let flushed = pending
        pending = []
        flushed.forEach { $0() }
        // First launch only; the window just shows the tiles and never acts by itself.
        // Migrate the old UserDefaults flag once.
        if UserDefaults.standard.bool(forKey: "setupShown") {
            UserDefaults.standard.removeObject(forKey: "setupShown")
            if !settings.setupShown { update { $0.setupShown = true } }
        }
        if !settings.setupShown && flushed.isEmpty {
            update { $0.setupShown = true }
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

    func update(_ change: (inout OpenTextSettings) -> Void) {
        var s = settings
        change(&s)
        guard !s.same(as: settings) else { return }
        let hotkeyChanged = s.hotkey != settings.hotkey
        settings = s
        do { try s.save() } catch { notice = Notice(title: "Settings not saved", message: error.localizedDescription) }
        if hotkeyChanged { hotkeyValid = HotkeyManager.shared.apply(s.hotkey) }
    }

    /// Called by the shortcut recorder: mirror the new shortcut into settings.json.
    func shortcutRecorded() {
        guard let str = HotkeyManager.shared.currentString else { return }
        hotkeyValid = true
        if str != settings.hotkey { update { $0.hotkey = str } }
    }

    private func publishURLToken() {
        guard let dir = TokenStore.groupContainer() else { return }   // no app group: every URL asks first
        urlToken = try? TokenStore.rotate(in: dir)
    }

    private func reloadSettingsFromDisk() {
        let s = OpenTextSettings.load()
        guard !s.same(as: settings) else { return }
        settings = s
        syncHotkeyFromFile()
    }

    /// File wins when it differs from what KeyboardShortcuts stored (hand/AI edits).
    private func syncHotkeyFromFile() {
        if settings.hotkey != HotkeyManager.shared.currentString {
            hotkeyValid = HotkeyManager.shared.apply(settings.hotkey)
        } else {
            hotkeyValid = true
        }
    }

    // MARK: windows

    func showQuickCreate() { whenReady { [self] in NSApp.activate(); openNamed?("quick-create") } }
    func showSetup() { whenReady { [self] in NSApp.activate(); openNamed?("setup") } }
    func showNotice(_ n: Notice) { notice = n; whenReady { [self] in NSApp.activate(); openNamed?("notice") } }

    func openFile(_ url: URL) {
        guard FileRouting.kind(for: url) != .unsupported else { NSSound.beep(); return }
        whenReady { [self] in NSApp.activate(); openDocument?(url) }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] r in
            guard r == .OK else { return }
            Task { @MainActor in panel.urls.forEach { self?.openFile($0) } }
        }
    }

    /// Folder-only picker, shown only when the user clicks Change.
    func chooseFolder(startingAt path: String, completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        panel.prompt = "Choose"
        panel.begin { r in
            guard r == .OK, let url = panel.url else { return }
            Task { @MainActor in completion(url.path) }
        }
    }

    // MARK: URL / file entry point

    /// Handles file URLs and opentext:// URLs from application(_:open:) and .onOpenURL.
    /// Signed URLs (valid token from the Finder extension) run; unsigned ones ask first. Paths must stay in $HOME.
    func handle(_ url: URL) {
        if let last = lastHandled, last.url == url, Date().timeIntervalSince(last.at) < 1 { return }
        lastHandled = (url, Date())
        if url.isFileURL { openFile(url); return }
        do {
            let route = try RouteGuard.validate(try URLRouter.parse(url))
            let signed = TokenStore.matches(URLRouter.token(in: url), expected: urlToken)
            switch ConfirmationPolicy.decide(route, tokenValid: signed, defaultFolder: settings.defaultFolderURL) {
            case .run: perform(route)
            case .confirm(let title, let detail): confirm(title: title, detail: detail) { self.perform(route) }
            }
        } catch {
            showNotice(Notice(title: "Link ignored", message: "\(url.absoluteString)\n\(error)"))
        }
    }

    private func confirm(title: String, detail: String, run: @escaping () -> Void) {
        guard confirmGate.begin() else { return }       // one unsigned-URL dialog at a time
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail + "\n\nOnly continue if you asked for this."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        confirmGate.end()
        if response == .alertFirstButtonReturn { run() }
    }

    private func perform(_ route: AppRoute) {
        switch route {
        case .new(let format, let dir): createNew(format: format, name: "Untitled", in: dir)
        case .convert(let to, let file): convertInBackground(file, to: to)
        case .lock(let file): openFile(file); lockRequest = file
        }
    }

    /// One code path for quick create, the hotkey window and Finder `new`.
    func createNew(format: String, name: String, in dir: URL? = nil) {
        guard let fmt = DocFormat(name: format) else { return }
        do {
            let url = try NewFile.create(fmt, name: name, in: dir ?? settings.defaultFolderURL)
            update { $0.lastNewFileFormat = format }
            openFile(url)
        } catch {
            showNotice(Notice(title: "Could not create the file", message: error.localizedDescription))
        }
    }

    /// Converts next to the original and reports in the notice window (no auto-open).
    func convertInBackground(_ file: URL, to format: String) {
        guard let fmt = DocFormat(name: format) else { return }
        let engine = self.engine
        Task {
            do {
                let out = try await Task.detached { try engine.convert(file, to: fmt) }.value
                let names = out.map(\.lastPathComponent).joined(separator: "\n")
                showNotice(Notice(title: "Converted", message: names, revealURL: out.first))
            } catch {
                showNotice(Notice(title: "Could not convert \(file.lastPathComponent)", message: error.localizedDescription))
            }
        }
    }
}
