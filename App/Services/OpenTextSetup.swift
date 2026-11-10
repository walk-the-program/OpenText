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
        if SelfTest.enabled { SelfTest.stub("makeDefault"); return SelfTest.makeDefaultFailures }      // the self-test never changes default apps
        var failed: [UTType] = []
        for type in defaultTypes {
            do { try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) }
            catch { failed.append(type) }
        }
        return failed
    }

    /// "Couldn't make default for: .png, .tiff" - the extensions of the types macOS refused.
    static func failureNote(_ failed: [UTType]) -> String? {
        guard !failed.isEmpty else { return nil }
        let names = failed.map { $0.preferredFilenameExtension.map { ".\($0)" } ?? $0.identifier }
        return "Couldn't make default for: " + names.joined(separator: ", ")
    }

    static func isDefault(for type: UTType) -> Bool {
        NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static var allDefaults: Bool { defaultTypes.allSatisfy(isDefault) }

    /// Opens the system's own Finder extension list (Login Items & Extensions).
    static func openExtensionSettings() {
        if SelfTest.enabled { SelfTest.stub("finderExtension"); return }      // the self-test never opens System Settings
        FIFinderSyncController.showExtensionManagementInterface()
    }

    static var finderExtensionEnabled: Bool { FIFinderSyncController.isExtensionEnabled }
}
