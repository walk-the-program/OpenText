// Values mirror design/brand.json: Bento Grid with Geist (D-023, approved Looks Good round 3, design/looks-good-build-pack.md). This is the only
// file that may contain colour literals. Change brand.json first, then update here.
import AppKit
import CoreText
import SwiftUI

public enum Brand {
    public static let appName = "OpenText"
    public static let accentBudget = 0.1

    // MARK: Colours (Bento Grid on OpenText steel, Looks Good round 3)

    /// AppKit colours. Dynamic: they resolve against the effective appearance (light/dark) at draw time.
    public enum NSPalette {
        /// Window ground: tiles sit on it; contrast between the two is the only depth (no borders, no shadows).
        public static let canvas = NSColor.brand(light: "#e8eaed", dark: "#121417")
        /// Tile fill (cards, panels, the document page column). `surface` is the older name.
        public static let card = NSColor.brand(light: "#fbfbfc", dark: "#1d2024")
        public static let surface = card
        /// Quiet fill inside a tile: fields, tracks, secondary buttons, drop zones.
        public static let well = NSColor.brand(light: "#eff1f3", dark: "#25292e")
        /// Window toolbar strip.
        public static let chrome = NSColor.brand(light: "#f3f4f6", dark: "#181b1f")
        public static let ink = NSColor.brand(light: "#16191d", dark: "#eef0f2")
        public static let muted = NSColor.brand(light: "#646b74", dark: "#a0a7b0")
        public static let faint = NSColor.brand(light: "#9aa1aa", dark: "#6c737c")
        public static let line = NSColor.brand(light: "#16191d", dark: "#eef0f2", lightAlpha: 0.07, darkAlpha: 0.08)
        /// Steel blue: the primary button and every selection.
        public static let primary = NSColor.brand(light: "#5d7189", dark: "#7d92ab")
        public static let primaryPressed = NSColor.brand(light: "#4c5d72", dark: "#6a7e96")
        public static let onPrimary = NSColor.brand(light: "#ffffff", dark: "#0f1215")
        /// Citron: highlights only (the logo's fold is the same family).
        public static let accent = NSColor.brand(light: "#cacd7e", dark: "#cacd7e")
        public static let onAccent = NSColor.brand(light: "#141414", dark: "#141414")
        /// Links and tinted text (the primary itself holds 4.5:1 on tiles).
        public static let primaryText = primary
        public static let priTint = NSColor.brand(light: "#e3e8ee", dark: "#2a323c")
        public static let secTint = well
        public static let error = ink
        public static let onError = NSColor.brand(light: "#eef0f2", dark: "#16191d")
        public static let abMuted = muted
        public static let abFill = well
        public static let abHair = line
        public static let ring = NSColor.brand(light: "#5d7189", dark: "#7d92ab", lightAlpha: 0.35, darkAlpha: 0.4)
        /// Floating sheets and toasts only; tiles never cast a shadow.
        public static let shadowNear = NSColor.brand(light: "#16191d", dark: "#000000", lightAlpha: 0.06, darkAlpha: 0.3)
        public static let shadowFar = NSColor.brand(light: "#16191d", dark: "#000000", lightAlpha: 0.14, darkAlpha: 0.45)
        public static let shadowSoft = shadowNear
        public static let shadowDeep = shadowFar
        public static let pressedInset = shadowNear
        public static let topLight = NSColor.brand(light: "#ffffff", dark: "#ffffff", lightAlpha: 0.18, darkAlpha: 0.12)
        /// Kept so older call sites compile: the gradient stop is the primary itself (Bento has no gradients).
        public static let abMHue = primary
    }

    /// Logo-only colours (the apricot app icon). The same in light and dark and never UI fills.
    public enum Mark {
        public static let groundNS = NSColor(brandHex: "#ffc79b")
        public static let pageNS = NSColor(brandHex: "#ffffff")
        public static let inkNS = NSColor(brandHex: "#1e1f21")
        public static let foldNS = NSColor(brandHex: "#e2e58a")
        public static let ground = Color(nsColor: groundNS)
        public static let fold = Color(nsColor: foldNS)
    }

