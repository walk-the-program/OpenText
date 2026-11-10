import SwiftUI
import OpenTextUI

/// QuickCreateView wired to settings + NewFile.create. Used by the menu bar popover and the hotkey window.
struct QuickCreateHost: View {
    var isPopover: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var state = QuickCreateState()
    @State private var hostWindow: NSWindow?

    var body: some View {
        QuickCreateView(state: $state, onCreate: create, onChangeFolder: changeFolder, onCancel: dismiss)
            .background(WindowAccessor { hostWindow = $0 })
            .onAppear(perform: reset)
    }

    private func reset() {
        state = QuickCreateState(name: "Untitled", format: model.settings.lastNewFileFormat,
                                 folderPath: model.settings.defaultFolder)
    }

    private func create() {
        let folder = URL(fileURLWithPath: (state.folderPath as NSString).expandingTildeInPath, isDirectory: true)
        let (format, name) = (state.format, state.name.isEmpty ? "Untitled" : state.name)
        // The panel closes as soon as the file exists, so it can never hide the new document window.
        if model.createNew(format: format, name: name, in: folder) { dismiss() }
    }

    private func changeFolder() {
        model.chooseFolder(startingAt: state.folderPath) { path in
            state.folderPath = path
            model.update { $0.defaultFolder = path }
        }
    }

    private func dismiss() {
        if isPopover { hostWindow?.orderOut(nil) } else { dismissWindow(id: "quick-create") }
    }
}

/// Reports the NSWindow hosting a SwiftUI view (the MenuBarExtra panel has no dismiss action).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in onWindow(v?.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { [weak v] in onWindow(v?.window) }
    }
}
