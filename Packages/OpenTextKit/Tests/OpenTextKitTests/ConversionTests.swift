import Foundation
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OpenTextKit

final class ConversionTests: TempTestCase {
    func read(_ u: URL) throws -> String { try String(contentsOf: u, encoding: .utf8) }

    func testFormatParsing() {
        XCTAssertEqual(DocFormat(url: URL(fileURLWithPath: "/a/B.JPEG")), .jpg)
        XCTAssertEqual(DocFormat(url: URL(fileURLWithPath: "/a/b.markdown")), .md)
        XCTAssertEqual(DocFormat(url: URL(fileURLWithPath: "/a/b.HTM")), .html)
        XCTAssertNil(DocFormat(url: URL(fileURLWithPath: "/a/b.xyz")))
        XCTAssertEqual(DocFormat(fileExtension: ".TIF"), .tiff); XCTAssertEqual(DocFormat(fileExtension: "text"), .txt)
        XCTAssertNil(DocFormat(fileExtension: ""))
        XCTAssertEqual(DocFormat.canonicalExtension("JPEG"), "jpg"); XCTAssertEqual(DocFormat.canonicalExtension("Xyz"), "xyz")
        XCTAssertEqual(DocFormat.textFormats.union(DocFormat.imageFormats).union([.pdf, .otlock]), Set(DocFormat.allCases))
        XCTAssertEqual(DocFormat.writableImageFormats, Set(DocFormat.imageFormats.filter { $0.imageUTType != nil }))
        XCTAssertEqual(DocFormat.imageFormats.subtracting(DocFormat.writableImageFormats), [.webp])
        XCTAssertTrue(DocFormat.docx.isText); XCTAssertTrue(DocFormat.heic.isImage); XCTAssertFalse(DocFormat.pdf.isText)
    }

    // txt <-> md <-> rtf <-> html
    func testTextRoundTrips() throws {
        let txt = try write("note.txt", "Hello world.\n\nSecond paragraph.\n")
        let md = try engine.convert(txt, to: .md)[0]
        XCTAssertEqual(md.lastPathComponent, "note.md")
        XCTAssertTrue(try read(md).contains("Second paragraph."))
        let backTxt = try engine.convert(md, to: .txt)[0]
        XCTAssertEqual(backTxt.lastPathComponent, "note 2.txt")
        let rtf = try engine.convert(txt, to: .rtf)[0]
        XCTAssertTrue(try read(rtf).hasPrefix("{\\rtf"))
        let fromRtf = try engine.convert(rtf, to: .txt)[0]
        XCTAssertTrue(try read(fromRtf).contains("Hello world."))
        let html = try engine.convert(txt, to: .html)[0]
        XCTAssertTrue(try read(html).contains("<p>Hello world.</p>"))
        let htmlToTxt = try engine.convert(html, to: .txt, options: { var o = ConversionOptions(); o.overwrite = true; return o }())[0]
        XCTAssertTrue(try read(htmlToTxt).contains("Second paragraph."))
        let htmlToRtf = try engine.convert(html, to: .rtf)[0]
        XCTAssertTrue(try read(htmlToRtf).hasPrefix("{\\rtf"))
        let rtfToHtml = try engine.convert(rtf, to: .html)[0]
        XCTAssertTrue(try read(rtfToHtml).lowercased().contains("hello world"))
        let rtfToMd = try engine.convert(rtf, to: .md)[0]
        XCTAssertTrue(try read(rtfToMd).contains("Hello world."))
        let htmlToMd = try engine.convert(html, to: .md)[0]
        XCTAssertTrue(try read(htmlToMd).contains("Hello world."))
    }

