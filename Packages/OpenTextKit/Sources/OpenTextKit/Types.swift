import Foundation

public enum DocFormat: String, CaseIterable, Codable, Sendable {
    case txt, md, rtf, html, docx, doc, odt, csv, json, pdf, png, jpg, heic, tiff, gif, webp, otlock

    /// By file extension, case-insensitive; "jpeg"→jpg, "markdown"→md, "htm"→html.
    public init?(url: URL) {
        self.init(name: url.pathExtension)
    }

    /// By name or extension (same aliases as `init(url:)`, plus "tif", "text"). Added for CLI/MCP use.
    public init?(name: String) {
        switch name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) {
        case "txt", "text": self = .txt
        case "md", "markdown": self = .md
        case "rtf": self = .rtf
        case "html", "htm": self = .html
        case "docx": self = .docx
        case "doc": self = .doc
        case "odt": self = .odt
        case "csv": self = .csv
        case "json": self = .json
        case "pdf": self = .pdf
        case "png": self = .png
        case "jpg", "jpeg": self = .jpg
        case "heic": self = .heic
        case "tiff", "tif": self = .tiff
        case "gif": self = .gif
        case "webp": self = .webp
        case "otlock": self = .otlock
        default: return nil
        }
    }

    public var fileExtension: String { rawValue }

    public var isText: Bool {
        switch self {
        case .txt, .md, .rtf, .html, .docx, .doc, .odt, .csv, .json: return true
        default: return false
        }
    }

    public var isImage: Bool {
        switch self {
        case .png, .jpg, .heic, .tiff, .gif, .webp: return true
        default: return false
        }
    }
}

public struct ConversionOptions: Sendable {
    public var overwrite = false
    public var imageQuality = 0.9
    public var ocr = true
    public init() {}
}

public enum OpenTextError: Error, LocalizedError, Equatable {
    case unsupportedConversion(from: DocFormat, to: DocFormat)
    case unreadable(URL)
    case writeFailed(URL)
    case wrongPassword
    case corruptLockedFile
    case notLocked
    case noRecoveryKeyConfigured
    case invalidRecoveryKey
    case originalNotRemoved(original: URL, locked: URL)
    case fileTooLarge(URL)
    case timedOut(URL)
    case destinationNotAllowed(URL, String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedConversion(from, to): return "Cannot convert \(from.rawValue) to \(to.rawValue)."
        case let .unreadable(url): return "Cannot read \(url.path)."
        case let .writeFailed(url): return "Cannot write \(url.path)."
        case .wrongPassword: return "Wrong password."
        case .corruptLockedFile: return "The locked file is damaged or not a valid OpenText locked file."
        case .notLocked: return "That file is not a locked OpenText file."
        case .noRecoveryKeyConfigured: return "This file has no recovery key slot."
        case .invalidRecoveryKey: return "The recovery key does not unlock this file."
        case let .originalNotRemoved(original, locked): return "The locked file was written to \(locked.path), but the original could not be moved to the Trash: \(original.path)."
        case let .timedOut(url): return "Converting \(url.lastPathComponent) took longer than 60 seconds and was stopped."
        case let .fileTooLarge(url): return "\(url.lastPathComponent) is larger than 2 GB, which is more than OpenText can lock or unlock."
        case let .destinationNotAllowed(url, why): return "Refusing to write \(url.path): \(why)."
        }
    }
}

/// Error with a plain message, used by `OpenTextTools` for bad arguments.
public struct ToolError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

// MARK: - File helpers

enum Files {
    /// "name.ext" → "name 2.ext", "name 3.ext"… if taken.
    static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// Runs `body` with a fresh temporary directory, removed afterwards.
    static func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("opentext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// Throws unless `dest` is a legal output for `format`: not an existing directory, extension matches the format.
    static func checkDestination(_ dest: URL, format: DocFormat) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir), isDir.boolValue {
            throw OpenTextError.destinationNotAllowed(dest, "it is a folder")
        }
        guard DocFormat(url: dest) == format else {
            throw OpenTextError.destinationNotAllowed(dest, "the file extension must be .\(format.fileExtension)")
        }
    }

    /// Moves `tmp` to `dest`. Never removes a directory. An existing file is replaced atomically
    /// (staged in the destination folder, then replaceItemAt), so a failure keeps the old file.
    static func place(_ tmp: URL, _ dest: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: dest.path, isDirectory: &isDir)
        if exists, isDir.boolValue { throw OpenTextError.destinationNotAllowed(dest, "it is a folder") }
        do {
            if exists {
                let staged = dest.deletingLastPathComponent().appendingPathComponent(".opentext-\(UUID().uuidString).tmp")
                do {
                    try fm.copyItem(at: tmp, to: staged)
                    _ = try fm.replaceItemAt(dest, withItemAt: staged)
                } catch {
                    try? fm.removeItem(at: staged)
                    throw error
                }
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            throw OpenTextError.writeFailed(dest)
        }
    }

    static func readText(_ url: URL) throws -> String {
        guard let data = FileManager.default.contents(atPath: url.path) else { throw OpenTextError.unreadable(url) }
        return decode(data)
    }

    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        if data.count >= 2, (data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF),
           let s = String(data: data, encoding: .utf16) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func writeText(_ s: String, to url: URL) throws {
        do { try s.write(to: url, atomically: true, encoding: .utf8) } catch { throw OpenTextError.writeFailed(url) }
    }
}
