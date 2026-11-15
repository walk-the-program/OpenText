import AppKit
import CoreText
import Foundation
import Testing
@testable import OpenTextDesign

@Suite struct BrandTests {
    @Test func fontsRegisterAndResolve() {
        #expect(Brand.registerFonts())
        for name in Brand.Fonts.PostScript.all {
            let font = CTFontCreateWithName(name as CFString, 13, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name, "\(name) should resolve to itself, not a fallback")
            #expect(["Geist", "Geist Mono"].contains(CTFontCopyFamilyName(font) as String))
        }
        #expect(Brand.Fonts.nsBody(13, weight: .semibold).fontName == "Geist-SemiBold")
        #expect(Brand.Fonts.nsHeading().fontName == "Geist-SemiBold")
        #expect(Brand.Fonts.nsMono().fontName == "GeistMono-Regular")
    }

    @Test func geistIsTheOnlyUIFamily() {
        _ = Brand.registerFonts()
        let families = NSFontManager.shared.availableFontFamilies
        #expect(families.contains("Geist"))
        // Only Geist and Geist Mono ship in the bundle (Inter may be installed on the Mac itself, which is fine).
        let bundled = (Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "woff2", subdirectory: nil) ?? [])
        #expect(Set(bundled.map(\.lastPathComponent)) == ["Geist.woff2", "GeistMono-Regular.ttf"], "bundled: \(bundled.map(\.lastPathComponent))")
        let regular = CTFontCopyVariation(Brand.Fonts.nsBody(14) as CTFont) as? [Int: Double]
        let semibold = CTFontCopyVariation(Brand.Fonts.nsHeading(20) as CTFont) as? [Int: Double]
        // Regular is the font's default instance, which reports no variation (or 400).
        #expect(regular?.isEmpty != false || regular?.values.contains(400) == true, "regular: \(String(describing: regular))")
        #expect(semibold?.values.contains(600) == true, "semibold: \(String(describing: semibold))")
    }

    @Test func paletteMatchesBrandJSON() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("design/brand.json"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pairs: [(String, NSColor)] = [
            ("canvas", Brand.NSPalette.canvas), ("surface", Brand.NSPalette.surface), ("ink", Brand.NSPalette.ink),
            ("muted", Brand.NSPalette.muted), ("line", Brand.NSPalette.line), ("primary", Brand.NSPalette.primary),
            ("on-primary", Brand.NSPalette.onPrimary), ("accent", Brand.NSPalette.accent), ("on-accent", Brand.NSPalette.onAccent),
        ]
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let tokens = try #require(json[mode] as? [String: String])
            for (key, color) in pairs {
                var resolved = ""
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    let c = color.usingColorSpace(.sRGB)!
                    resolved = String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()),
                                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
                }
                #expect(resolved == tokens[key], "\(mode).\(key): \(resolved) vs \(tokens[key] ?? "nil")")
            }
        }
    }
}

@Suite struct BrandMarkTests {
    @Test func templateImageIsTemplateWithGlyphAspect() {
        let image = BrandMark.templateImage(pointSize: 16)
        #expect(image.isTemplate)
        #expect(image.size.height == 16)
        #expect(abs(image.size.width - 16 * 510.56 / 690.56) < 0.01)
    }

    @Test func colourImageIsTheApricotTile() throws {
        let image = BrandMark.image(pointSize: 64)
        #expect(!image.isTemplate)
        // Draw into an explicit sRGB bitmap: tiffRepresentation tags pixels with the screen's space.
        let side = 128
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let scale = CGFloat(side) / 64
        func px(_ x: CGFloat, _ y: CGFloat) -> NSColor? { rep.colorAt(x: Int(x * scale), y: Int(y * scale)) }
        let ground = try #require(px(6, 32)), page = try #require(px(40, 30)), corner = try #require(px(0.5, 0.5))
        #expect(abs(ground.redComponent - 1) < 0.03 && abs(ground.greenComponent - 0.780) < 0.03 && abs(ground.blueComponent - 0.608) < 0.03, "ground \(ground)")
        #expect(page.redComponent > 0.97 && page.greenComponent > 0.97 && page.blueComponent > 0.97)
        #expect(corner.alphaComponent < 0.1, "rounded tile corners are transparent")
    }
}
