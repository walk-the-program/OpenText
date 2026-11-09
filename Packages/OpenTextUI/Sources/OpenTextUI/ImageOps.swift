import AppKit
import CoreGraphics

/// Pixel operations on `CGImage`. Rect arguments use top-left-origin pixel coordinates (like image editors do).
public enum ImageOps {
    /// Crops to `rect` (clamped to the image). Returns nil if the clamped rect is empty.
    public static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = rect.integral.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return image.cropping(to: r)
    }

    public static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let ctx = makeContext(like: image, width: width, height: height) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Height for `width` keeping the image's aspect ratio (at least 1).
    public static func height(forWidth width: Int, keepingAspectOf size: (width: Int, height: Int)) -> Int {
        guard size.width > 0 else { return 1 }
        return max(1, Int((Double(width) * Double(size.height) / Double(size.width)).rounded()))
    }

    public static func width(forHeight height: Int, keepingAspectOf size: (width: Int, height: Int)) -> Int {
        guard size.height > 0 else { return 1 }
        return max(1, Int((Double(height) * Double(size.width) / Double(size.height)).rounded()))
    }

    /// 90 degree rotation. `clockwise` as seen on screen. Swaps width and height.
    public static func rotate90(_ image: CGImage, clockwise: Bool = true) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = makeContext(like: image, width: h, height: w) else { return nil }
        // CGContext origin is bottom-left; moving the image into a rotated frame.
        if clockwise {
            ctx.translateBy(x: 0, y: CGFloat(w)); ctx.rotate(by: -.pi / 2)
        } else {
            ctx.translateBy(x: CGFloat(h), y: 0); ctx.rotate(by: .pi / 2)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    public static func flip(_ image: CGImage, horizontal: Bool) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = makeContext(like: image, width: w, height: h) else { return nil }
        if horizontal { ctx.translateBy(x: CGFloat(w), y: 0); ctx.scaleBy(x: -1, y: 1) }
        else { ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Pixel size of an NSImage's best representation (falls back to point size).
    public static func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        if let rep = image.representations.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 { return (rep.pixelsWide, rep.pixelsHigh) }
        return (Int(image.size.width), Int(image.size.height))
    }

    public static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        if let best = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }), best.pixelsWide > 0 {
            rect = CGRect(x: 0, y: 0, width: best.pixelsWide, height: best.pixelsHigh)
        }
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    public static func nsImage(from image: CGImage) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: image)
        let result = NSImage(size: NSSize(width: image.width, height: image.height))
        result.addRepresentation(rep)
        return result
    }

    private static func makeContext(like image: CGImage, width: Int, height: Int) -> CGContext? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
