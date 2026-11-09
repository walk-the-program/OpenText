import AppKit
import UniformTypeIdentifiers
import FinderSync

/// Setup actions. Each runs only from a button press in the setup window, never at launch.
enum OpenTextSetup {
    /// The four user-facing types (images, PDF, .txt, .md) expanded to concrete UTTypes.
    static var defaultTypes: [UTType] {
        var t: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .pdf, .plainText]
        if let webp = UTType("org.webmproject.webp") { t.append(webp) }
        if let md = UTType("net.daringfireball.markdown") { t.append(md) }
        return t
    }

    /// macOS shows its own confirmation per type. Returns the types that failed.
    static func makeDefault() async -> [UTType] {
        var failed: [UTType] = []
        for type in defaultTypes {
            do { try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) }
            catch { failed.append(type) }
        }
        return failed
    }

    static func isDefault(for type: UTType) -> Bool {
        NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static var allDefaults: Bool { defaultTypes.allSatisfy(isDefault) }

    static func openExtensionSettings() {
        for s in ["x-apple.systempreferences:com.apple.ExtensionsPreferences",
                  "x-apple.systempreferences:"] {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { return }
        }
    }

    static var finderExtensionEnabled: Bool { FIFinderSyncController.isExtensionEnabled }
}
