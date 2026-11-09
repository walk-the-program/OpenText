import Foundation
import Security

// Security helpers for opentext:// URLs and for save safety. Pure Foundation so they are unit-testable
// and shared with the sandboxed Finder extension.

/// Shared secret between the app and the Finder extension (app-group container file).
public enum TokenStore {
    public static let groupID = "7ZT7J8C9QP.com.walkertracy.opentext"
    static let fileName = "url-token"

    public static func groupContainer() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
    public static func tokenFile(in dir: URL) -> URL { dir.appendingPathComponent(fileName) }

    /// Writes a fresh random 32-byte token (hex, mode 0600) and returns it.
    @discardableResult
    public static func rotate(in dir: URL) throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = tokenFile(in: dir)
        try Data(token.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return token
    }

    public static func read(in dir: URL) -> String? {
        guard let d = try? Data(contentsOf: tokenFile(in: dir)), let s = String(data: d, encoding: .utf8),
              s.count == 64 else { return nil }
        return s
    }

    /// Constant-time comparison; a missing token on either side never matches.
    public static func matches(_ given: String?, expected: String?) -> Bool {
        guard let g = given?.utf8, let e = expected?.utf8, !e.isEmpty, g.count == e.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(g, e) { diff |= a ^ b }
        return diff == 0
    }
}

/// Only paths inside the home folder (and outside ~/Library) may be targeted by a URL.
public enum PathPolicy {
    /// Resolves symlinks of the deepest existing ancestor, then re-appends the not-yet-existing tail.
    public static func resolve(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            tail.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var out = existing.resolvingSymlinksInPath()
        for t in tail { out.appendPathComponent(t) }
        return out.standardizedFileURL
    }

    public static func isAllowed(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let h = resolve(home).path.lowercased()
        let p = resolve(url).path.lowercased()
        guard p == h || p.hasPrefix(h + "/") else { return false }
        let lib = h + "/library"
        return !(p == lib || p.hasPrefix(lib + "/"))
    }
}

public enum RouteGuard {
    /// Throws `.badPath` for any path outside the allowed area; returns the route with symlinks resolved.
    public static func validate(_ route: AppRoute, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> AppRoute {
        func check(_ u: URL) throws -> URL {
            guard PathPolicy.isAllowed(u, home: home) else { throw RouteError.badPath(u.path) }
            return PathPolicy.resolve(u)
        }
        switch route {
        case .new(let f, let dir): return .new(format: f, dir: try dir.map(check))
        case .convert(let to, let file): return .convert(to: to, file: try check(file))
        case .lock(let file): return .lock(file: try check(file))
        }
    }
}

public enum RouteDecision: Equatable, Sendable {
    case run
    case confirm(title: String, detail: String)
}

public enum ConfirmationPolicy {
    /// Signed (valid token) URLs run directly; anything else needs a click.
    public static func decide(_ route: AppRoute, tokenValid: Bool, defaultFolder: URL) -> RouteDecision {
        if tokenValid { return .run }
        switch route {
        case .new(let format, let dir):
            let folder = dir ?? defaultFolder
            return .confirm(title: "Create Untitled.\(format) in \(folder.lastPathComponent)?",
                            detail: "A link or another app asked OpenText to create a file in \(folder.path).")
        case .convert(let to, let file):
            return .confirm(title: "Convert \(file.lastPathComponent) to \(to) in \(file.deletingLastPathComponent().lastPathComponent)?",
                            detail: "A link or another app asked OpenText to convert \(file.path).")
        case .lock(let file):
            return .confirm(title: "Lock \(file.lastPathComponent) in \(file.deletingLastPathComponent().lastPathComponent)?",
                            detail: "A link or another app asked OpenText to lock \(file.path).")
        }
    }
}

/// At most one unsigned-URL dialog at a time; others arriving meanwhile are dropped.
public struct OneAtATime: Sendable {
    public private(set) var busy = false
    public init() {}
    public mutating func begin() -> Bool {
        if busy { return false }
        busy = true
        return true
    }
    public mutating func end() { busy = false }
}

/// External-change check before writing: compare the modification date seen at load / last save.
public enum FileChangeCheck {
    public static func hasChanged(recorded: Date?, current: Date?) -> Bool {
        guard let recorded else { return false }       // nothing recorded (new session): don't block
        guard let current else { return true }         // file vanished
        return recorded != current
    }
}

/// How a text file was stored: its encoding and whether it started with a byte order mark.
public struct TextFormat: Equatable, Sendable {
    public var encoding: String.Encoding
    public var hasBOM: Bool
    public init(encoding: String.Encoding, hasBOM: Bool = false) { self.encoding = encoding; self.hasBOM = hasBOM }
    public static let utf8 = TextFormat(encoding: .utf8)
}

/// Detect the encoding on load and write back in it, BOM included.
public enum TextCoding {
    public static func decode(_ data: Data) -> (String, TextFormat)? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let s = String(data: data.dropFirst(3), encoding: .utf8) else { return nil }
            return (s, TextFormat(encoding: .utf8, hasBOM: true))
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            let enc: String.Encoding = bytes[0] == 0xFF ? .utf16LittleEndian : .utf16BigEndian
            if let s = String(data: data.dropFirst(2), encoding: enc) { return (s, TextFormat(encoding: enc, hasBOM: true)) }
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
        if let s = String(data: data, encoding: .isoLatin1) { return (s, TextFormat(encoding: .isoLatin1)) }
        return nil
    }

    /// Bytes in the file's own encoding with its BOM; nil when the text no longer fits that encoding.
    public static func encode(_ text: String, as format: TextFormat) -> Data? {
        guard let body = text.data(using: format.encoding, allowLossyConversion: false) else { return nil }
        guard format.hasBOM else { return body }
        switch format.encoding {
        case .utf8: return Data([0xEF, 0xBB, 0xBF]) + body
        case .utf16LittleEndian: return Data([0xFF, 0xFE]) + body
        case .utf16BigEndian: return Data([0xFE, 0xFF]) + body
        default: return body
        }
    }

    /// True when saving would force a different encoding (the user must agree first).
    public static func needsEncodingChange(_ text: String, format: TextFormat) -> Bool {
        encode(text, as: format) == nil
    }
}

/// Writes through a temp file in the same folder and swaps it in, so Finder tags and other extended
/// attributes of the existing file survive.
public enum SafeWrite {
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let staged = url.deletingLastPathComponent().appendingPathComponent(".opentext-\(UUID().uuidString).tmp")
        do {
            try data.write(to: staged)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: url)
            }
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
    }
}

/// What to do with the recovery public key before locking. Compares the keys themselves, not fingerprints.
public enum PinDecision: Equatable, Sendable {
    case createNew                 // no key anywhere: first lock generates one
    case adopt(String)             // settings has a key never pinned: pin it
    case restore(String)           // settings lost the key: put the pinned one back
    case ok(String)
    case mismatch(pinned: String, current: String)
}

public enum PinPolicy {
    public static func evaluate(pinned: String?, current: String?) -> PinDecision {
        switch (pinned, current) {
        case (nil, nil): return .createNew
        case (nil, let c?): return .adopt(c)
        case (let p?, nil): return .restore(p)
        case (let p?, let c?): return p == c ? .ok(p) : .mismatch(pinned: p, current: c)
        }
    }
}
