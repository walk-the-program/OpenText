import AppKit
import Combine
import SwiftUI
import OpenTextKit
import OpenTextUI
import OpenTextAppLogic

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

    /// The document window that is key (or main) right now. File menu items fall back to it when SwiftUI has
    /// not published a focused scene value yet, which is the case for a window that was just created.
    private(set) var keyDocument: DocumentSession?
    private var keyDocumentChange: AnyCancellable?

    private var openDocument: ((URL) -> Void)?
    private var openNamed: ((String) -> Void)?
    /// AppKit delivers application(_:open:) before applicationDidFinishLaunching. An open that arrives first means
    /// macOS launched us for those files or links, and the home window stays away.
    private(set) var launchedWithFiles = false
    private var didFinishLaunching = false
    private var pending: [() -> Void] = []
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
        if !SelfTest.enabled {                      // the self-test touches no system state
            publishURLToken()
            HotkeyManager.shared.start { [weak self] in self?.showQuickCreate() }
            syncHotkeyFromFile()
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshKeyDocument() }
            }
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { n in
                guard let w = n.object as? NSWindow else { return }
                MainActor.assumeIsolated { AppModel.bringOnScreen(w) }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadSettingsFromDisk() }
        }
        let flushed = pending
        pending = []
        flushed.forEach { $0() }
        // Migrate the old UserDefaults flag once. The first-run setup window is opened by HomeHost.
        if !SelfTest.enabled, UserDefaults.standard.bool(forKey: "setupShown") {
            UserDefaults.standard.removeObject(forKey: "setupShown")
            if !settings.setupShown { update { $0.setupShown = true } }
        }
    }

    /// Re-reads which document window is key and re-publishes whenever its state (saved, busy, ...) changes.
    func refreshKeyDocument() {
        let w = NSApp.keyWindow ?? NSApp.mainWindow
        let session = w.flatMap { win in DocumentSession.openSessions.first { $0.window === win } }
        guard session !== keyDocument else { return }
        keyDocument = session
        keyDocumentChange = session?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        objectWillChange.send()
    }

    /// Menu actions for the key document window; nil when none is key.
    var keyDocumentActions: DocActions? { keyDocument.map { DocActions(session: $0, model: self) } }

    /// The permanent bridge window attaches once; it is never closed, so these actions stay live.
    func attach(openDocument: @escaping (URL) -> Void, openNamed: @escaping (String) -> Void) {
        self.openDocument = openDocument
        self.openNamed = openNamed
        start()
    }

    /// True once the bridge is attached and everything queued before it has run.
    var isReady: Bool { openDocument != nil && pending.isEmpty }

    /// Any window the user can see (not the invisible bridge, panels or the menu bar item).
    var hasUserWindow: Bool {
        NSApp.windows.contains { w in
            w.isVisible && !(w is NSPanel) && w.canBecomeKey && !(w.identifier?.rawValue.contains("bridge") ?? false)
        }
    }

    /// Called from applicationDidFinishLaunching.
    func finishLaunching() {
        didFinishLaunching = true
        if !launchedWithFiles { showHome() }
    }

    /// An open delivered before launch finished means we were launched to open it.
    func noteExternalOpen() {
        if !didFinishLaunching { launchedWithFiles = true }
    }

    /// First run also opens setup, from the home window.
    func homeAppeared() {
        if !settings.setupShown {
            update { $0.setupShown = true }
            showSetup()
        }
    }

    private func whenReady(_ work: @escaping () -> Void) {
        if openDocument == nil { pending.append(work) } else { work() }
    }

    // MARK: settings

    func update(_ change: (inout OpenTextSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
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
        guard s != settings else { return }
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

    private func activate() { if !SelfTest.enabled { NSApp.activate() } }

    func showQuickCreate() { whenReady { [self] in activate(); openNamed?("quick-create"); raise("quick-create") } }
    func showHome() { whenReady { [self] in activate(); openNamed?("home"); raise("home") } }
    func showSetup() { whenReady { [self] in activate(); openNamed?("setup"); raise("setup") } }
    func showNotice(_ n: Notice) { notice = n; whenReady { [self] in activate(); openNamed?("notice"); raise("notice") } }

    /// openWindow(id:) on a window that is already open does not always bring it forward (it can sit behind
    /// Home after first-run setup opened it), so a button that "opens" it would appear to do nothing.
    private func raise(_ id: String) {
        DispatchQueue.main.async {
            guard let w = NSApp.windows.first(where: { $0.isVisible && ($0.identifier?.rawValue.contains(id) ?? false) }) else { return }
            Self.bringOnScreen(w)
            w.makeKeyAndOrderFront(nil)
        }
    }

    /// A saved frame can point off every screen (an unplugged display, or an old self-test run that wrote
    /// off-screen frames to the real preferences). Such a window "opens" where nobody can see it, so center it.
    static func bringOnScreen(_ w: NSWindow) {
        guard !SelfTest.enabled, !(w is NSPanel), w.isVisible,
              !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(w.frame.insetBy(dx: 40, dy: 40)) }) else { return }
        w.center()
    }

    func openFile(_ url: URL) {
        guard FileRouting.kind(for: url) != .unsupported else { NSSound.beep(); return }
        if !SelfTest.enabled { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        // SwiftUI orders a new (or already open) window for this URL to the front once the app is active.
        whenReady { [self] in
            activate()
            openDocument?(url)
        }
    }

    /// `onOpened` runs after the chosen files were handed to their windows (Home closes itself then).
    func openPanel(onOpened: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] r in
            guard r == .OK else { return }
            Task { @MainActor in
                guard let self else { return }
                let opened = panel.urls.filter { FileRouting.kind(for: $0) != .unsupported }
                panel.urls.forEach { self.openFile($0) }
                if !opened.isEmpty { onOpened?() }
            }
        }
    }

    /// Single-file picker for Home's Convert and Lock cards.
    func pickFile(prompt: String, completion: @escaping (URL) -> Void) {
        if SelfTest.enabled {
            SelfTest.stub("pickFile")
            if let url = SelfTest.pickFileURL { completion(url) }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.begin { r in
            guard r == .OK, let url = panel.url else { return }
            Task { @MainActor in completion(url) }
        }
    }

    /// Formats `file` can be converted to (lowercase extensions), empty when none.
    func convertTargets(for file: URL) -> [String] {
        guard let f = DocFormat(url: file), f != .otlock else { return [] }
        return engine.targets(from: f).map(\.fileExtension)
    }

    /// Converts next to the original off the main thread; returns the files written.
    func convertNow(_ file: URL, to format: String) async throws -> [URL] {
        guard let fmt = DocFormat(name: format) else { throw ToolError("Unknown format .\(format)") }
        let engine = self.engine
        return try await Task.detached { try engine.convert(file, to: fmt) }.value
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

    /// Handles file URLs and opentext:// URLs from application(_:open:).
    /// Signed URLs (valid token from the Finder extension) run; unsigned ones ask first. Paths must stay in $HOME.
    func handle(_ url: URL) {
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
        activate()
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

    /// One code path for quick create, the hotkey window and Finder `new`. True when the file was created and
    /// is opening; callers close their own window only then.
    @discardableResult
    func createNew(format: String, name: String, in dir: URL? = nil) -> Bool {
        guard let fmt = DocFormat(name: format) else { return false }
        do {
            let url = try NewFile.create(fmt, name: name, in: dir ?? settings.defaultFolderURL)
            update { $0.lastNewFileFormat = format }
            openFile(url)
            return true
        } catch {
            showNotice(Notice(title: "Could not create the file", message: error.localizedDescription))
            return false
        }
    }

    private var conversionsRunning = 0
    private var conversionOutputs: [URL] = []
    private var conversionFailures: [String] = []

    /// Converts next to the original. Several files in a row (Finder multi-select) end in one combined notice
    /// listing every result (no auto-open).
    func convertInBackground(_ file: URL, to format: String) {
        guard let fmt = DocFormat(name: format) else { return }
        let engine = self.engine
        conversionsRunning += 1
        Task {
            do {
                conversionOutputs += try await Task.detached { try engine.convert(file, to: fmt) }.value
            } catch {
                conversionFailures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
            conversionsRunning -= 1
            try? await Task.sleep(for: .milliseconds(400))      // let the rest of a multi-select arrive
            if conversionsRunning == 0 { showConversionSummary() }
        }
    }

    private func showConversionSummary() {
        guard !conversionOutputs.isEmpty || !conversionFailures.isEmpty else { return }
        var lines = conversionOutputs.map(\.lastPathComponent)
        if !conversionFailures.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Could not convert:")
            lines += conversionFailures
        }
        let title = conversionFailures.isEmpty ? "Converted"
            : conversionOutputs.isEmpty ? "Could not convert" : "Converted, with problems"
        showNotice(Notice(title: title, message: lines.joined(separator: "\n"), revealURL: conversionOutputs.first))
        conversionOutputs = []
        conversionFailures = []
    }
}
