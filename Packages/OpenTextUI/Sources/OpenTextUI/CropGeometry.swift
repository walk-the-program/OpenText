import CoreGraphics

/// Crop rectangle logic in a normalised (0...1) space so it is independent of zoom. Pure and testable.
public struct CropRect: Equatable, Sendable {
    public enum Corner: Sendable { case topLeft, topRight, bottomLeft, bottomRight }
    public enum Grab: Equatable, Sendable { case corner(Corner), inside, none }

    public var rect: CGRect
    public init(_ rect: CGRect) { self.rect = rect }

    static let minSide: CGFloat = 0.02

    /// What a press at `point` (normalised) would grab. `tolerance` is in normalised units.
    public func grab(at point: CGPoint, tolerance: CGFloat) -> Grab {
        let corners: [(Corner, CGPoint)] = [(.topLeft, CGPoint(x: rect.minX, y: rect.minY)), (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
                                            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)), (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))]
        for (corner, p) in corners where abs(p.x - point.x) <= tolerance && abs(p.y - point.y) <= tolerance { return .corner(corner) }
        return rect.contains(point) ? .inside : .none
    }

    public func moved(by delta: CGSize) -> CropRect {
        var r = rect
        r.origin.x = min(max(0, r.origin.x + delta.width), 1 - r.width)
        r.origin.y = min(max(0, r.origin.y + delta.height), 1 - r.height)
        return CropRect(r)
    }

    public func resized(corner: Corner, to point: CGPoint) -> CropRect {
        let p = CGPoint(x: min(max(0, point.x), 1), y: min(max(0, point.y), 1))
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch corner {
        case .topLeft: minX = min(p.x, maxX - Self.minSide); minY = min(p.y, maxY - Self.minSide)
        case .topRight: maxX = max(p.x, minX + Self.minSide); minY = min(p.y, maxY - Self.minSide)
        case .bottomLeft: minX = min(p.x, maxX - Self.minSide); maxY = max(p.y, minY + Self.minSide)
        case .bottomRight: maxX = max(p.x, minX + Self.minSide); maxY = max(p.y, minY + Self.minSide)
        }
        return CropRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    /// A rectangle spanned by two points, clamped to the unit square.
    public static func spanning(_ a: CGPoint, _ b: CGPoint) -> CropRect {
        let x0 = min(max(0, min(a.x, b.x)), 1), x1 = min(max(0, max(a.x, b.x)), 1)
        let y0 = min(max(0, min(a.y, b.y)), 1), y1 = min(max(0, max(a.y, b.y)), 1)
        return CropRect(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
    }

    /// Pixel rect (top-left origin) for an image of the given pixel size.
    public func pixelRect(width: Int, height: Int) -> CGRect {
        CGRect(x: rect.minX * CGFloat(width), y: rect.minY * CGFloat(height), width: rect.width * CGFloat(width), height: rect.height * CGFloat(height)).integral
    }
}
