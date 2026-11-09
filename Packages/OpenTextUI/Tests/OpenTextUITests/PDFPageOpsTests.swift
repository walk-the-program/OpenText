import AppKit
import PDFKit
import Testing
@testable import OpenTextUI

/// Builds an in-memory PDF whose page n carries the text "Page n" so order is checkable.
func makeDocument(pages: Int, label: String = "Page") -> PDFDocument {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 300, height: 400)
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    for n in 1...pages {
        ctx.beginPDFPage(nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(label) \(n)", attributes: attrs))
        ctx.textPosition = CGPoint(x: 40, y: 300)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return PDFDocument(data: data as Data)!
}

func order(_ doc: PDFDocument) -> [String] {
    (0..<doc.pageCount).map { (doc.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

@Suite @MainActor struct PDFPageOpsTests {
    @Test func buildsThreePages() {
        let doc = makeDocument(pages: 3)
        #expect(doc.pageCount == 3)
        #expect(order(doc) == ["Page 1", "Page 2", "Page 3"])
    }

    @Test func movePages() {
        let doc = makeDocument(pages: 3)
        #expect(PDFPageOps.move(in: doc, from: 0, to: 2))
        #expect(order(doc) == ["Page 2", "Page 3", "Page 1"])
        #expect(PDFPageOps.move(in: doc, from: 2, to: 0))
        #expect(order(doc) == ["Page 1", "Page 2", "Page 3"])
        #expect(!PDFPageOps.move(in: doc, from: 5, to: 0))
        #expect(doc.pageCount == 3)
    }

    @Test func deletePagesKeepsAtLeastOne() {
        let doc = makeDocument(pages: 3)
        #expect(PDFPageOps.delete(in: doc, at: [1]) == 1)
        #expect(order(doc) == ["Page 1", "Page 3"])
        #expect(PDFPageOps.delete(in: doc, at: [0, 1]) == 1)
        #expect(doc.pageCount == 1)
        #expect(PDFPageOps.delete(in: doc, at: [0]) == 0)
        #expect(doc.pageCount == 1)
    }

    @Test func insertDocument() {
        let doc = makeDocument(pages: 3)
        let other = makeDocument(pages: 2, label: "Extra")
        #expect(PDFPageOps.insert(other, into: doc, at: 1) == 2)
        #expect(order(doc) == ["Page 1", "Extra 1", "Extra 2", "Page 2", "Page 3"])
        #expect(other.pageCount == 2)   // source untouched
        PDFPageOps.insert(other, into: doc, at: 99)
        #expect(doc.pageCount == 7)
        #expect(order(doc).last == "Extra 2")
    }

    @Test func rotate() {
        let doc = makeDocument(pages: 3)
        PDFPageOps.rotate(in: doc, pageAt: 1)
        #expect(doc.page(at: 1)?.rotation == 90)
        PDFPageOps.rotate(in: doc, pageAt: 1, by: -180)
        #expect(doc.page(at: 1)?.rotation == 270)
        #expect(doc.page(at: 0)?.rotation == 0)
    }

    @Test func highlightSelection() throws {
        let doc = makeDocument(pages: 3)
        let selection = try #require(doc.findString("Page 2", withOptions: []).first)
        let added = PDFPageOps.addHighlight(for: selection)
        #expect(added.count == 1)
        let page = try #require(doc.page(at: 1))
        #expect(page.annotations.contains { $0.type == "Highlight" })
        #expect(doc.page(at: 0)?.annotations.isEmpty == true)
    }

    @Test func stampAndFlatten() throws {
        let doc = makeDocument(pages: 3)
        let image = NSImage(size: NSSize(width: 100, height: 30), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill(); return true
        }
        let page = try #require(doc.page(at: 2))
        let bounds = PDFPageOps.defaultStampBounds(for: image, on: page)
        #expect(bounds.width == 150 && abs(bounds.height - 45) < 0.01)
        PDFPageOps.stampImage(image, on: page, bounds: bounds)
        #expect(page.annotations.contains { $0 is ImageStampAnnotation })
        #expect(PDFPageOps.flattenStamps(in: doc) == 1)
        #expect(doc.pageCount == 3)
        #expect(order(doc) == ["Page 1", "Page 2", "Page 3"])          // text layer survives
        #expect(doc.page(at: 2)?.annotations.contains { $0 is ImageStampAnnotation } == false)
        // the baked image is present in a round-tripped file
        let bytes = try #require(doc.dataRepresentation())
        let reloaded = try #require(PDFDocument(data: bytes))
        let thumb = try #require(reloaded.page(at: 2)).thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox)
        let tiff = try #require(thumb.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let x = Int(bounds.midX / 300 * Double(rep.pixelsWide)), y = Int((1 - bounds.midY / 400) * Double(rep.pixelsHigh))
        let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        #expect(c.redComponent < 0.2)
    }
}
