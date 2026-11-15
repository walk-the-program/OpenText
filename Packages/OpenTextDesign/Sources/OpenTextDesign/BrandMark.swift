import AppKit
import SwiftUI

/// One geometry source for the OpenText mark (a page with a folded corner and two text lines),
/// shared by the SwiftUI view and both NSImages. Coordinates come from the 1024 icon grid.
enum MarkGeometry {
    static let grid: CGFloat = 1024
    static let strokeUnits: CGFloat = 66.56
    /// Glyph bounds including stroke, in icon-grid units.
    static let box = CGRect(x: 290 - strokeUnits / 2, y: 200 - strokeUnits / 2,
                            width: 444 + strokeUnits, height: 624 + strokeUnits)
    static var aspect: CGFloat { box.width / box.height }
    /// Corner radius of the app-icon tile as a fraction of its side (the macOS 26 icon shape).
    static let tileCornerFraction: CGFloat = 0.2237

    /// Maps the glyph box into `rect` (top-left origin, y down): the glyph fills the rect.
    static func glyphTransform(into rect: CGRect) -> CGAffineTransform {
        let k = rect.height / box.height
        return CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: k, y: k).translatedBy(x: -box.minX, y: -box.minY)
    }

    /// Maps the whole 1024 grid into `rect`: the glyph sits where it sits on the app icon.
    static func tileTransform(into rect: CGRect) -> CGAffineTransform {
        let k = rect.width / grid
        return CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: k, y: k)
    }

    static func body(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 290, y: 200)); p.addLine(to: CGPoint(x: 524, y: 200)); p.addLine(to: CGPoint(x: 734, y: 410))
        p.addLine(to: CGPoint(x: 734, y: 824)); p.addLine(to: CGPoint(x: 290, y: 824)); p.closeSubpath()
        return p.copy(using: [t])!
    }

    static func fold(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 524, y: 200)); p.addLine(to: CGPoint(x: 524, y: 410)); p.addLine(to: CGPoint(x: 734, y: 410)); p.closeSubpath()
        return p.copy(using: [t])!
    }

    static func lines(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 390, y: 560)); p.addLine(to: CGPoint(x: 634, y: 560))
        p.move(to: CGPoint(x: 390, y: 690)); p.addLine(to: CGPoint(x: 540, y: 690))
        return p.copy(using: [t])!
    }

    static func tile(in rect: CGRect) -> CGPath {
        let r = rect.width * tileCornerFraction
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// Draws the full-colour app-icon tile into `rect` (a square, flipped context).
    static func drawTile(in ctx: CGContext, rect: CGRect) {
        let t = tileTransform(into: rect)
        ctx.saveGState()
        ctx.addPath(tile(in: rect)); ctx.clip()
        ctx.setFillColor(Brand.Mark.groundNS.cgColor); ctx.fill(rect)
        ctx.setLineWidth(strokeUnits * rect.width / grid); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setStrokeColor(Brand.Mark.inkNS.cgColor)
        ctx.setFillColor(Brand.Mark.pageNS.cgColor); ctx.addPath(body(t)); ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(Brand.Mark.foldNS.cgColor); ctx.addPath(fold(t)); ctx.drawPath(using: .fillStroke)
        ctx.addPath(lines(t)); ctx.strokePath()
        ctx.restoreGState()
    }
}

/// The OpenText logo: the apricot app-icon tile (white page, citron fold). Same colours in light and dark,
/// like the icon in the Dock. For monochrome places (menu bar) use `templateImage`.
public struct BrandMark: View {
    public let size: CGFloat

    /// - Parameter size: side of the square tile in points.
    public init(size: CGFloat) { self.size = size }

    public var body: some View {
        Canvas { ctx, canvasSize in
            ctx.withCGContext { MarkGeometry.drawTile(in: $0, rect: CGRect(origin: .zero, size: canvasSize)) }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("OpenText")
    }

    /// Full-colour tile as a vector NSImage, for AppKit places that show the logo (Finder menus).
    /// Safe to draw on any thread.
    public static func image(pointSize: CGFloat = 16) -> NSImage { MarkImages.tile(pointSize: pointSize) }

    /// Monochrome template of the page glyph for the menu bar. Vector, strokes never thinner than 1.4pt.
    public static func templateImage(pointSize: CGFloat = 16) -> NSImage { MarkImages.template(pointSize: pointSize) }
}

/// Image builders live outside the SwiftUI view so their drawing handlers are not main-actor isolated:
/// AppKit (and the Finder extension) may render them off the main thread.
enum MarkImages {
    static func tile(pointSize: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            MarkGeometry.drawTile(in: ctx, rect: bounds)
            return true
        }
        image.accessibilityDescription = "OpenText"
        return image
    }

    static func template(pointSize: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize * MarkGeometry.aspect, height: pointSize), flipped: true) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let natural = MarkGeometry.strokeUnits * bounds.height / MarkGeometry.box.height
            let width = max(1.4, natural)
            // Inset by half the extra stroke so a raised width stays inside the image bounds.
            let inset = (width - natural) / 2
            let t = MarkGeometry.glyphTransform(into: bounds.insetBy(dx: inset, dy: inset))
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addPath(MarkGeometry.body(t)); ctx.strokePath()
            ctx.addPath(MarkGeometry.fold(t)); ctx.drawPath(using: .fillStroke)
            ctx.addPath(MarkGeometry.lines(t)); ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "OpenText"
        return image
    }
}
