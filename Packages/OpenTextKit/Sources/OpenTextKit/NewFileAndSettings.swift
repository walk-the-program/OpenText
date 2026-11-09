import Foundation

public enum NewFile {
    /// Creates an empty file (html gets a minimal skeleton) with a unique name. Formats: txt, md, csv, html.
    public static func create(_ format: DocFormat, name: String = "Untitled", in folder: URL) throws -> URL {
        let content: String
        switch format {
        case .txt, .md, .csv: content = ""
        case .html: content = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title></title></head>\n<body>\n</body></html>\n"
        default: throw OpenTextError.writeFailed(folder.appendingPathComponent("\(name).\(format.fileExtension)"))
        }
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let target = Files.unique(folder.appendingPathComponent("\(safeName.isEmpty ? "Untitled" : safeName).\(format.fileExtension)"))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try content.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            throw OpenTextError.writeFailed(target)
        }
        return target
    }
}

public struct OpenTextSettings: Codable, Sendable {
    public var defaultFolder: String = "~/Desktop"
    public var hotkey: String = "ctrl+opt+n"
    public var recoveryPublicKey: String? = nil
    public var useTouchID: Bool = true
    public var txtMonospace: Bool = false
    public var lastNewFileFormat: String = "md"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OpenTextSettings()
        defaultFolder = try c.decodeIfPresent(String.self, forKey: .defaultFolder) ?? d.defaultFolder
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? d.hotkey
        recoveryPublicKey = try c.decodeIfPresent(String.self, forKey: .recoveryPublicKey)
        useTouchID = try c.decodeIfPresent(Bool.self, forKey: .useTouchID) ?? d.useTouchID
        txtMonospace = try c.decodeIfPresent(Bool.self, forKey: .txtMonospace) ?? d.txtMonospace
        lastNewFileFormat = try c.decodeIfPresent(String.self, forKey: .lastNewFileFormat) ?? d.lastNewFileFormat
    }

    /// `$OPENTEXT_SETTINGS_PATH` if set (used by tests), else ~/Library/Application Support/OpenText/settings.json.
    public static var fileURL: URL {
        if let p = ProcessInfo.processInfo.environment["OPENTEXT_SETTINGS_PATH"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenText/settings.json")
    }

    /// Defaults when the file is missing or unreadable.
    public static func load() -> OpenTextSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(OpenTextSettings.self, from: data) else { return OpenTextSettings() }
        return s
    }

    public func save() throws {
        let url = Self.fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// `defaultFolder` with "~" expanded. Added for CLI/MCP/app convenience.
    public var defaultFolderURL: URL {
        URL(fileURLWithPath: (defaultFolder as NSString).expandingTildeInPath, isDirectory: true)
    }
}
