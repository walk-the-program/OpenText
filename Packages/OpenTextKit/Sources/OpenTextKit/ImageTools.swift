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
        let type: UTType
        switch format {
        case .jpg: type = .jpeg
        case .png: type = .png
        case .tiff: type = .tiff
        case .heic: type = .heic
        case .gif: type = .gif
        default: throw OpenTextError.unsupportedConversion(from: .png, to: format)
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw OpenTextError.writeFailed(url)
        }
        let img = format == .jpg ? flattened(image) : image
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: max(0, min(1, quality))]
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw OpenTextError.writeFailed(url) }
    }

    /// Writes a PDF with one page per image, each page sized to its image (capped at 842 points on the long side).
    static func imagesToPDF(_ inputs: [URL], output: URL) throws -> URL {
        guard !inputs.isEmpty else { throw OpenTextError.unreadable(output) }
        guard let ctx = CGContext(output as CFURL, mediaBox: nil, nil) else { throw OpenTextError.writeFailed(output) }
        for url in inputs {
            let image = try load(url)
            let scale = min(1, 842 / Double(max(image.width, image.height)))
            var box = CGRect(x: 0, y: 0, width: Double(image.width) * scale, height: Double(image.height) * scale)
            let boxData = withUnsafeBytes(of: &box) { Data($0) }
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            ctx.draw(image, in: box)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return output
    }
}
