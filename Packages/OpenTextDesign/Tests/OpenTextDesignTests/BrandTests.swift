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
            #expect(["Inter 18pt", "Plus Jakarta Sans", "Geist Mono"].contains(CTFontCopyFamilyName(font) as String))
        }
        #expect(Brand.Fonts.nsBody(13, weight: .semibold).fontName == "Inter18pt-SemiBold")
        #expect(Brand.Fonts.nsHeading().fontName == "PlusJakartaSans-Regular_SemiBold")
        #expect(Brand.Fonts.nsMono().fontName == "GeistMono-Regular")
    }

    @Test func headingIsJakartaSemiBoldAndDisplayIsLight() {
        _ = Brand.registerFonts()
        #expect(NSFontManager.shared.availableFontFamilies.contains("Plus Jakarta Sans"))
        #expect(!NSFontManager.shared.availableFontFamilies.contains("Inter Tight"))
        let heading = CTFontCopyVariation(Brand.Fonts.nsHeading(20) as CTFont) as? [Int: Double]
        #expect(heading?.values.contains(600) == true, "heading variation: \(String(describing: heading))")
        let light = CTFontCreateWithName(Brand.Fonts.PostScript.displayLight as CFString, 30, nil)
        let lv = CTFontCopyVariation(light) as? [Int: Double]
        #expect(lv?.values.contains(300) == true, "display variation: \(String(describing: lv))")
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
}
