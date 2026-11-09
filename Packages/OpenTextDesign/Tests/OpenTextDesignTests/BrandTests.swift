import AppKit
import CoreText
import Foundation
import Testing
@testable import OpenTextDesign

@Suite struct BrandTests {
    @Test func fontsRegisterAndInterResolves() {
        #expect(Brand.registerFonts())
        for name in Brand.Fonts.PostScript.all {
            let font = CTFontCreateWithName(name as CFString, 13, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name, "\(name) should resolve to itself, not a fallback")
            #expect(["Inter 18pt", "Inter Tight"].contains(CTFontCopyFamilyName(font) as String))
        }
        #expect(Brand.Fonts.nsBody(13, weight: .semibold).fontName == "Inter18pt-SemiBold")
        #expect(Brand.Fonts.nsHeading().fontName == "InterTight-Regular_SemiBold")
    }

    @Test func interTightFamilyIsRegistered() {
        _ = Brand.registerFonts()
        let families = NSFontManager.shared.availableFontFamilies
        #expect(families.contains("Inter Tight"))
        #expect(Brand.Fonts.headingFamily == "Inter Tight")
        let font = Brand.Fonts.nsHeading(20)
        #expect(font.familyName == "Inter Tight")
        // weight axis is at 600, not the 400 default
        let axes = CTFontCopyVariation(font as CTFont) as? [Int: Double]
        #expect(axes?.values.contains(600) == true, "variation: \(String(describing: axes))")
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