    func testRichSourcesToTxtAndMdWordsOnly() throws {
        for (ext, type) in [("docx", NSAttributedString.DocumentType.officeOpenXML), ("doc", .docFormat), ("odt", .openDocument), ("rtf", .rtf)] {
            let src = try richFixture(ext, type: type)
            for target in [DocFormat.txt, .md] {
                let out = try engine.convert(src, to: target, options: { var o = ConversionOptions(); o.overwrite = true; return o }())[0]
                let s = try read(out)
                XCTAssertTrue(s.contains("Quarterly Report"), "\(ext)->\(target)")
                XCTAssertTrue(s.contains("Alpha paragraph here."), "\(ext)->\(target)")
                XCTAssertTrue(s.contains("Beta paragraph there."), "\(ext)->\(target)")
                XCTAssertFalse(s.contains("{\\rtf") || s.contains("<w:") || s.contains("PK"), "\(ext)->\(target) leaked markup")
            }
        }
        let html = try write("page.html", "<html><head><title>T</title><style>p{color:red}</style></head><body><h1>Head</h1><p>Body <b>words</b>.</p></body></html>")
        let s = try read(try engine.convert(html, to: .txt)[0])
        XCTAssertTrue(s.contains("Head") && s.contains("Body words."))
        XCTAssertFalse(s.contains("<") || s.contains("color:red"))
    }

    func testMarkdownToHTMLPDFDocxRtfOdt() throws {
        let md = try write("doc.md", "# Title\n\nSome *emphasis*, **bold**, `code` and a [link](https://example.com).\n\n- one\n- two\n\n> quoted\n\n```\nlet x = 1\n```\n")
        let html = try read(try engine.convert(md, to: .html)[0])
        for needle in ["<h1>Title</h1>", "<em>emphasis</em>", "<strong>bold</strong>", "<code>code</code>", "<a href=\"https://example.com\">link</a>", "<li>one</li>", "<blockquote>", "<pre><code>"] {
            XCTAssertTrue(html.contains(needle), needle)
        }
        let pdf = try engine.convert(md, to: .pdf)[0]
        let text = PDFDocument(url: pdf)?.string ?? ""
        XCTAssertTrue(text.contains("Title") && text.contains("emphasis"), text)
        let docx = try engine.convert(md, to: .docx)[0]
        XCTAssertEqual(try Data(contentsOf: docx).prefix(2), Data("PK".utf8))
        let back = try read(try engine.convert(docx, to: .txt)[0])
        XCTAssertTrue(back.contains("Title") && back.contains("emphasis"))
        for t in [DocFormat.rtf, .doc, .odt] {
            let o = try engine.convert(md, to: t)[0]
            XCTAssertGreaterThan(try Data(contentsOf: o).count, 100, "\(t)")
        }
    }

    func testTxtAndRichToPDF() throws {
        let long = (1...200).map { "Line number \($0) of the long document." }.joined(separator: "\n")
        let txt = try write("long.txt", long)
        let pdf = try engine.convert(txt, to: .pdf)[0]
        let doc = PDFDocument(url: pdf)!
        XCTAssertGreaterThan(doc.pageCount, 1)
        XCTAssertTrue((doc.string ?? "").contains("Line number 200"))
        let rtf = try richFixture("rtf", type: .rtf)
        let p2 = try engine.convert(rtf, to: .pdf)[0]
        XCTAssertTrue((PDFDocument(url: p2)?.string ?? "").contains("Alpha paragraph"))
    }

    func testPDFToTextAndMarkdown() throws {
        let pdf = try textPDF()
        let t = try read(try engine.convert(pdf, to: .txt)[0])
        XCTAssertTrue(t.contains("First page words.") && t.contains("Second page words."))
        let m = try read(try engine.convert(pdf, to: .md)[0])
        XCTAssertTrue(m.contains("First page words.\n\nSecond page words."), m)
        XCTAssertEqual(try engine.extractText(pdf), t)
    }

    func testOCRFallback() throws {
        let scan = try scannedPDF()
        XCTAssertEqual((PDFDocument(url: scan)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines), "")
        let text = try engine.extractText(scan, ocr: true)
        XCTAssertTrue(text.lowercased().contains("hello"), "OCR got: \(text)")
        XCTAssertEqual(try engine.extractText(scan, ocr: false), "")
    }

