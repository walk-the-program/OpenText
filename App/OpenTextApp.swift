import SwiftUI
import OpenTextDesign
import OpenTextUI
import OpenTextAppLogic

// Windowing choice: WindowGroup(for: URL.self) - one window per file, SwiftUI de-duplicates
// the same URL (re-opening focuses the existing window). NSDocumentController was rejected: it
// wants a document model and autosave, but OpenText edits files in place and opens many formats.

@main
struct OpenTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @FocusedValue(\.docActions) private var doc

    init() { Brand.registerFonts() }

    var body: some Scene {
        WindowGroup("OpenText", for: URL.self) { $url in
            if let url {
                DocumentWindowView(url: url)
                    .environmentObject(model)
                    .modifier(RouterBridge())
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .commands { menus }

        MenuBarExtra {
            QuickCreateHost(isPopover: true).environmentObject(model)
        } label: {
            // The label is alive from launch, so it hosts the bridge that supplies openWindow.
            Image(systemName: "doc.text").modifier(RouterBridge())
        }
        .menuBarExtraStyle(.window)

        Window("Quick Create", id: "quick-create") {
            QuickCreateHost(isPopover: false).environmentObject(model).modifier(RouterBridge())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Set up OpenText", id: "setup") {
            SetupHost().environmentObject(model).modifier(RouterBridge())
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("OpenText", id: "notice") {
            NoticeWindowView().environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    /// One menu set. Where a view also binds the same key (Save, Convert), the menu item wins, so each
    /// key does one thing. Find, Zoom, Thumbnails and the Markdown tools are bound inside the views.
    @CommandsBuilder private var menus: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New…") { model.showQuickCreate() }.keyboardShortcut("n")
            Button("Open…") { model.openPanel() }.keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Save") { doc?.save() }.keyboardShortcut("s").disabled(!(doc?.canSave ?? false))
            Button("Convert…") { doc?.convert() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(doc == nil)
            Button("Lock…") { doc?.lock() }.keyboardShortcut("l", modifiers: [.command, .control]).disabled(doc == nil)
        }
        CommandGroup(after: .appSettings) {
            Button("Set Up OpenText…") { model.showSetup() }
        }
    }
}

/// Hands SwiftUI's openWindow to AppModel and forwards .onOpenURL.
struct RouterBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content
            .onAppear {
                AppModel.shared.attach(
                    openDocument: { openWindow(value: $0) },
                    openNamed: { openWindow(id: $0) })
            }
            .onOpenURL { AppModel.shared.handle($0) }
    }
}
