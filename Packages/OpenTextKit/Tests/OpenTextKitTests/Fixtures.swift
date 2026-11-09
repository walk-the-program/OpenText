import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OpenTextKit

class TempTestCase: XCTestCase {
    var dir: URL!
    let engine = ConversionEngine()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("OPENTEXT_SETTINGS_PATH", dir.appendingPathComponent("settings.json").path, 1)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        unsetenv("OPENTEXT_SETTINGS_PATH")
    }

    func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

    func write(_ name: String, _ s: String) throws -> URL {
        let u = file(name)
        try s.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func richFixture(_ ext: String, type: NSAttributedString.DocumentType) throws -> URL {
        let s = NSMutableAttributedString(string: "Quarterly Report\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        s.append(NSAttributedString(string: "Alpha paragraph here.\n\nBeta paragraph there.\n", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        let data = try s.data(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: type])
        let u = file("rich.\(ext)")
        try data.write(to: u)
        return u
    }

    func textPDF(_ name: String = "two.pdf") throws -> URL {
        let u = file(name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(u as CFURL, mediaBox: &box, nil)!
        for text in ["First page words.", "Second page words."] {
            ctx.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 24)]) as CFAttributedString)
            ctx.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return u
    }

    func cgImage(width: Int = 400, height: Int = 200, text: String? = nil) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let text {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont(name: "Helvetica-Bold", size: 90)!, .foregroundColor: NSColor.black]) as CFAttributedString)
            ctx.textPosition = CGPoint(x: 30, y: CGFloat(height) / 2 - 30)
            CTLineDraw(line, ctx)
        } else {
            ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(x: 20, y: 20, width: 200, height: 100))
        }
        return ctx.makeImage()!
    }

    func imageFile(_ name: String, type: UTType) throws -> URL {
        let u = file(name)
        let d = CGImageDestinationCreateWithURL(u as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, cgImage(), nil)
        XCTAssertTrue(CGImageDestinationFinalize(d), "could not write \(type)")
        return u
    }

    func pixelSize(_ u: URL) -> (Int, Int) {
        let img = try! ImageTools.load(u)
        return (img.width, img.height)
    }

    func scannedPDF() throws -> URL {
        let image = NSImage(cgImage: cgImage(width: 1100, height: 300, text: "HELLO OPENTEXT"), size: NSSize(width: 550, height: 150))
        let doc = PDFDocument()
        doc.insert(PDFPage(image: image)!, at: 0)
        let u = file("scan.pdf")
        XCTAssertTrue(doc.write(to: u))
        return u
    }
}
