import Foundation
import OpenTextKit

public enum FileKind: Equatable, Sendable {
    case text, markdown, pdf, image, richText, locked, unsupported
}

public enum FileRouting {
    public static func kind(for url: URL) -> FileKind {
        guard let f = DocFormat(url: url) else { return .unsupported }
        if f == .otlock { return .locked }
        if f == .pdf { return .pdf }
        if f == .md { return .markdown }
        if DocFormat.plainTextFormats.contains(f) { return .text }
        if DocFormat.imageFormats.contains(f) { return .image }
        if richTextFormats.contains(f) { return .richText }
        return .unsupported
    }

    /// Opened read-only in the rich text viewer.
    public static let richTextFormats: Set<DocFormat> = [.rtf, .rtfd, .docx, .doc, .odt, .html]

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
