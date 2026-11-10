import ArgumentParser
import Foundation
import OpenTextKit

struct JSONFlag: ParsableArguments {
    @Flag(name: .long, help: "Print machine-readable JSON.") var json = false
}

func jsonString(_ o: Any) -> String {
    let d = (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return String(decoding: d, as: UTF8.self)
}

func password(confirm: Bool) throws -> String {
    if let p = ProcessInfo.processInfo.environment["OPENTEXT_PASSWORD"], !p.isEmpty { return p }
    guard let a = getpass("Password: ") else { throw ToolError("No password given (set OPENTEXT_PASSWORD).") }
    let first = String(cString: a)
    if confirm {
        guard let b = getpass("Confirm password: "), String(cString: b) == first else { throw ToolError("Passwords do not match.") }
    }
    guard !first.isEmpty else { throw ToolError("Password is empty.") }
    return first
}

/// Runs a shared tool, prints plain or JSON output, maps errors to stderr + exit 1.
/// A batch convert where some inputs failed still prints the successes, lists each failure on stderr, and exits 1.
func runTool(_ tool: String, _ args: [String: Any], json: Bool) throws {
    let r: [String: Any]
    do {
        r = try OpenTextTools.call(tool, args, trusted: true)
    } catch {
        let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        FileHandle.standardError.write(Data((msg + "\n").utf8))
        if json { print(jsonString(["error": msg])) }
        throw ExitCode(1)
    }
    if json { print(jsonString(r)) }
    else if let t = r["text"] as? String { print(t) }
    else if let o = r["outputs"] as? [String] { o.forEach { print($0) } }
    else if let p = r["path"] as? String { print(p) }
    else if let list = r["formats"] as? [[String: Any]] {
        for f in list { print("\(f["format"] as? String ?? "?"): \((f["targets"] as? [String] ?? []).joined(separator: ", "))") }
    } else if let t = r["targets"] as? [String] { print(t.joined(separator: ", ")) }
    let failures = (r["results"] as? [[String: Any]] ?? []).compactMap { x in
        (x["error"] as? String).map { "\(x["input"] as? String ?? "?"): \($0)" }
    }
    if !failures.isEmpty {
        FileHandle.standardError.write(Data((failures.joined(separator: "\n") + "\n").utf8))
        throw ExitCode(1)
    }
}

@main
struct OpenText: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "opentext",
        abstract: "Convert, create, combine, lock and unlock documents. Everything the OpenText app does.",
        subcommands: [Convert.self, Text.self, New.self, Combine.self, ImagesToPDF.self, Lock.self, Unlock.self, Formats.self])

    struct Convert: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Convert files to another format.")
        @Argument(help: "Input files.") var files: [String]
        @Option(name: .long, help: "Target format (txt, md, pdf, png, ...).") var to: String
        @Option(name: .long, help: "Output path (single input only).") var out: String?
        @Flag(name: .long, help: "Replace existing output instead of picking 'name 2.ext'.") var overwrite = false
        @Flag(name: .long, help: "Skip OCR for scanned PDF pages.") var noOcr = false
        @OptionGroup var j: JSONFlag
        func run() throws {
            var a: [String: Any] = ["files": files, "to": to, "overwrite": overwrite, "ocr": !noOcr]
            if let out { a["out"] = out }
            try runTool("convert", a, json: j.json)
        }
    }

    struct Text: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the plain text of a document or PDF.")
        @Argument var file: String
        @Flag(name: .long, help: "Skip OCR for scanned PDF pages.") var noOcr = false
        @OptionGroup var j: JSONFlag
        func run() throws { try runTool("extract_text", ["file": file, "ocr": !noOcr], json: j.json) }
    }

    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create an empty txt, md, csv or html file.")
        @Argument(help: "txt, md, csv or html.") var format: String
        @Argument(help: "Base name (default Untitled).") var name: String?
        @Option(name: .customLong("in"), help: "Folder (default: default folder from settings).") var folder: String?
        @OptionGroup var j: JSONFlag
        func run() throws {
            var a: [String: Any] = ["format": format]
            if let name { a["name"] = name }
            if let folder { a["folder"] = folder }
            try runTool("create_file", a, json: j.json)
        }
    }

    struct Combine: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Combine PDFs into one.")
        @Argument var files: [String]
        @Option(name: .long) var out: String
        @OptionGroup var j: JSONFlag
        func run() throws { try runTool("combine_pdfs", ["files": files, "out": out], json: j.json) }
    }

    struct ImagesToPDF: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "images-to-pdf", abstract: "Combine images into one PDF.")
        @Argument var files: [String]
        @Option(name: .long) var out: String
        @OptionGroup var j: JSONFlag
        func run() throws { try runTool("images_to_pdf", ["files": files, "out": out], json: j.json) }
    }

    struct Lock: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Encrypt a file to .otlock. Password from OPENTEXT_PASSWORD or a prompt.")
        @Argument var file: String
        @Option(name: .long, help: "Output path.") var out: String?
        @Flag(name: .long, help: "Move the original to the Trash.") var removeOriginal = false
        @OptionGroup var j: JSONFlag
        func run() throws {
            var a: [String: Any] = ["file": file, "remove_original": removeOriginal]
            if let out { a["out"] = out }
            do { a["password"] = try password(confirm: true) } catch { try fail(error, j.json) }
            try runTool("lock_file", a, json: j.json)
        }
    }

    struct Unlock: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Decrypt a .otlock file with the password (OPENTEXT_PASSWORD or prompt) or --recovery-key.")
        @Argument var file: String
        @Option(name: .long, help: "Recovery key (ABCD-EFGH-...).") var recoveryKey: String?
        @Option(name: .long, help: "Output path.") var out: String?
        @OptionGroup var j: JSONFlag
        func run() throws {
            var a: [String: Any] = ["file": file]
            if let out { a["out"] = out }
            if let recoveryKey { a["recovery_key"] = recoveryKey }
            else { do { a["password"] = try password(confirm: false) } catch { try fail(error, j.json) } }
            try runTool("unlock_file", a, json: j.json)
        }
    }

    struct Formats: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List formats and conversion targets.")
        @Argument var format: String?
        @OptionGroup var j: JSONFlag
        func run() throws {
            var a = [String: Any]()
            if let format { a["format"] = format }
            try runTool("list_formats", a, json: j.json)
        }
    }
}

func fail(_ error: Error, _ json: Bool) throws -> Never {
    let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    if json { print(jsonString(["error": msg])) }
    throw ExitCode(1)
}
