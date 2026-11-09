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
    @FocusedValue(\.documentCommands) private var cmds

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

    private func item(_ title: String, _ c: DocumentCommands.Command, _ key: KeyEquivalent,
                      _ mods: EventModifiers = .command) -> some View {
        Button(title) { cmds?.perform(c) }
            .keyboardShortcut(key, modifiers: mods)
            .disabled(!(cmds?.isAvailable(c) ?? false))
    }

    /// One menu set. Where a view also binds the same key (Save, Convert), the menu item wins, so each
    /// key does one thing. Edit, View, Markdown and Image items drive the view through DocumentCommands; Highlight, Sign, Edit/Preview and Mono stay in the views.
    @CommandsBuilder private var menus: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New…") { model.showQuickCreate() }.keyboardShortcut("n")
            Button("Open…") { model.openPanel() }.keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Save") { doc?.save() }.keyboardShortcut("s").disabled(!(doc?.canSave ?? false))
            Button("Revert to Saved…") { doc?.revert() }.disabled(!(doc?.canRevert ?? false))
            Button("Convert…") { doc?.convert() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(doc == nil)
            Button("Lock…") { doc?.lock() }.keyboardShortcut("l", modifiers: [.command, .control]).disabled(doc == nil)
        }
        CommandGroup(after: .textEditing) {
            item("Find", .find, "f")
        }
        CommandGroup(after: .toolbar) {
            item("Zoom In", .zoomIn, "=")
            item("Zoom Out", .zoomOut, "-")
            item("Actual Size", .actualSize, "0")
            item("Thumbnails", .toggleThumbnails, "s", [.command, .option])
        }
        CommandMenu("Markdown") {
            item("Heading 1", .heading(1), "1")
            item("Heading 2", .heading(2), "2")
            item("Heading 3", .heading(3), "3")
            item("Bold", .bold, "b")
            item("Italic", .italic, "i")
            item("List", .list, "l", [.command, .shift])
            item("Link", .link, "k")
        }
        CommandMenu("Image") {
            item("Crop", .crop, "k")
            item("Resize…", .resize, "i", [.command, .option])
            item("Rotate", .rotate, "r")
            item("Flip Horizontal", .flipHorizontal, "h", [.command, .control])
            item("Flip Vertical", .flipVertical, "v", [.command, .control])
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
