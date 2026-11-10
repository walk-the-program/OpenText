import SwiftUI
import OpenTextUI

/// HomeView wired to AppModel. Shown by code at launch; first run also opens setup from here (this view's environment is live).
struct HomeHost: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var state = QuickCreateState()
    @State private var recents: [URL] = []
    @State private var setupIncomplete = false

    var body: some View {
        HomeView(
            quickCreate: $state, recents: recents, setupIncomplete: setupIncomplete,
            onCreate: create, onChangeFolder: changeFolder,
            onOpenPanel: { model.openPanel() },
            onOpenURL: { model.openFile($0) },
            onDropURLs: { urls in
                let files = urls.filter(\.isFileURL)
                files.forEach { model.openFile($0) }
                return !files.isEmpty
            },
            onFinishSetup: { model.showSetup() })
        .onAppear {
            state = QuickCreateState(name: "Untitled", format: model.settings.lastNewFileFormat, folderPath: model.settings.defaultFolder)
            refreshRecents()
            model.homeAppeared()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshRecents() }
    }

    private func refreshRecents() {
        recents = NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        setupIncomplete = SelfTest.enabled || !OpenTextSetup.allDefaults || !OpenTextSetup.finderExtensionEnabled
    }

    private func create() {
        let folder = URL(fileURLWithPath: (state.folderPath as NSString).expandingTildeInPath, isDirectory: true)
        // The new document opens in its own window; Home has done its job and closes (only if the file was made).
        if model.createNew(format: state.format, name: state.name.isEmpty ? "Untitled" : state.name, in: folder) {
            dismissWindow(id: "home")
        }
    }

    private func changeFolder() {
        model.chooseFolder(startingAt: state.folderPath) { path in
            state.folderPath = path
            model.update { $0.defaultFolder = path }
        }
    }
}