    func testPDFToPNGPerPageAt2x() throws {
        let pdf = try textPDF()
        let outs = try engine.convert(pdf, to: .png)
        XCTAssertEqual(outs.map(\.lastPathComponent), ["two-1.png", "two-2.png"])
        let (w, h) = pixelSize(outs[0])
        XCTAssertEqual(w, 1224); XCTAssertEqual(h, 1584)
    }

    func testImageConversions() throws {
        let png = try imageFile("a.png", type: .png)
        let jpg = try imageFile("b.jpg", type: .jpeg)
        let heic = try imageFile("c.heic", type: .heic)
        let tiff = try imageFile("d.tiff", type: .tiff)
        let gif = try imageFile("e.gif", type: .gif)
        for src in [png, jpg, heic, tiff, gif] {
            for t in [DocFormat.jpg, .png, .pdf] where DocFormat(url: src) != t {
                let o = try engine.convert(src, to: t)[0]
                XCTAssertEqual(o.pathExtension, t.rawValue)
                if t == .pdf { XCTAssertEqual(PDFDocument(url: o)?.pageCount, 1) } else { XCTAssertEqual(pixelSize(o).0, 400) }
            }
        }
        XCTAssertEqual(pixelSize(try engine.convert(png, to: .heic)[0]).0, 400)
        XCTAssertEqual(pixelSize(try engine.convert(png, to: .tiff)[0]).0, 400)
        XCTAssertFalse(engine.targets(from: .png).contains(.webp))
        XCTAssertThrowsError(try engine.convert(png, to: .webp)) {
            XCTAssertEqual($0 as? OpenTextError, .unsupportedConversion(from: .png, to: .webp))
        }
    }

    func testWebPReadOnly() throws {
        XCTAssertEqual(Set(engine.targets(from: .webp)), [.jpg, .png, .tiff, .heic, .pdf])
        // Create a webp fixture only if ImageIO can (it normally cannot).
        let u = file("x.webp")
        if let d = CGImageDestinationCreateWithURL(u as CFURL, "org.webmproject.webp" as CFString, 1, nil) {
            CGImageDestinationAddImage(d, cgImage(), nil)
            if CGImageDestinationFinalize(d) { XCTAssertEqual(pixelSize(try engine.convert(u, to: .png)[0]).0, 400) }
        }
    }

    func noisyJPEG(_ name: String, width: Int, height: Int, orientation: Int? = nil) throws -> URL {
        var px = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 12345
        for y in 0..<height { for x in 0..<width {
            seed = seed &* 1664525 &+ 1013904223
            let i = (y * width + x) * 4
            px[i] = UInt8(truncatingIfNeeded: x / 8 + Int(seed >> 28)); px[i + 1] = UInt8(truncatingIfNeeded: y / 6 + Int((seed >> 24) & 15)); px[i + 2] = UInt8(truncatingIfNeeded: (x + y) / 10)
        } }
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let u = file(name)
        let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(d, ctx.makeImage()!, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(d))
        return u
    }

    func testImagesToPDFKeepsJPEGCompressedAndHonoursOrientation() throws {
        let jpg = try noisyJPEG("big.jpg", width: 2000, height: 1500)
        let pdf = try engine.imagesToPDF([jpg], output: file("big.pdf"))
        let jpgSize = try Data(contentsOf: jpg).count, pdfSize = try Data(contentsOf: pdf).count
        XCTAssertLessThan(pdfSize, 2 * jpgSize, "pdf \(pdfSize) vs jpeg \(jpgSize)")
        let landscape = PDFDocument(url: pdf)!.page(at: 0)!.bounds(for: .mediaBox)
        XCTAssertGreaterThan(landscape.width, landscape.height)

        let rotated = try noisyJPEG("rot.jpg", width: 400, height: 300, orientation: 6)
        let box = PDFDocument(url: try engine.imagesToPDF([rotated], output: file("rot.pdf")))!.page(at: 0)!.bounds(for: .mediaBox)
        XCTAssertGreaterThan(box.height, box.width)
        XCTAssertEqual(box.height / box.width, 400.0 / 300.0, accuracy: 0.01)
    }

