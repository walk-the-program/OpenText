// Values mirror design/brand.json (Mesh Gradient, BUILD-PACK.md Part 1-2, Mac scale from docs/review/2026-11-10-mesh/plan.md). This is the only
// file that may contain colour literals. Change brand.json first, then update here.
import AppKit
import CoreText
import SwiftUI

public enum Brand {
    public static let appName = "OpenText"
    public static let accentBudget = 0.1

    // MARK: Colours (BUILD-PACK.md, Mesh Gradient, Part 2 Theme.swift)

    /// AppKit colours. Dynamic: they resolve against the effective appearance (light/dark) at draw time.
    public enum NSPalette {
        public static let canvas = NSColor.brand(light: "#f5f7f9", dark: "#1c2126")
        /// Card and panel fill (paper). `surface` is the older name.
        public static let card = NSColor.brand(light: "#ffffff", dark: "#2b3035")
        public static let surface = card
        public static let ink = NSColor.brand(light: "#1c2126", dark: "#f5f7f9")
        public static let muted = NSColor.brand(light: "#686c70", dark: "#9ea1a5")
        public static let line = NSColor.brand(light: "#d4d7d9", dark: "#3d4146")
        public static let primary = NSColor.brand(light: "#98b0cc", dark: "#98b0cc")
        /// Second stop of the primary gradient.
        public static let abMHue = NSColor.brand(light: "#9493d1", dark: "#9493d1")
        public static let onPrimary = NSColor.brand(light: "#141414", dark: "#141414")
        public static let accent = NSColor.brand(light: "#cacd7e", dark: "#cacd7e")
        public static let onAccent = NSColor.brand(light: "#141414", dark: "#141414")
        /// The primary as text and small icons, 4.5:1 on the canvas.
        public static let primaryText = NSColor.brand(light: "#607081", dark: "#98b0cc")
        public static let priTint = NSColor.brand(light: "#eaeef4", dark: "#2b323a")
        public static let secTint = NSColor.brand(light: "#f2f1f3", dark: "#3b3d41")
        public static let error = NSColor.brand(light: "#1c2126", dark: "#f5f7f9")
        public static let onError = NSColor.brand(light: "#f5f7f9", dark: "#1c2126")
        public static let abMuted = NSColor.brand(light: "#686c70", dark: "#a7aaad")
        public static let abFill = NSColor.brand(light: "#1c2126", dark: "#f5f7f9", lightAlpha: 0.045, darkAlpha: 0.07)
        public static let abHair = NSColor.brand(light: "#1c2126", dark: "#f5f7f9", lightAlpha: 0.09, darkAlpha: 0.14)
        public static let ring = NSColor.brand(light: "#98b0cc", dark: "#98b0cc", lightAlpha: 0.3, darkAlpha: 0.3)
        /// Kit shadow colours (measured, light and dark).
        public static let shadowNear = NSColor.brand(light: "#0a2540", dark: "#000000", lightAlpha: 0.06, darkAlpha: 0.16)
        public static let shadowFar = NSColor.brand(light: "#32325d", dark: "#000000", lightAlpha: 0.18, darkAlpha: 0.26)
        public static let shadowSoft = NSColor.brand(light: "#32325d", dark: "#000000", lightAlpha: 0.16, darkAlpha: 0.22)
        public static let shadowDeep = NSColor.brand(light: "#32325d", dark: "#000000", lightAlpha: 0.28, darkAlpha: 0.26)
        public static let pressedInset = NSColor.brand(light: "#0a2540", dark: "#0a2540", lightAlpha: 0.22, darkAlpha: 0.22)
        public static let topLight = NSColor.brand(light: "#ffffff", dark: "#ffffff", lightAlpha: 0.24, darkAlpha: 0.16)
    }

    /// Logo-only colour. The citron fold is the same in light and dark and is never a UI fill.
    public enum Mark {
        public static let foldNS = NSColor(brandHex: "#e2e58a")
        public static let fold = Color(nsColor: foldNS)
    }

    public enum Palette {
        public static let canvas = Color(nsColor: NSPalette.canvas)
        public static let card = Color(nsColor: NSPalette.card)
        public static let surface = card
        public static let ink = Color(nsColor: NSPalette.ink)
        public static let muted = Color(nsColor: NSPalette.muted)
        public static let line = Color(nsColor: NSPalette.line)
        public static let primary = Color(nsColor: NSPalette.primary)
        public static let abMHue = Color(nsColor: NSPalette.abMHue)
        public static let onPrimary = Color(nsColor: NSPalette.onPrimary)
        public static let accent = Color(nsColor: NSPalette.accent)
        public static let onAccent = Color(nsColor: NSPalette.onAccent)
        public static let primaryText = Color(nsColor: NSPalette.primaryText)
        public static let priTint = Color(nsColor: NSPalette.priTint)
        public static let secTint = Color(nsColor: NSPalette.secTint)
        public static let error = Color(nsColor: NSPalette.error)
        public static let onError = Color(nsColor: NSPalette.onError)
        public static let abMuted = Color(nsColor: NSPalette.abMuted)
        public static let abFill = Color(nsColor: NSPalette.abFill)
        public static let abHair = Color(nsColor: NSPalette.abHair)
        public static let ring = Color(nsColor: NSPalette.ring)
        public static let shadowNear = Color(nsColor: NSPalette.shadowNear)
        public static let shadowFar = Color(nsColor: NSPalette.shadowFar)
        public static let shadowSoft = Color(nsColor: NSPalette.shadowSoft)
        public static let shadowDeep = Color(nsColor: NSPalette.shadowDeep)
        public static let pressedInset = Color(nsColor: NSPalette.pressedInset)
        public static let topLight = Color(nsColor: NSPalette.topLight)

