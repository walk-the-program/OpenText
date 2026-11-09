import AppKit
import SwiftUI
import OpenTextKit
import OpenTextUI
import OpenTextAppLogic

extension OpenTextSettings {
    func same(as o: OpenTextSettings) -> Bool {
        defaultFolder == o.defaultFolder && hotkey == o.hotkey && recoveryPublicKey == o.recoveryPublicKey
            && useTouchID == o.useTouchID && txtMonospace == o.txtMonospace && lastNewFileFormat == o.lastNewFileFormat
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
    private let engine = ConversionEngine()

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
        // First launch only; the window just shows the tiles and never acts by itself.
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

    func update(_ change: (inout OpenTextSettings) -> Void) {
        var s = settings
        change(&s)
        guard !s.same(as: settings) else { return }
        let hotkeyChanged = s.hotkey != settings.hotkey
        settings = s
        do { try s.save() } catch { notice = Notice(title: "Settings not saved", message: error.localizedDescription) }
        if hotkeyChanged { hotkeyValid = HotkeyManager.shared.apply(s.hotkey) }
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
    func handle(_ url: URL) {
        if let last = lastHandled, last.url == url, Date().timeIntervalSince(last.at) < 1 { return }
        lastHandled = (url, Date())
        if url.isFileURL { openFile(url); return }
        do {
            switch try URLRouter.parse(url) {
            case .new(let format, let dir): createNew(format: format, name: "Untitled", in: dir)
            case .convert(let to, let file): convertInBackground(file, to: to)
            case .lock(let file): openFile(file); lockRequest = file
            }
        } catch {
            showNotice(Notice(title: "Link ignored", message: "\(url.absoluteString)\n\(error)"))
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
