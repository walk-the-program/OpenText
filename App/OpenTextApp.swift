import SwiftUI
import OpenTextAppLogic

// Windowing choice: WindowGroup(for: URL.self) — one window per file, SwiftUI de-duplicates
// the same URL (re-opening focuses the existing window). NSDocumentController was rejected: it
// wants a document model and autosave, but OpenText edits files in place and opens many formats.

@main
struct OpenTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("OpenText", for: URL.self) { $url in
            if let url {
                DocumentWindowView(url: url)
                    .environmentObject(model)
                    .modifier(RouterBridge())
            }
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            QuickCreateStandIn().environmentObject(model).frame(width: 260)
        } label: {
            // The label is alive from launch, so it hosts the bridge that supplies openWindow.
            Image(systemName: "doc.text").modifier(RouterBridge())
        }
        .menuBarExtraStyle(.window)

        Window("Quick Create", id: "quick-create") {
            QuickCreateStandIn().environmentObject(model).frame(width: 260).modifier(RouterBridge())
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Welcome to OpenText", id: "setup") {
            SetupStandIn().environmentObject(model).modifier(RouterBridge())
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
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
