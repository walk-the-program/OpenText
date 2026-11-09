import SwiftUI
import OpenTextUI

/// QuickCreateView wired to settings + NewFile.create. Used by the menu bar popover and the hotkey window.
struct QuickCreateHost: View {
    var isPopover: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var state = QuickCreateState()

    var body: some View {
        QuickCreateView(state: $state, onCreate: create, onChangeFolder: changeFolder, onCancel: dismiss)
            .onAppear(perform: reset)
    }

    private func reset() {
        state = QuickCreateState(name: "Untitled", format: model.settings.lastNewFileFormat,
                                 folderPath: model.settings.defaultFolder)
    }

    private func create() {
        let folder = URL(fileURLWithPath: (state.folderPath as NSString).expandingTildeInPath, isDirectory: true)
        model.createNew(format: state.format, name: state.name.isEmpty ? "Untitled" : state.name, in: folder)
        dismiss()
    }

    private func changeFolder() {
        model.chooseFolder(startingAt: state.folderPath) { path in
            state.folderPath = path
            model.update { $0.defaultFolder = path }
        }
    }

    private func dismiss() {
        if isPopover { NSApp.keyWindow?.orderOut(nil) } else { dismissWindow(id: "quick-create") }
    }
}
