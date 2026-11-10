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

    init() { Brand.registerFonts(); SelfTest.prepare() }

    // Every scene except the bridge opts out of SwiftUI's own file/URL routing (`handlesExternalEvents(matching: [])`):
    // external opens reach AppDelegate.application(_:open:) exactly once and AppModel routes them. The bridge keeps
    // the default: with `[]` on it, a launch-with-file presents no scene at all, so openWindow never comes alive
    // (self-test launch-with-file). It never shows content, so it can't produce a stray window.
    var body: some Scene {
        // Permanent invisible window; its view holds the only RouterBridge, so openWindow is always live.
        Window("", id: "bridge") {
            BridgeView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)

        WindowGroup("OpenText", for: URL.self) { $url in
            if let current = url {
                // A rename moves the file; the scene's URL value follows it, so opening the new path finds this window.
                DocumentWindowView(url: current, onRenamed: { url = $0 }).environmentObject(model)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])
        .commands { menus }

        // Shown by AppDelegate.applicationDidFinishLaunching, and only when launch wasn't for files.
        Window("OpenText", id: "home") {
            HomeHost().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        MenuBarExtra(isInserted: .constant(!SelfTest.enabled)) {
            QuickCreateHost(isPopover: true).environmentObject(model)
        } label: {
            Image(nsImage: BrandMark.templateImage(pointSize: 16))
        }
        .menuBarExtraStyle(.window)
        .handlesExternalEvents(matching: [])

        Window("Quick Create", id: "quick-create") {
            QuickCreateHost(isPopover: false).environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        Window("Set up OpenText", id: "setup") {
            SetupHost().environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])

        Window("OpenText", id: "notice") {
            NoticeWindowView().environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])
    }

    /// The focused document's actions; a window that was just created has no focused scene value yet, so the key
    /// document window stands in (otherwise ⌘S on a fresh file would be disabled).
    private var activeDoc: DocActions? { doc ?? model.keyDocumentActions }

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
            Button("Save") { activeDoc?.save() }.keyboardShortcut("s").disabled(!(activeDoc?.canSave ?? false))
            Button("Revert to Saved…") { activeDoc?.revert() }.disabled(!(activeDoc?.canRevert ?? false))
            Button("Convert…") { activeDoc?.convert() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(activeDoc == nil)
            Button("Lock…") { activeDoc?.lock() }.keyboardShortcut("l", modifiers: [.command, .control]).disabled(activeDoc == nil)
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
        CommandGroup(after: .windowArrangement) {
            Button("OpenText Home") { model.showHome() }.keyboardShortcut("h", modifiers: [.command, .shift])
        }
        CommandGroup(after: .appSettings) {
            Button("Set Up OpenText…") { model.showSetup() }
        }
    }
}

/// Hands SwiftUI's openWindow to AppModel. Used only by BridgeView, the permanent window.
struct RouterBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            AppModel.shared.attach(openDocument: { openWindow(value: $0) }, openNamed: { openWindow(id: $0) })
        }
    }
}

/// Root of the bridge window: 1x1, transparent, off-screen, never in the Windows menu, never closable.
struct BridgeView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(BridgeWindowConfigurator())
            .modifier(RouterBridge())
    }
}

struct BridgeWindowConfigurator: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            guard let w = window else { return }
            w.collectionBehavior = [.transient, .ignoresCycle, .stationary, .fullScreenNone]
            w.isExcludedFromWindowsMenu = true
            w.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
            w.styleMask.remove(.closable)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.alphaValue = 0
            let x = (NSScreen.screens.map(\.frame.maxX).max() ?? 0) + 20000
            w.setFrameOrigin(NSPoint(x: x, y: 0))
        }
    }
    func makeNSView(context: Context) -> NSView { Anchor() }
    func updateNSView(_ v: NSView, context: Context) {}
}