    public enum Palette {
        public static let canvas = Color(nsColor: NSPalette.canvas)
        public static let card = Color(nsColor: NSPalette.card)
        public static let surface = card
        public static let well = Color(nsColor: NSPalette.well)
        public static let chrome = Color(nsColor: NSPalette.chrome)
        public static let ink = Color(nsColor: NSPalette.ink)
        public static let muted = Color(nsColor: NSPalette.muted)
        public static let faint = Color(nsColor: NSPalette.faint)
        public static let line = Color(nsColor: NSPalette.line)
        public static let primary = Color(nsColor: NSPalette.primary)
        public static let primaryPressed = Color(nsColor: NSPalette.primaryPressed)
        public static let abMHue = primary
        public static let onPrimary = Color(nsColor: NSPalette.onPrimary)
        public static let accent = Color(nsColor: NSPalette.accent)
        public static let onAccent = Color(nsColor: NSPalette.onAccent)
        public static let primaryText = Color(nsColor: NSPalette.primaryText)
        public static let priTint = Color(nsColor: NSPalette.priTint)
        public static let secTint = well
        public static let error = Color(nsColor: NSPalette.error)
        public static let onError = Color(nsColor: NSPalette.onError)
        public static let abMuted = muted
        public static let abFill = well
        public static let abHair = line
        public static let ring = Color(nsColor: NSPalette.ring)
        public static let shadowNear = Color(nsColor: NSPalette.shadowNear)
        public static let shadowFar = Color(nsColor: NSPalette.shadowFar)
        public static let shadowSoft = shadowNear
        public static let shadowDeep = shadowFar
        public static let pressedInset = shadowNear
        public static let topLight = Color(nsColor: NSPalette.topLight)

        /// Bento has no gradients: these older names now fill flat with the primary.
        public static let gradient = LinearGradient(colors: [primary, primary], startPoint: .top, endPoint: .bottom)
        public static let selectionGradient = gradient
    }

    // MARK: Shape and spacing (Mac translation of the phone kit, plan 2026-11-10)

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 9
        public static let lg: CGFloat = 14
        public static let field: CGFloat = 12
        public static let chip: CGFloat = 8
        public static let button: CGFloat = 12
        /// Tiles (Bento Grid kit 24-28, scaled for the Mac).
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
        public static let button: CGFloat = 36
        public static let field: CGFloat = 38
        public static let row: CGFloat = 40
        public static let toolbarHeight: CGFloat = 52
    }

    /// Springs (Walker asked for bouncy, active, premium). Reduce Motion: use `Brand.Motion.resolved`.
    /// Press is the Bento kit's: scale 0.96 and a darker fill.
    public enum Motion {
        public static let press = Animation.spring(response: 0.22, dampingFraction: 0.62)
        public static let settle = Animation.spring(response: 0.36, dampingFraction: 0.74)
        public static let enter = Animation.spring(response: 0.42, dampingFraction: 0.8)
        public static let pressScale: CGFloat = 0.96

        /// nil (no movement) when Reduce Motion is on.
        public static func resolved(_ a: Animation, reduceMotion: Bool) -> Animation? { reduceMotion ? nil : a }
    }

    // MARK: Fonts

    public enum Fonts {
        public static let headingFamily = "Geist"
        public static let headingWeight = "600"
        public static let headingSize: CGFloat = 22
        public static let headingTracking: CGFloat = -0.33
        public static let bodyFamily = "Geist"
        public static let bodyWeight = "400"
        public static let bodySize: CGFloat = 14
        public static let bodyTracking: CGFloat = 0

        /// Mac type scale: size in points.
        public enum Scale {
            public static let display: CGFloat = 30
            public static let largeTitle: CGFloat = 24
            public static let title: CGFloat = 21
            public static let title2: CGFloat = 17
            public static let headline: CGFloat = 14
            public static let body: CGFloat = 14
            public static let callout: CGFloat = 13
            public static let footnote: CGFloat = 12
            public static let caption: CGFloat = 11
        }

        /// PostScript names of the named instances in the bundled Geist variable font, plus Geist Mono.
        public enum PostScript {
            public static let regular = "Geist-Regular"
            public static let medium = "Geist-Medium"
            public static let semibold = "Geist-SemiBold"
            public static let headingSemibold = semibold
            public static let displayLight = "Geist-Light"
            public static let mono = "GeistMono-Regular"
            public static let all = [regular, medium, semibold, displayLight, mono]
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

        /// Geist 600 for titles. Pair with `.brandHeading` for its tracking.
        public static func heading(_ size: CGFloat = Fonts.headingSize) -> Font {
            _ = Brand.fontsRegistered
            return .custom(PostScript.headingSemibold, fixedSize: size)
        }

        /// Geist 300 for the one display title (welcome).
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
        // CoreText reads both TrueType and WOFF2 (Geist ships as a variable WOFF2).
        let urls = ["ttf", "woff2"].flatMap { ext in
            Bundle.module.urls(forResourcesWithExtension: ext, subdirectory: nil)
                ?? Bundle.module.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? []
        }
        guard !urls.isEmpty else { return false }
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