        /// The one gradient: primary to abMHue. 135° on buttons, 140° on selection.
        public static let gradient = LinearGradient(colors: [primary, abMHue], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let selectionGradient = LinearGradient(colors: [primary, abMHue],
                                                             startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1))
    }

    // MARK: Shape and spacing (Mac translation of the phone kit, plan 2026-11-10)

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
        public static let field: CGFloat = 12
        /// Pill. Clamped to half the height by SwiftUI.
        public static let chip: CGFloat = 999
        public static let button: CGFloat = 999
        public static let card: CGFloat = 20
        public static let popover: CGFloat = 20
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Size {
        /// Toolbar items, chips, segmented.
        public static let control: CGFloat = 30
        public static let button: CGFloat = 34
        public static let field: CGFloat = 32
        public static let row: CGFloat = 36
        public static let toolbarHeight: CGFloat = 52
    }

    /// Springs (Walker asked for bouncy, active, premium). Reduce Motion: use `Brand.Motion.resolved`.
    public enum Motion {
        public static let press = Animation.spring(response: 0.22, dampingFraction: 0.62)
        public static let settle = Animation.spring(response: 0.36, dampingFraction: 0.74)
        public static let enter = Animation.spring(response: 0.42, dampingFraction: 0.8)
        public static let pressScale: CGFloat = 0.97

        /// nil (no movement) when Reduce Motion is on.
        public static func resolved(_ a: Animation, reduceMotion: Bool) -> Animation? { reduceMotion ? nil : a }
    }

    // MARK: Fonts

    public enum Fonts {
        public static let headingFamily = "Plus Jakarta Sans"
        public static let headingWeight = "600"
        public static let headingSize: CGFloat = 22
        public static let headingTracking: CGFloat = -0.22
        public static let bodyFamily = "Inter"
        public static let bodyWeight = "400"
        public static let bodySize: CGFloat = 14
        public static let bodyTracking: CGFloat = 0

        /// Mac type scale (plan 2026-11-10): size, line height.
        public enum Scale {
            public static let display: CGFloat = 30
            public static let largeTitle: CGFloat = 26
            public static let title: CGFloat = 22
            public static let title2: CGFloat = 17
            public static let headline: CGFloat = 14
            public static let body: CGFloat = 14
            public static let callout: CGFloat = 13
            public static let footnote: CGFloat = 12
            public static let caption: CGFloat = 11
        }

        /// PostScript names read from the bundled files.
        public enum PostScript {
            public static let regular = "Inter18pt-Regular"
            public static let medium = "Inter18pt-Medium"
            public static let semibold = "Inter18pt-SemiBold"
            /// Named instances of the Plus Jakarta Sans variable font.
            public static let headingSemibold = "PlusJakartaSans-Regular_SemiBold"
            public static let displayLight = "PlusJakartaSans-Regular_Light"
            public static let mono = "GeistMono-Regular"
            public static let all = [regular, medium, semibold, headingSemibold, displayLight, mono]
        }

        public enum Weight { case regular, medium, semibold }

        static func postScript(_ weight: Weight) -> String {
            switch weight {
            case .regular: PostScript.regular
            case .medium: PostScript.medium
            case .semibold: PostScript.semibold
            }
        }

        public static func body(_ size: CGFloat = Fonts.bodySize, weight: Weight = .regular) -> Font {
            _ = Brand.fontsRegistered
            return .custom(postScript(weight), fixedSize: size)
        }

        /// Plus Jakarta Sans 600 for titles. Pair with `.brandHeading` for its tracking.
        public static func heading(_ size: CGFloat = Fonts.headingSize) -> Font {
            _ = Brand.fontsRegistered
            return .custom(PostScript.headingSemibold, fixedSize: size)
        }

        /// Plus Jakarta Sans 300 for the one display title (welcome).
        public static func display(_ size: CGFloat = Scale.display) -> Font {
            _ = Brand.fontsRegistered
            return .custom(PostScript.displayLight, fixedSize: size)
        }

        public static func mono(_ size: CGFloat = Fonts.bodySize) -> Font {
            _ = Brand.fontsRegistered
            return .custom(PostScript.mono, fixedSize: size)
        }

        public static func nsBody(_ size: CGFloat = Fonts.bodySize, weight: Weight = .regular) -> NSFont {
            _ = Brand.fontsRegistered
            return NSFont(name: postScript(weight), size: size) ?? .systemFont(ofSize: size)
        }

        public static func nsHeading(_ size: CGFloat = Fonts.headingSize) -> NSFont {
            _ = Brand.fontsRegistered
            return NSFont(name: PostScript.headingSemibold, size: size) ?? .boldSystemFont(ofSize: size)
        }

        public static func nsMono(_ size: CGFloat = Fonts.bodySize) -> NSFont {
            _ = Brand.fontsRegistered
            return NSFont(name: PostScript.mono, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    // MARK: Font registration

    /// Registers the bundled font files for this process. Safe to call repeatedly. Call once at launch.
    @discardableResult
    public static func registerFonts() -> Bool { fontsRegistered }

    static let fontsRegistered: Bool = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil)
                ?? Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
              !urls.isEmpty else { return false }
        var ok = true
        for url in urls {
            var error: Unmanaged<CFError>?
            // "Already registered" counts as success.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
                if code != CFIndex(CTFontManagerError.alreadyRegistered.rawValue) { ok = false }
            }
        }
        return ok
    }()
}

extension NSColor {
    static func brand(light: String, dark: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(brandHex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }

    convenience init(brandHex hex: String, alpha: CGFloat = 1) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: alpha)
    }
}
