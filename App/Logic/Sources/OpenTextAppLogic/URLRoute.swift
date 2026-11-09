import Foundation

/// Actions carried by opentext:// URLs. The sandboxed Finder extension never writes files;
/// it builds these URLs and the app performs the work.
public enum AppRoute: Equatable, Sendable {
    case new(format: String, dir: URL?)
    case convert(to: String, file: URL)
    case lock(file: URL)
}

public enum RouteError: Error, Equatable {
    case notOurScheme, unknownAction(String), badFormat(String), missingParameter(String), badPath(String)
}

public enum URLRouter {
    public static let scheme = "opentext"
    public static let newFormats: Set<String> = ["txt", "md", "csv", "html"]
    public static let convertFormats: Set<String> =
        ["txt", "md", "rtf", "html", "docx", "pdf", "png", "jpg", "heic", "tiff", "gif", "webp"]

    public static func parse(_ url: URL) throws -> AppRoute {
        guard url.scheme?.lowercased() == scheme else { throw RouteError.notOurScheme }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func value(_ name: String) -> String? {
            comps?.queryItems?.first(where: { $0.name == name })?.value
        }
        let action = (url.host ?? "").lowercased()
        switch action {
        case "new":
            let fmt = FileRouting.canonicalExtension(value("format") ?? "md")
            guard newFormats.contains(fmt) else { throw RouteError.badFormat(fmt) }
            let dir = try value("dir").map { try path($0) }
            return .new(format: fmt, dir: dir)
        case "convert":
            guard let to = value("to") else { throw RouteError.missingParameter("to") }
            let fmt = FileRouting.canonicalExtension(to)
            guard convertFormats.contains(fmt) else { throw RouteError.badFormat(fmt) }
            guard let file = value("file") else { throw RouteError.missingParameter("file") }
            return .convert(to: fmt, file: try path(file))
        case "lock":
            guard let file = value("file") else { throw RouteError.missingParameter("file") }
            return .lock(file: try path(file))
        default:
            throw RouteError.unknownAction(action)
        }
    }

    /// Absolute or ~ paths only; ".." is resolved away.
    static func path(_ raw: String) throws -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw RouteError.badPath(raw) }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    private static func build(_ action: String, _ items: [URLQueryItem]) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = action
        c.queryItems = items
        return c.url!
    }

    public static func newURL(format: String, dir: URL?) -> URL {
        var items = [URLQueryItem(name: "format", value: format)]
        if let dir { items.append(URLQueryItem(name: "dir", value: dir.path)) }
        return build("new", items)
    }
    public static func convertURL(to: String, file: URL) -> URL {
        build("convert", [URLQueryItem(name: "to", value: to), URLQueryItem(name: "file", value: file.path)])
    }
    public static func lockURL(file: URL) -> URL {
        build("lock", [URLQueryItem(name: "file", value: file.path)])
    }
}
