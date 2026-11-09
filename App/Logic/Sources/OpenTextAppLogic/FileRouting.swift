import Foundation

public enum FileKind: Equatable, Sendable {
    case text, markdown, pdf, image, locked, unsupported
}

public enum FileRouting {
    public static func kind(for url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "txt", "text", "csv", "json": return .text
        case "md", "markdown": return .markdown
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "webp": return .image
        case "otlock": return .locked
        default: return .unsupported
        }
    }

    /// Canonical lowercase extension used across the UI boundary ("jpeg" -> "jpg", "markdown" -> "md").
    public static func canonicalExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg": return "jpg"
        case "markdown": return "md"
        case "tif": return "tiff"
        case "htm": return "html"
        case "text": return "txt"
        case let e: return e
        }
    }

    /// Targets offered in the Finder right-click submenu (png/jpg/pdf/md/txt only).
    public static let finderMenuFormats = ["pdf", "md", "txt", "png", "jpg"]
    /// Keeps only the formats shown in the Finder submenu, in menu order.
    public static func finderFilter(_ targets: [String]) -> [String] {
        finderMenuFormats.filter { targets.contains($0) }
    }
}

public enum PasswordRules {
    public static let minimumLength = 8
    public enum Problem: Equatable, Sendable { case tooShort, mismatch }
    public static func validate(password: String, confirm: String) -> Problem? {
        if password.count < minimumLength { return .tooShort }
        if password != confirm { return .mismatch }
        return nil
    }
}
