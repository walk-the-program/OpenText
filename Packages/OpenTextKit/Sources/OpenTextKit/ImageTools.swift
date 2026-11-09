import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageTools {
    static func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw OpenTextError.unreadable(url)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        if w > 0, h > 0 {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            ]
            if let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) { return img }
        }
        guard let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw OpenTextError.unreadable(url) }
        return img
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    static func flattened(_ image: CGImage) -> CGImage {
        guard hasAlpha(image),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    static func write(_ image: CGImage, as format: DocFormat, to url: URL, quality: Double) throws {
        guard let type = format.imageUTType else { throw OpenTextError.unsupportedConversion(from: .png, to: format) }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw OpenTextError.writeFailed(url)
        }
        let img = format == .jpg ? flattened(image) : image
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: max(0, min(1, quality))]
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw OpenTextError.writeFailed(url) }
    }

    /// The source image as stored (so JPEG data can stay compressed in a PDF) plus its EXIF orientation (1...8).
    /// Falls back to the oriented thumbnail path, orientation 1, when the source cannot be decoded directly.
    static func loadRaw(_ url: URL) throws -> (image: CGImage, orientation: Int) {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let o = (props?[kCGImagePropertyOrientation] as? Int) ?? 1
            return (img, (1...8).contains(o) ? o : 1)
        }
        return (try load(url), 1)
    }

    /// Maps raw pixel space (y up, `w` x `h`) to the displayed image for an EXIF orientation.
    static func orientationTransform(_ o: Int, width w: CGFloat, height h: CGFloat) -> CGAffineTransform {
        switch o {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 6: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case 7: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 8: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        default: return .identity
        }
    }

    /// Writes a PDF with one page per image, each page sized to the displayed (EXIF-oriented) image, capped at 842 points on the long side.
    static func imagesToPDF(_ inputs: [URL], output: URL) throws -> URL {
        guard !inputs.isEmpty else { throw OpenTextError.unreadable(output) }
        guard let ctx = CGContext(output as CFURL, mediaBox: nil, nil) else { throw OpenTextError.writeFailed(output) }
        for url in inputs {
            let (image, orientation) = try loadRaw(url)
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let swap = orientation >= 5
            let (ow, oh) = swap ? (h, w) : (w, h)
            let scale = min(1, 842 / max(ow, oh))
            var box = CGRect(x: 0, y: 0, width: ow * scale, height: oh * scale)
            let boxData = withUnsafeBytes(of: &box) { Data($0) }
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            ctx.saveGState()
            ctx.concatenate(orientationTransform(orientation, width: w, height: h).concatenating(CGAffineTransform(scaleX: scale, y: scale)))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return output
    }
}
