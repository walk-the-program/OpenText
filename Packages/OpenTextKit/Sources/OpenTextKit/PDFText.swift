import AppKit
import Foundation
import PDFKit
import Vision

enum PDFText {
    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = NSSize(width: (rotated ? box.height : box.width) * scale, height: (rotated ? box.width : box.height) * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func ocr(_ page: PDFPage) -> String {
        guard let image = render(page, scale: 2) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { return "" }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func pages(_ url: URL, ocr: Bool) throws -> [String] {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { throw OpenTextError.unreadable(url) }
        return (0..<doc.pageCount).map { i in
            guard let page = doc.page(at: i) else { return "" }
            var t = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty, ocr { t = PDFText.ocr(page).trimmingCharacters(in: .whitespacesAndNewlines) }
            return t
        }
    }

    static func extract(_ url: URL, ocr: Bool) throws -> String {
        try pages(url, ocr: ocr).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func markdown(_ url: URL, ocr: Bool) throws -> String {
        try pages(url, ocr: ocr).filter { !$0.isEmpty }.map(paragraphs).joined(separator: "\n\n")
    }

    /// Rejoins hard-wrapped lines: a line ends its paragraph if it ends a sentence and is not full width.
    static func paragraphs(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let maxLen = Double(lines.map(\.count).max() ?? 0)
        var paras = [String]()
        var current = ""
        func flush() { if !current.isEmpty { paras.append(current); current = "" } }
        for line in lines {
            if line.isEmpty { flush(); continue }
            let isItem = line.firstMatch(of: /^([-•*]|\d+[.)])\s/) != nil
            if isItem { flush() }
            current = current.isEmpty ? line : current + " " + line
            if isItem { flush(); continue }
            if let last = line.last, ".!?:;".contains(last), Double(line.count) < maxLen * 0.85 { flush() }
        }
        flush()
        return paras.joined(separator: "\n\n")
    }
}
