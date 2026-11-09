import Foundation

/// Shared operation layer used by the `opentext` CLI and the `opentext-mcp` server (same names, same arguments).
/// Arguments and results are JSON-compatible dictionaries.
public enum OpenTextTools {
    public static let toolNames = ["convert", "extract_text", "create_file", "combine_pdfs", "images_to_pdf", "list_formats", "lock_file", "unlock_file"]

    private static func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": props, "required": required, "additionalProperties": false]
    }
    private static var s: [String: Any] { ["type": "string"] }
    private static var b: [String: Any] { ["type": "boolean"] }
    private static func arr(_ d: String) -> [String: Any] { ["type": "array", "items": ["type": "string"], "description": d, "minItems": 1] }
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }

    /// MCP tool definitions: name, description, inputSchema (JSON Schema).
    public static func toolDefinitions() -> [[String: Any]] {
        let fmt = DocFormat.allCases.map(\.rawValue)
        return [
            ["name": "convert", "description": "Convert one or more files to another format. Writes next to the input unless out is given; never overwrites an existing file (picks 'name 2.ext'). pdf to png/jpg writes one image per page. Returns written paths.",
             "inputSchema": obj(["files": arr("Input file paths"), "to": ["type": "string", "enum": fmt, "description": "Target format"],
                                 "out": str("Output path (single input only)"), "ocr": ["type": "boolean", "description": "OCR scanned PDF pages (default true)"]],
                                required: ["files", "to"])],
            ["name": "extract_text", "description": "Extract plain text (words only) from txt, md, rtf, html, docx, doc, odt or pdf. Scanned PDF pages use on-device OCR unless ocr is false.",
             "inputSchema": obj(["file": str("Input file path"), "ocr": b], required: ["file"])],
            ["name": "create_file", "description": "Create an empty txt, md, csv or html file with a unique name. Folder defaults to the OpenText default folder setting.",
             "inputSchema": obj(["format": ["type": "string", "enum": ["txt", "md", "csv", "html"]], "name": str("Base name, default Untitled"), "folder": str("Destination folder")], required: ["format"])],
            ["name": "combine_pdfs", "description": "Combine PDFs, in order, into one PDF.",
             "inputSchema": obj(["files": arr("PDF paths"), "out": str("Output PDF path")], required: ["files", "out"])],
            ["name": "images_to_pdf", "description": "Combine images (png, jpg, heic, tiff, gif, webp), in order, into one PDF with one page per image.",
             "inputSchema": obj(["files": arr("Image paths"), "out": str("Output PDF path")], required: ["files", "out"])],
            ["name": "list_formats", "description": "List supported formats and what each converts to. Pass format for one entry.",
             "inputSchema": obj(["format": s])],
            ["name": "lock_file", "description": "Encrypt any file into a .otlock file (AES-256-GCM, PBKDF2 600k). Adds the recovery slot from the recovery public key in settings. The original is kept.",
             "inputSchema": obj(["file": str("File to lock"), "password": s, "out": str("Output path")], required: ["file", "password"])],
            ["name": "unlock_file", "description": "Decrypt a .otlock file with the password or the recovery key. Restores the original file name.",
             "inputSchema": obj(["file": str("The .otlock file"), "password": s, "recovery_key": str("Recovery key string, e.g. ABCD-EFGH-..."), "out": str("Output path")], required: ["file"])],
        ]
    }

    // MARK: argument access

    static func url(_ p: String) -> URL { URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
    /// Strict path parsing for untrusted callers: expands "~", rejects relative paths.
    static func absoluteURL(_ p: String) throws -> URL {
        let e = (p as NSString).expandingTildeInPath
        guard e.hasPrefix("/") else { throw ToolError("Path must be absolute (or start with ~): \(p)") }
        return URL(fileURLWithPath: e)
    }
    static func string(_ a: [String: Any], _ k: String) -> String? { (a[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    static func bool(_ a: [String: Any], _ k: String, default d: Bool) -> Bool { (a[k] as? Bool) ?? d }
    static func required(_ a: [String: Any], _ k: String) throws -> String {
        guard let v = string(a, k) else { throw ToolError("Missing required argument '\(k)'.") }
        return v
    }
    static func files(_ a: [String: Any]) throws -> [URL] {
        guard let list = a["files"] as? [String], !list.isEmpty else { throw ToolError("Missing required argument 'files'.") }
        return list.map(url)
    }
    static func format(_ name: String) throws -> DocFormat {
        guard let f = DocFormat(name: name) else { throw ToolError("Unknown format '\(name)'.") }
        return f
    }

    // MARK: dispatch

    /// `trusted` is true only for the human-run CLI: relative paths allowed, `remove_original` and `recovery_public_key` honored.
    /// The MCP server uses the default (untrusted): absolute or "~" paths only, locks always use the settings key and never delete the original.
    public static func call(_ name: String, _ a: [String: Any], trusted: Bool = false) throws -> [String: Any] {
        let engine = ConversionEngine()
        let url: (String) throws -> URL = { trusted ? OpenTextTools.url($0) : try OpenTextTools.absoluteURL($0) }
        func files(_ a: [String: Any]) throws -> [URL] {
            guard let list = a["files"] as? [String], !list.isEmpty else { throw ToolError("Missing required argument 'files'.") }
            return try list.map(url)
        }
        switch name {
        case "convert":
            let inputs = try files(a)
            let to = try format(try required(a, "to"))
            let out = try string(a, "out").map(url)
            if out != nil, inputs.count > 1 { throw ToolError("'out' can only be used with a single input file.") }
            var opts = ConversionOptions()
            opts.overwrite = trusted && bool(a, "overwrite", default: false)
            opts.ocr = bool(a, "ocr", default: true)
            var results = [[String: Any]]()
            var all = [String]()
            for f in inputs {
                let written = try engine.convert(f, to: to, output: out, options: opts).map(\.path)
                results.append(["input": f.path, "outputs": written])
                all += written
            }
            return ["outputs": all, "results": results]
        case "extract_text":
            return ["text": try engine.extractText(try url(try required(a, "file")), ocr: bool(a, "ocr", default: true))]
        case "create_file":
            let f = try format(try required(a, "format"))
            let folder = try string(a, "folder").map(url) ?? OpenTextSettings.load().defaultFolderURL
            return ["path": try NewFile.create(f, name: string(a, "name") ?? "Untitled", in: folder).path]
        case "combine_pdfs":
            return ["path": try engine.combinePDFs(try files(a), output: try url(try required(a, "out"))).path]
        case "images_to_pdf":
            return ["path": try engine.imagesToPDF(try files(a), output: try url(try required(a, "out"))).path]
        case "list_formats":
            func entry(_ f: DocFormat) -> [String: Any] {
                ["format": f.rawValue, "extension": f.fileExtension,
                 "kind": f.isText ? "text" : f.isImage ? "image" : f == .pdf ? "pdf" : "other",
                 "targets": engine.targets(from: f).map(\.rawValue)]
            }
            if let n = string(a, "format") { return entry(try format(n)) }
            return ["formats": DocFormat.allCases.map(entry)]
        case "lock_file":
            let key = (trusted ? string(a, "recovery_public_key") : nil) ?? OpenTextSettings.load().recoveryPublicKey
            let out = try Locker.lock(try url(try required(a, "file")), password: try required(a, "password"), recoveryPublicKeyBase64: key,
                                      output: try string(a, "out").map(url), removeOriginal: trusted && bool(a, "remove_original", default: false))
            return ["path": out.path, "recovery": key != nil]
        case "unlock_file":
            let file = try url(try required(a, "file"))
            let out = try string(a, "out").map(url)
            if let rk = string(a, "recovery_key") {
                guard let key = RecoveryKey(displayString: rk) else { throw OpenTextError.invalidRecoveryKey }
                return ["path": try Locker.unlock(file, recoveryKey: key, output: out).path]
            }
            return ["path": try Locker.unlock(file, password: try required(a, "password"), output: out).path]
        default:
            throw ToolError("Unknown tool '\(name)'.")
        }
    }
}
