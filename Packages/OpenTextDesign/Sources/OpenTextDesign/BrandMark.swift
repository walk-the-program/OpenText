import AppKit
import SwiftUI

/// One geometry source for the OpenText mark (a page with a folded corner and two text lines),
/// shared by the SwiftUI view and the template NSImage. Coordinates come from the 1024 icon grid.
enum MarkGeometry {
    static let strokeUnits: CGFloat = 66.56
    /// Glyph bounds including stroke, in icon-grid units.
    static let box = CGRect(x: 290 - strokeUnits / 2, y: 200 - strokeUnits / 2,
                            width: 444 + strokeUnits, height: 624 + strokeUnits)
    static var aspect: CGFloat { box.width / box.height }

    /// Maps icon-grid points into `rect` (top-left origin, y down).
    private static func transform(into rect: CGRect) -> CGAffineTransform {
        let k = rect.height / box.height
        return CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: k, y: k).translatedBy(x: -box.minX, y: -box.minY)
    }

    static func body(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 290, y: 200)); p.addLine(to: CGPoint(x: 524, y: 200)); p.addLine(to: CGPoint(x: 734, y: 410))
        p.addLine(to: CGPoint(x: 734, y: 824)); p.addLine(to: CGPoint(x: 290, y: 824)); p.closeSubpath()
        return p.copy(using: [transform(into: rect)])!
    }

    static func fold(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 524, y: 200)); p.addLine(to: CGPoint(x: 524, y: 410)); p.addLine(to: CGPoint(x: 734, y: 410)); p.closeSubpath()
        return p.copy(using: [transform(into: rect)])!
    }

    static func lines(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 390, y: 560)); p.addLine(to: CGPoint(x: 634, y: 560))
        p.move(to: CGPoint(x: 390, y: 690)); p.addLine(to: CGPoint(x: 540, y: 690))
        return p.copy(using: [transform(into: rect)])!
    }

    static func lineWidth(forHeight h: CGFloat) -> CGFloat { strokeUnits * h / box.height }
}

/// The OpenText logo. Paper and ink adapt to light and dark; the citron fold is the only colour.
public struct BrandMark: View {
    public let size: CGFloat

    /// - Parameter size: height of the glyph box in points.
    public init(size: CGFloat) { self.size = size }

    public var body: some View {
        Canvas { ctx, canvasSize in
            // Half-point inset keeps antialiased edges of the outer stroke from being clipped by the canvas.
            let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 0.5, dy: 0.5)
            let style = StrokeStyle(lineWidth: MarkGeometry.lineWidth(forHeight: rect.height), lineCap: .round, lineJoin: .round)
            let body = Path(MarkGeometry.body(in: rect)), fold = Path(MarkGeometry.fold(in: rect))
            ctx.fill(body, with: .color(Brand.Palette.surface))
            ctx.stroke(body, with: .color(Brand.Palette.ink), style: style)
            ctx.fill(fold, with: .color(Brand.Mark.fold))
            ctx.stroke(fold, with: .color(Brand.Palette.ink), style: style)
            ctx.stroke(Path(MarkGeometry.lines(in: rect)), with: .color(Brand.Palette.ink), style: style)
        }
        .frame(width: size * MarkGeometry.aspect, height: size)
        .accessibilityElement()
        .accessibilityLabel("OpenText")
    }

    /// Monochrome template image for the menu bar and Finder. Vector (drawing handler), strokes never thinner than 1.4pt.
    public static func templateImage(pointSize: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize * MarkGeometry.aspect, height: pointSize), flipped: true) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let width = max(1.4, MarkGeometry.lineWidth(forHeight: bounds.height))
            // Inset by half a stroke so the stroke stays inside the image bounds when the width is raised.
            let inset = max(0, width - MarkGeometry.lineWidth(forHeight: bounds.height)) / 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addPath(MarkGeometry.body(in: rect)); ctx.strokePath()
            ctx.addPath(MarkGeometry.fold(in: rect)); ctx.drawPath(using: .fillStroke)
            ctx.addPath(MarkGeometry.lines(in: rect)); ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
