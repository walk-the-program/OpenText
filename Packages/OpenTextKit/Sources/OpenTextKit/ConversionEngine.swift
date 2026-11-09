import AppKit
import Foundation
import PDFKit

public struct ConversionEngine: Sendable {
    public init() {}

    private static let richTargets: [DocFormat] = [.txt, .md, .rtf, .html, .docx, .doc, .odt, .pdf]
    private static let table: [DocFormat: [DocFormat]] = {
        var t = [DocFormat: [DocFormat]]()
        for f in [DocFormat.txt, .md, .rtf, .html, .docx, .doc, .odt] {
            t[f] = richTargets.filter { $0 != f }
        }
        t[.csv] = [.txt, .pdf]
        t[.json] = [.txt, .pdf]
        t[.pdf] = [.txt, .md, .png, .jpg]
        for f in [DocFormat.png, .jpg, .heic, .tiff, .gif, .webp] {
            t[f] = [.jpg, .png, .tiff, .heic, .pdf].filter { $0 != f }
        }
        return t
    }()

    public func targets(from: DocFormat) -> [DocFormat] { Self.table[from] ?? [] }

    // MARK: convert

    /// Writes next to the input unless `output` is given. Never overwrites unless options.overwrite;
    /// picks "name 2.ext", "name 3.ext"… Returns the written URL(s) (pdf→png returns one per page).
    public func convert(_ input: URL, to: DocFormat, output: URL? = nil, options: ConversionOptions = .init()) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: input.path), let from = DocFormat(url: input) else {
            throw OpenTextError.unreadable(input)
        }
        guard targets(from: from).contains(to) else { throw OpenTextError.unsupportedConversion(from: from, to: to) }
        let base = output ?? input.deletingPathExtension().appendingPathExtension(to.fileExtension)

        if from == .pdf, to.isImage {
            return try pdfToImages(input, to: to, base: base, explicit: output != nil, options: options)
        }

        let dest = options.overwrite ? base : Files.unique(base)
        if dest.standardizedFileURL == input.standardizedFileURL { throw OpenTextError.writeFailed(dest) }
        try Files.withTempDir { dir in
            let tmp = dir.appendingPathComponent("out.\(to.fileExtension)")
            try produce(from: from, to: to, input: input, tmp: tmp, dir: dir, options: options)
            try Files.place(tmp, dest)
        }
        return [dest]
    }

    private func produce(from: DocFormat, to: DocFormat, input: URL, tmp: URL, dir: URL, options: ConversionOptions) throws {
        switch to {
        case .txt:
            try Files.writeText(try extractText(input, ocr: options.ocr), to: tmp)
        case .md:
            if from == .pdf {
                try Files.writeText(try PDFText.markdown(input, ocr: options.ocr), to: tmp)
            } else {
                try Files.writeText(try extractText(input, ocr: options.ocr), to: tmp)
            }
        case .html:
            switch from {
            case .txt:
                let text = try Files.readText(input)
                try Files.writeText(MD.document(body: MD.plainToHTML(text), title: input.deletingPathExtension().lastPathComponent), to: tmp)
            case .md:
                let md = try Files.readText(input)
                try Files.writeText(MD.document(body: MD.toHTML(md), title: input.deletingPathExtension().lastPathComponent), to: tmp)
            default:
                try Textutil.convert(input, to: "html", output: tmp)
            }
        case .rtf, .docx, .doc, .odt:
            if from == .md {
                let html = dir.appendingPathComponent("in.html")
                let md = try Files.readText(input)
                try Files.writeText(MD.document(body: MD.toHTML(md), title: input.deletingPathExtension().lastPathComponent), to: html)
                try Textutil.convert(html, to: to.rawValue, output: tmp)
            } else {
                try Textutil.convert(input, to: to.rawValue, output: tmp)
            }
        case .pdf:
            if from.isImage {
                _ = try ImageTools.imagesToPDF([input], output: tmp)
            } else {
                let attributed = try attributedString(for: input, from: from, dir: dir)
                try PDFWriter.write(attributed, to: tmp)
            }
        case .png, .jpg, .heic, .tiff:
            let image = try ImageTools.load(input)
            try ImageTools.write(image, as: to, to: tmp, quality: options.imageQuality)
        default:
            throw OpenTextError.unsupportedConversion(from: from, to: to)
        }
    }

    private func attributedString(for input: URL, from: DocFormat, dir: URL) throws -> NSAttributedString {
        switch from {
        case .txt, .csv, .json:
            let text = try Files.readText(input)
            let mono = from != .txt
            let font = mono ? (NSFont(name: "Menlo", size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .regular))
                            : (NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12))
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 6
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style])
        default:
            let rtf = dir.appendingPathComponent("render.rtf")
            if from == .md {
                let html = dir.appendingPathComponent("render.html")
                try Files.writeText(MD.document(body: MD.toHTML(try Files.readText(input)), title: ""), to: html)
                try Textutil.convert(html, to: "rtf", output: rtf)
            } else {
                try Textutil.convert(input, to: "rtf", output: rtf)
            }
            guard let data = try? Data(contentsOf: rtf),
                  let s = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { throw OpenTextError.unreadable(input) }
            return s
        }
    }

    private func pdfToImages(_ input: URL, to: DocFormat, base: URL, explicit: Bool, options: ConversionOptions) throws -> [URL] {
        guard let doc = PDFDocument(url: input), !doc.isLocked else { throw OpenTextError.unreadable(input) }
        let n = doc.pageCount
        guard n > 0 else { throw OpenTextError.unreadable(input) }
        let stem = base.deletingPathExtension()
        var written = [URL]()
        for i in 0..<n {
            guard let page = doc.page(at: i), let image = PDFText.render(page, scale: 2) else { throw OpenTextError.unreadable(input) }
            let target: URL = n == 1
                ? base
                : stem.deletingLastPathComponent().appendingPathComponent("\(stem.lastPathComponent)-\(i + 1).\(to.fileExtension)")
            let dest = options.overwrite ? target : Files.unique(target)
            try Files.withTempDir { dir in
                let tmp = dir.appendingPathComponent("page.\(to.fileExtension)")
                try ImageTools.write(image, as: to, to: tmp, quality: options.imageQuality)
                try Files.place(tmp, dest)
            }
            written.append(dest)
        }
        return written
    }

    // MARK: text

    public func extractText(_ input: URL, ocr: Bool = true) throws -> String {
        guard FileManager.default.fileExists(atPath: input.path), let from = DocFormat(url: input) else {
            throw OpenTextError.unreadable(input)
        }
        switch from {
        case .txt, .md, .csv, .json:
            return try Files.readText(input)
        case .rtf, .html, .docx, .doc, .odt:
            return try Files.withTempDir { dir in
                let out = dir.appendingPathComponent("out.txt")
                try Textutil.convert(input, to: "txt", output: out)
                return try Files.readText(out)
            }
        case .pdf:
            return try PDFText.extract(input, ocr: ocr)
        default:
            throw OpenTextError.unsupportedConversion(from: from, to: .txt)
        }
    }

    // MARK: PDF / images

    public func combinePDFs(_ inputs: [URL], output: URL) throws -> URL {
        guard !inputs.isEmpty else { throw OpenTextError.unreadable(output) }
        let merged = PDFDocument()
        for url in inputs {
            guard let doc = PDFDocument(url: url), !doc.isLocked else { throw OpenTextError.unreadable(url) }
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i)?.copy() as? PDFPage else { throw OpenTextError.unreadable(url) }
                merged.insert(page, at: merged.pageCount)
            }
        }
        let dest = Files.unique(output)
        try Files.withTempDir { dir in
            let tmp = dir.appendingPathComponent("out.pdf")
            guard merged.write(to: tmp) else { throw OpenTextError.writeFailed(dest) }
            try Files.place(tmp, dest)
        }
        return dest
    }

    public func imagesToPDF(_ inputs: [URL], output: URL) throws -> URL {
        let dest = Files.unique(output)
        try Files.withTempDir { dir in
            let tmp = dir.appendingPathComponent("out.pdf")
            _ = try ImageTools.imagesToPDF(inputs, output: tmp)
            try Files.place(tmp, dest)
        }
        return dest
    }

    // MARK: switchFormat

    /// Changes format in place for the title-bar chip: converts, then moves the original to the Trash.
    public func switchFormat(_ input: URL, to: DocFormat) throws -> URL {
        let out = try convert(input, to: to)
        guard let url = out.first else { throw OpenTextError.writeFailed(input) }
        do {
            try FileManager.default.trashItem(at: input, resultingItemURL: nil)
        } catch {
            throw OpenTextError.writeFailed(input)
        }
        return url
    }
}

// MARK: - textutil

enum Textutil {
    static func convert(_ input: URL, to format: String, output: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        var args = ["-convert", format, "-output", output.path]
        let ext = input.pathExtension.lowercased()
        if ["txt", "html", "htm"].contains(ext) { args += ["-inputencoding", "UTF-8"] }
        if ["txt", "html"].contains(format) { args += ["-encoding", "UTF-8"] }
        args.append(input.path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw OpenTextError.unreadable(input) }
        p.waitUntilExit()
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw OpenTextError.unreadable(input)
        }
    }
}

// MARK: - PDF text writing

enum PDFWriter {
    static func write(_ text: NSAttributedString, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw OpenTextError.writeFailed(url) }
        let setter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let area = box.insetBy(dx: 72, dy: 72)
        var location = 0
        let length = text.length
        repeat {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: location, length: 0), CGPath(rect: area, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            location += visible.length
        } while location < length
        ctx.closePDF()
    }
}
