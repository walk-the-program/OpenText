import OpenTextDesign
import AppKit
import PDFKit

/// Page and annotation operations that need no UI. All operate in place on a `PDFDocument`.
public enum PDFPageOps {
    /// Moves the page at `from` so it ends up at index `to` (index in the resulting document).
    @discardableResult
    public static func move(in document: PDFDocument, from: Int, to: Int) -> Bool {
        let count = document.pageCount
        guard from >= 0, from < count, to >= 0, to < count else { return false }
        guard from != to, let page = document.page(at: from) else { return from == to }
        document.removePage(at: from)
        document.insert(page, at: to)
        return true
    }

    /// Deletes pages at the given indexes. Never removes the last remaining page. Returns how many were removed.
    @discardableResult
    public static func delete(in document: PDFDocument, at indexes: [Int]) -> Int {
        let valid = Set(indexes.filter { $0 >= 0 && $0 < document.pageCount })
        var removed = 0
        for index in valid.sorted(by: >) where document.pageCount > 1 {
            document.removePage(at: index)
            removed += 1
        }
        return removed
    }

    /// Inserts every page of `other` so the first lands at `index` (clamped to 0...pageCount). Returns pages added.
    @discardableResult
    public static func insert(_ other: PDFDocument, into document: PDFDocument, at index: Int) -> Int {
        var position = min(max(index, 0), document.pageCount)
        var added = 0
        for i in 0..<other.pageCount {
            guard let page = other.page(at: i)?.copy() as? PDFPage else { continue }
            document.insert(page, at: position)
            position += 1
            added += 1
        }
        return added
    }

    /// Rotates by a multiple of 90 degrees (positive = clockwise).
    public static func rotate(in document: PDFDocument, pageAt index: Int, by degrees: Int = 90) {
        guard let page = document.page(at: index) else { return }
        page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
    }

    /// Adds highlight annotations (one per selected line) in the accent colour. Returns the annotations added.
    @discardableResult
    public static func addHighlight(for selection: PDFSelection, color: NSColor = Brand.NSPalette.accent) -> [PDFAnnotation] {
        var added: [PDFAnnotation] = []
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color.withAlphaComponent(0.55)
                annotation.quadrilateralPoints = [
                    NSValue(point: CGPoint(x: 0, y: bounds.height)), NSValue(point: CGPoint(x: bounds.width, y: bounds.height)),
                    NSValue(point: CGPoint(x: 0, y: 0)), NSValue(point: CGPoint(x: bounds.width, y: 0)),
                ]
                page.addAnnotation(annotation)
                added.append(annotation)
            }
        }
        return added
    }

    /// Places an image (a signature) on a page. `bounds` are in page coordinates.
    @discardableResult
    public static func stampImage(_ image: NSImage, on page: PDFPage, bounds: CGRect) -> PDFAnnotation {
        let stamp = ImageStampAnnotation(image: image, bounds: bounds)
        page.addAnnotation(stamp)
        return stamp
    }

    /// Default placement: width 180pt, aspect preserved, centred horizontally in the lower third of the page.
    public static func defaultStampBounds(for image: NSImage, on page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: .cropBox)
        let width = min(180, pageBounds.width * 0.5)
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 0.3
        let height = width * aspect
        return CGRect(x: pageBounds.midX - width / 2, y: pageBounds.minY + pageBounds.height * 0.18, width: width, height: height)
    }

    /// PDFKit does not write custom-drawn annotations to disk. Call before `document.write(to:)`: every page
    /// carrying an `ImageStampAnnotation` is re-drawn (original content kept as vectors) with the image baked in.
    /// Returns the number of pages rewritten.
    @discardableResult
    public static func flattenStamps(in document: PDFDocument) -> Int {
        var rewritten = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let stamps = page.annotations.compactMap { $0 as? ImageStampAnnotation }
            guard !stamps.isEmpty, let cgPage = page.pageRef else { continue }
            var box = page.bounds(for: .mediaBox)
            let data = NSMutableData()
            guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { continue }
            ctx.beginPDFPage(nil)
            ctx.drawPDFPage(cgPage)
            for stamp in stamps {
                var rect = stamp.image.cgImageRect()
                if let cg = stamp.image.cgImage(forProposedRect: &rect, context: nil, hints: nil) { ctx.draw(cg, in: stamp.bounds) }
            }
            ctx.endPDFPage()
            ctx.closePDF()
            guard let new = PDFDocument(data: data as Data)?.page(at: 0) else { continue }
            for annotation in page.annotations where !(annotation is ImageStampAnnotation) {
                if let copy = annotation.copy() as? PDFAnnotation { new.addAnnotation(copy) }
            }
            // Redrawing yields a fresh page whose crop box is the media box; carry the original boxes over.
            new.setBounds(page.bounds(for: .mediaBox), for: .mediaBox)
            new.setBounds(page.bounds(for: .cropBox), for: .cropBox)
            new.rotation = page.rotation
            document.removePage(at: index)
            document.insert(new, at: index)
            rewritten += 1
        }
        return rewritten
    }
}

/// Image annotation drawn by the app; baked into the page by `PDFPageOps.flattenStamps`.
public final class ImageStampAnnotation: PDFAnnotation {
    public let image: NSImage

    public init(image: NSImage, bounds: CGRect) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    public required init?(coder: NSCoder) { fatalError("not supported") }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        var rect = image.cgImageRect()
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        context.saveGState()
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}

extension NSImage {
    func cgImageRect() -> NSRect { NSRect(origin: .zero, size: size) }
}
