import SwiftUI
import OpenTextUI
import OpenTextAppLogic

/// HomeView wired to AppModel. Shown by code at launch; first run also opens setup from here (this view's environment is live).
/// Home has done its job once a file is created or opened, so it closes then; Convert and Lock work in place.
struct HomeHost: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var state = QuickCreateState()
    @State private var convert = HomeConvertState()
    @State private var lock = HomeLockState()
    @State private var recents: [URL] = []
    @State private var setupIncomplete = false
    @State private var recoveryKey: String?

    var body: some View {
        HomeView(quickCreate: $state, convert: $convert, lock: $lock, recents: recents,
                 setupIncomplete: setupIncomplete, actions: actions)
        .onAppear {
            state = QuickCreateState(name: "Untitled", format: model.settings.lastNewFileFormat, folderPath: model.settings.defaultFolder)
            refreshRecents()
            model.homeAppeared()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshRecents() }
        .onReceive(NotificationCenter.default.publisher(for: SelfTest.refreshHome)) { _ in refreshRecents() }
        .sheet(isPresented: Binding(get: { recoveryKey != nil }, set: { if !$0 { recoveryKey = nil } })) {
            if let key = recoveryKey { RecoveryKeySheet(displayString: key, onDone: { recoveryKey = nil }) }
        }
    }

    private var actions: HomeActions {
        var a = HomeActions()
        a.onCreate = create
        a.onChangeFolder = changeFolder
        a.onOpenPanel = { model.openPanel { closeHome() } }
        a.onOpenURL = { open([$0]) }
        a.onDropURLs = { open($0) }
        a.onFinishSetup = { model.showSetup() }
        a.onPickConvertFile = { model.pickFile(prompt: "Choose") { setConvertFile($0) } }
        a.onConvertFile = setConvertFile
        a.onConvert = runConvert
        a.onPickLockFile = { model.pickFile(prompt: "Choose") { setLockFile($0) } }
        a.onLockFile = setLockFile
        a.onLock = runLock
        a.onReveal = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        return a
    }

    private func closeHome() { dismissWindow(id: "home") }

    /// Opens the files OpenText can show and closes Home if at least one opened.
    @discardableResult
    private func open(_ urls: [URL]) -> Bool {
        let files = urls.filter { $0.isFileURL && FileRouting.kind(for: $0) != .unsupported }
        guard !files.isEmpty else { NSSound.beep(); return false }
        files.forEach { model.openFile($0) }
        closeHome()
        return true
    }

    private func refreshRecents() {
        recents = (SelfTest.enabled ? SelfTest.recents : NSDocumentController.shared.recentDocumentURLs)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        setupIncomplete = SelfTest.enabled || !OpenTextSetup.allDefaults || !OpenTextSetup.finderExtensionEnabled
    }

    private func create() {
        let folder = URL(fileURLWithPath: (state.folderPath as NSString).expandingTildeInPath, isDirectory: true)
        // The new document opens in its own window; Home has done its job and closes (only if the file was made).
        if model.createNew(format: state.format, name: state.name.isEmpty ? "Untitled" : state.name, in: folder) {
            closeHome()
        }
    }

    private func changeFolder() {
        model.chooseFolder(startingAt: state.folderPath) { path in
            state.folderPath = path
            model.update { $0.defaultFolder = path }
        }
    }

    // MARK: Convert card

    private func setConvertFile(_ url: URL) {
        // Locking has its own card; converting to a locked file is not offered here.
        let targets = model.convertTargets(for: url).filter { $0 != "otlock" }
        convert.file = url
        convert.targets = targets
        convert.target = targets.first
        convert.status = targets.isEmpty ? HomeStatus(message: "OpenText can't convert \(url.lastPathComponent).", isError: true) : nil
    }

    private func runConvert() {
        guard let file = convert.file, let target = convert.target, !convert.busy else { return }
        convert.busy = true
        convert.status = nil
        Task {
            do {
                let outputs = try await model.convertNow(file, to: target)
                let names = outputs.map(\.lastPathComponent).joined(separator: ", ")
                convert.status = HomeStatus(message: "Made \(names) next to the original.", reveal: outputs.first)
            } catch {
                convert.status = HomeStatus(message: error.localizedDescription, isError: true)
            }
            convert.busy = false
        }
    }

    // MARK: Lock card

    private func setLockFile(_ url: URL) {
        lock.file = url
        lock.status = url.pathExtension.lowercased() == "otlock"
            ? HomeStatus(message: "\(url.lastPathComponent) is already locked.", isError: true) : nil
    }

    private func runLock() {
        guard let file = lock.file, !lock.busy else { return }
        guard file.pathExtension.lowercased() != "otlock" else { setLockFile(file); return }
        lock.busy = true
        lock.status = nil
        let password = lock.password, confirm = lock.confirm
        Task {
            do {
                let out = try await LockFlow.lock(file, password: password, confirm: confirm, model: model)
                var message = out.originalStillThere
                    ? "Locked. The original is still at its old place; move it to the Trash yourself."
                    : "Locked. The original is in the Trash."
                if !out.warnings.isEmpty { message += " " + out.warnings.joined(separator: " ") }
                lock = HomeLockState()
                lock.status = HomeStatus(message: message, reveal: out.lockedURL)
                recoveryKey = out.recoveryKeyToShow        // first lock only: shown once, never stored
            } catch {
                lock.busy = false
                lock.status = HomeStatus(message: error.localizedDescription, isError: true)
            }
        }
    }
}
