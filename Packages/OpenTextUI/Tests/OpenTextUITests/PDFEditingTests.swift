import AppKit
import PDFKit
import Testing
@testable import OpenTextUI

/// A solid red 200x60 "signature".
private func redSignature() -> NSImage {
    let image = NSImage(size: NSSize(width: 200, height: 60))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 200, height: 60).fill()
    image.unlockFocus()
    return image
}

/// Colour of the rendered page at a page-space point (page rendered 1:1).
private func pixel(_ page: PDFPage, at p: CGPoint) -> NSColor? {
    let box = page.bounds(for: .cropBox)
    let image = page.thumbnail(of: box.size, for: .cropBox)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    let sx = CGFloat(rep.pixelsWide) / box.width, sy = CGFloat(rep.pixelsHigh) / box.height
    return rep.colorAt(x: Int((p.x - box.minX) * sx), y: rep.pixelsHigh - 1 - Int((p.y - box.minY) * sy))?.usingColorSpace(.sRGB)
}

private func isRed(_ c: NSColor?) -> Bool { guard let c else { return false }; return c.redComponent > 0.8 && c.greenComponent < 0.3 && c.blueComponent < 0.3 }

@Suite struct AnnotationGeometryTests {
    let page = CGRect(x: 0, y: 0, width: 300, height: 400)

    @Test func moveIsClampedToThePage() {
        let r = CGRect(x: 10, y: 10, width: 50, height: 20)
        #expect(AnnotationGeometry.moved(r, by: CGSize(width: 100, height: 50), within: page) == CGRect(x: 110, y: 60, width: 50, height: 20))
        #expect(AnnotationGeometry.moved(r, by: CGSize(width: -500, height: 900), within: page) == CGRect(x: 0, y: 380, width: 50, height: 20))
    }

    @Test func resizeKeepsTheOppositeCorner() {
        let r = CGRect(x: 100, y: 100, width: 100, height: 50)
        let out = AnnotationGeometry.resized(r, handle: .topRight, to: CGPoint(x: 260, y: 200), keepAspect: false, within: page)
        #expect(out == CGRect(x: 100, y: 100, width: 160, height: 100))
        let left = AnnotationGeometry.resized(r, handle: .bottomLeft, to: CGPoint(x: 80, y: 90), keepAspect: false, within: page)
        #expect(left == CGRect(x: 80, y: 90, width: 120, height: 60))
    }

    @Test func aspectLockKeepsTheRatio() {
        let r = CGRect(x: 100, y: 100, width: 100, height: 50)
        let out = AnnotationGeometry.resized(r, handle: .topRight, to: CGPoint(x: 300, y: 120), keepAspect: true, within: page)
        #expect(abs(out.width / out.height - 2) < 0.001)
        #expect(out.minX == 100 && out.minY == 100)
        #expect(out.maxX <= page.maxX + 0.001)
    }

    @Test func resizeNeverGoesBelowTheMinimum() {
        let r = CGRect(x: 100, y: 100, width: 100, height: 50)
        let out = AnnotationGeometry.resized(r, handle: .topRight, to: CGPoint(x: 90, y: 90), keepAspect: false, within: page)
        #expect(out.width == AnnotationGeometry.minimumSide && out.height == AnnotationGeometry.minimumSide)
    }

    @Test func handleHitTest() {
        let r = CGRect(x: 100, y: 100, width: 100, height: 50)
        #expect(AnnotationGeometry.handle(at: CGPoint(x: 203, y: 148), for: r, tolerance: 5) == .topRight)
        #expect(AnnotationGeometry.handle(at: CGPoint(x: 150, y: 125), for: r, tolerance: 5) == nil)
    }
}

@Suite @MainActor struct PDFEditingTests {
    @Test func signatureMovesUndoesAndRedoes() {
        let doc = makeDocument(pages: 2)
        let model = PDFReaderModel(document: doc)
        var changes = 0
        model.actions = PDFReaderActions(loadSignature: { redSignature().tiffRepresentation }, onChange: { changes += 1 })
        model.sign()
        guard let stamp = model.selectedAnnotation as? ImageStampAnnotation else { Issue.record("no signature selected"); return }
        #expect(doc.page(at: 0)!.annotations.contains { $0 === stamp })
        let start = stamp.bounds
        model.nudge(dx: 10, dy: -5)
        #expect(stamp.bounds == start.offsetBy(dx: 10, dy: -5))
        model.undo.undo()
        #expect(stamp.bounds == start)
        model.undo.redo()
        #expect(stamp.bounds == start.offsetBy(dx: 10, dy: -5))
        model.deleteSelectedAnnotation()
        #expect(!doc.page(at: 0)!.annotations.contains { $0 === stamp })
        model.undo.undo()
        #expect(doc.page(at: 0)!.annotations.contains { $0 === stamp })
        #expect(changes >= 5)
    }

