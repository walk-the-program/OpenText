import Foundation
import CryptoKit
import OpenTextAppLogic

// STAND-INS for OpenTextKit (W1). Every call into the engine goes through this file so T3b can
// swap bodies for the real API (ConversionEngine, NewFile, Locker, RecoveryKey, OpenTextSettings)
// without touching call sites. Field and function names mirror PLAN.md rev 1.

enum EngineError: LocalizedError {
    case notWired(String)
    var errorDescription: String? {
        switch self { case .notWired(let what): return "\(what) is not connected to the engine yet." }
    }
}

/// STAND-IN for OpenTextKit.OpenTextSettings (same fields, same JSON file).
struct StandInSettings: Codable, Equatable {
    var defaultFolder: String = "~/Desktop"
    var hotkey: String = "ctrl+opt+n"
    var recoveryPublicKey: String? = nil
    var useTouchID: Bool = true
    var txtMonospace: Bool = false
    var lastNewFileFormat: String = "md"

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenText/settings.json")
    }
    static func load() -> StandInSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(StandInSettings.self, from: data) else { return StandInSettings() }
        return s
    }
    func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: Self.fileURL, options: .atomic)
    }
    var defaultFolderURL: URL { URL(fileURLWithPath: (defaultFolder as NSString).expandingTildeInPath) }
}

enum EngineAdapter {
    /// STAND-IN for NewFile.create: empty file, unique "Untitled 2.md" naming.
    static func newFile(format: String, in folder: URL) throws -> URL {
        var url = folder.appendingPathComponent("Untitled.\(format)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Untitled \(n).\(format)")
            n += 1
        }
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// STAND-IN for ConversionEngine.targets(from:).
    static func convertTargets(from ext: String) -> [String] { FileRouting.convertTargets(fromExtension: ext) }

    /// STAND-IN for ConversionEngine.convert. Only txt<->md copies work; everything else throws.
    static func convert(_ input: URL, to format: String) throws -> [URL] {
        let from = FileRouting.canonicalExtension(input.pathExtension)
        guard (from == "txt" && format == "md") || (from == "md" && format == "txt") else {
            throw EngineError.notWired("Converting \(from) to \(format)")
        }
        let out = try uniqueSibling(of: input, ext: format)
        try FileManager.default.copyItem(at: input, to: out)
        return [out]
    }

    /// STAND-IN for the lock id stored in the .otlock header (T3b: read it from the file).
    static func lockID(for url: URL) -> String {
        SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func isLocked(_ url: URL) -> Bool { url.pathExtension.lowercased() == "otlock" }

    /// STAND-IN for RecoveryKey.generate(). Random 20 bytes, base32, groups of 4. The public key
    /// is a placeholder; the real value comes from Curve25519.
    static func generateRecoveryKey() -> (display: String, publicKeyBase64: String) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var rng = SystemRandomNumberGenerator()
        let chars = (0..<32).map { _ in alphabet[Int(rng.next() % 32)] }
        let groups = stride(from: 0, to: 32, by: 4).map { String(chars[$0..<$0 + 4]) }
        return (groups.joined(separator: "-"), Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString())
    }

    /// STAND-IN for Locker.lock. Throws until T3b so no fake "locked" file is ever written.
    static func lock(_ input: URL, password: String, recoveryPublicKey: String?) throws -> URL {
        throw EngineError.notWired("Locking")
    }
    /// STAND-IN for Locker.unlock(_:password:).
    static func unlock(_ input: URL, password: String) throws -> URL { throw EngineError.notWired("Unlocking") }
    /// STAND-IN for Locker.unlock(_:recoveryKey:) (parse with RecoveryKey(displayString:)).
    static func unlock(_ input: URL, recoveryKey: String) throws -> URL { throw EngineError.notWired("Recovery unlock") }

    private static func uniqueSibling(of url: URL, ext: String) throws -> URL {
        let base = url.deletingPathExtension()
        var out = base.appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = URL(fileURLWithPath: base.path + " \(n)").appendingPathExtension(ext)
            n += 1
        }
        return out
    }
}