    func testRenderCapsHugePages() throws {
        var box = CGRect(x: 0, y: 0, width: 14400, height: 14400)  // PDF max page size
        let u = file("huge.pdf")
        let ctx = CGContext(u as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
        let page = PDFDocument(url: u)!.page(at: 0)!
        let img = try XCTUnwrap(PDFText.render(page, scale: 2))
        XCTAssertLessThanOrEqual(Double(img.width * img.height), PDFText.maxPixels * 1.01)
    }

    func testTextutilTimeoutKillsProcess() throws {
        let src = try write("t.txt", "hello")
        XCTAssertThrowsError(try Textutil.convert(src, to: "rtf", output: file("t.rtf"), timeout: 0.0001)) {
            XCTAssertEqual($0 as? OpenTextError, .timedOut(src))
        }
        XCTAssertNoThrow(try Textutil.convert(src, to: "rtf", output: file("t2.rtf")))
    }

    func testImagesToPDFAndCombine() throws {
        let a = try imageFile("a.png", type: .png), b = try imageFile("b.jpg", type: .jpeg)
        let pdf = try engine.imagesToPDF([a, b, a], output: file("imgs.pdf"))
        XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 3)
        let t = try textPDF()
        let combined = try engine.combinePDFs([t, pdf], output: file("all.pdf"))
        XCTAssertEqual(PDFDocument(url: combined)?.pageCount, 5)
        XCTAssertTrue((PDFDocument(url: combined)?.string ?? "").contains("Second page words."))
    }

    func testUniqueNameRuleAndOverwrite() throws {
        let txt = try write("n.txt", "x")
        XCTAssertEqual(try engine.convert(txt, to: .md)[0].lastPathComponent, "n.md")
        XCTAssertEqual(try engine.convert(txt, to: .md)[0].lastPathComponent, "n 2.md")
        XCTAssertEqual(try engine.convert(txt, to: .md)[0].lastPathComponent, "n 3.md")
        var o = ConversionOptions(); o.overwrite = true
        XCTAssertEqual(try engine.convert(txt, to: .md, options: o)[0].lastPathComponent, "n.md")
        let out = file("custom.md")
        XCTAssertEqual(try engine.convert(txt, to: .md, output: out)[0], out)
    }

    func testUnsupportedAndUnreadable() throws {
        let txt = try write("n.txt", "x")
        XCTAssertThrowsError(try engine.convert(txt, to: .png)) { XCTAssertEqual($0 as? OpenTextError, .unsupportedConversion(from: .txt, to: .png)) }
        XCTAssertThrowsError(try engine.convert(file("missing.txt"), to: .md)) { XCTAssertEqual($0 as? OpenTextError, .unreadable(file("missing.txt"))) }
    }

    func testSwitchFormatTrashesOriginal() throws {
        let txt = try write("switch-\(UUID().uuidString).txt", "# Heading\n")
        let md = try engine.switchFormat(txt, to: .md)
        XCTAssertEqual(md.pathExtension, "md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: md.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: txt.path), "original must leave its folder")
        let trashed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(txt.lastPathComponent)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path), "original should be in the Trash")
        try? FileManager.default.removeItem(at: trashed) // our own test file only
    }

    func testNewFile() throws {
        let a = try NewFile.create(.md, in: dir)
        let b = try NewFile.create(.md, in: dir)
        let c = try NewFile.create(.html, name: "Page", in: dir)
        XCTAssertEqual([a, b, c].map(\.lastPathComponent), ["Untitled.md", "Untitled 2.md", "Page.html"])
        XCTAssertEqual(try NewFile.create(.csv, in: dir).lastPathComponent, "Untitled.csv")
        XCTAssertThrowsError(try NewFile.create(.pdf, in: dir))
    }

    func testTargetsMatchConvert() throws {
        XCTAssertEqual(Set(engine.targets(from: .pdf)), [.txt, .md, .png, .jpg])
        XCTAssertTrue(engine.targets(from: .md).contains(.docx))
        XCTAssertTrue(engine.targets(from: .otlock).isEmpty)
    }
}