    @Test func selectionFrameIsNeverSaved() {
        let doc = makeDocument(pages: 1)
        let model = PDFReaderModel(document: doc)
        model.actions = PDFReaderActions(loadSignature: { redSignature().tiffRepresentation })
        model.sign()
        #expect(doc.page(at: 0)!.annotations.contains { $0 is SelectionFrameAnnotation })
        guard let flat = PDFPageOps.flattenedCopy(of: doc) else { Issue.record("no copy"); return }
        #expect(!flat.page(at: 0)!.annotations.contains { $0 is SelectionFrameAnnotation || $0 is ImageStampAnnotation })
        // The live document keeps the editable signature and the frame.
        #expect(doc.page(at: 0)!.annotations.contains { $0 is ImageStampAnnotation })
    }

    @Test func savedCopyBurnsTheSignatureInWhereItWasMoved() throws {
        let doc = makeDocument(pages: 1)
        let page = doc.page(at: 0)!
        page.setBounds(CGRect(x: 20, y: 20, width: 260, height: 360), for: .cropBox)
        let stamp = PDFPageOps.stampImage(redSignature(), on: page, bounds: CGRect(x: 40, y: 40, width: 100, height: 30))
        stamp.bounds = CGRect(x: 150, y: 300, width: 100, height: 30)        // "moved"
        let flat = try #require(PDFPageOps.flattenedCopy(of: doc))
        let data = try #require(flat.dataRepresentation())
        let reopened = try #require(PDFDocument(data: data))
        let out = try #require(reopened.page(at: 0))
        #expect(out.bounds(for: .cropBox) == CGRect(x: 20, y: 20, width: 260, height: 360))
        #expect(isRed(pixel(out, at: CGPoint(x: 200, y: 315))), "signature burned in at its new spot")
        #expect(!isRed(pixel(out, at: CGPoint(x: 90, y: 55))), "nothing left at the old spot")
    }

    @Test func textBoxIsBurnedIn() throws {
        let doc = makeDocument(pages: 1, label: "")
        let page = doc.page(at: 0)!
        page.addAnnotation(TextBoxAnnotation(text: "Approved by Walker", bounds: CGRect(x: 40, y: 100, width: 220, height: 28)))
        let flat = try #require(PDFPageOps.flattenedCopy(of: doc))
        let data = try #require(flat.dataRepresentation())
        let reopened = try #require(PDFDocument(data: data))
        #expect(reopened.page(at: 0)?.string?.contains("Approved by Walker") == true)
    }

    @Test func pageOperationsUndo() {
        let doc = makeDocument(pages: 3)
        let model = PDFReaderModel(document: doc)
        model.rotate(by: 90)
        #expect(doc.page(at: 0)!.rotation == 90)
        model.undo.undo()
        #expect(doc.page(at: 0)!.rotation == 0)
        model.selectedPages = [1, 2]
        model.deleteSelectedPages()
        #expect(order(doc) == ["Page 1"])
        model.undo.undo()
        #expect(order(doc) == ["Page 1", "Page 2", "Page 3"])
        model.move(from: 0, to: 2)
        #expect(order(doc) == ["Page 2", "Page 3", "Page 1"])
        model.undo.undo()
        #expect(order(doc) == ["Page 1", "Page 2", "Page 3"])
    }

    @Test func cannotDeleteEveryPage() {
        let doc = makeDocument(pages: 2)
        let model = PDFReaderModel(document: doc)
        model.selectedPages = [0, 1]
        model.deleteSelectedPages()
        #expect(doc.pageCount == 2)
    }

    @Test func extractWritesTheChosenPages() throws {
        let doc = makeDocument(pages: 4)
        PDFPageOps.stampImage(redSignature(), on: doc.page(at: 2)!, bounds: CGRect(x: 100, y: 50, width: 100, height: 30))
        let out = PDFPageOps.extract(pages: [1, 2], from: doc)
        #expect(order(out) == ["Page 2", "Page 3"], "got \(order(out)) count \(out.pageCount)")
        #expect(isRed(pixel(out.page(at: 1)!, at: CGPoint(x: 150, y: 65))))
        #expect(doc.page(at: 2)!.annotations.contains { $0 is ImageStampAnnotation }, "source keeps its editable signature")
    }

    @Test func thumbnailMultiSelect() {
        let model = PDFReaderModel(document: makeDocument(pages: 5))
        model.clickThumbnail(1, command: false, shift: false)
        model.clickThumbnail(3, command: false, shift: true)
        #expect(model.selectedPages == [1, 2, 3])
        model.clickThumbnail(2, command: true, shift: false)
        #expect(model.selectedPages == [1, 3])
    }
}
