import SwiftUI
import OpenTextUI
import KeyboardShortcuts

/// SetupView wired to SetupActions. Nothing happens until the user presses a button.
struct SetupHost: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var state = SetupState()

    var body: some View {
        SetupView(state: $state, actions: SetupActions(
            onMakeDefault: { Task {
                state.defaultAppsNote = OpenTextSetup.failureNote(await OpenTextSetup.makeDefault())
                refresh()
            } },
            onOpenFinderSettings: { OpenTextSetup.openExtensionSettings() },
            onShortcutChanged: { new in model.update { $0.hotkey = new }; refresh() },
            onDone: { dismissWindow(id: "setup") }),
            shortcutRecorder: AnyView(KeyboardShortcuts.Recorder(for: .quickCreate) { _ in
                model.shortcutRecorded(); refresh()
            }))
        .frame(width: 940, height: 500)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        state.defaultAppsDone = OpenTextSetup.allDefaults
        state.finderExtensionOn = OpenTextSetup.finderExtensionEnabled
        state.shortcut = model.settings.hotkey
        state.shortcutWarning = model.hotkeyValid ? nil : "That shortcut can't be used. Try a modifier plus a letter or number."
    }
}
