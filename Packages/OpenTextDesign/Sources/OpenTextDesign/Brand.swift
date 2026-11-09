// Values mirror design/brand.json (and the extra tokens BUILD-PACK.md Part 1 lists). This is the only
// file that may contain colour literals. Change brand.json first, then update here.
import AppKit
import CoreText
import SwiftUI

public enum Brand {
    public static let appName = "OpenText"
    public static let accentBudget = 0.1

    // MARK: Colours

    /// AppKit colours. Dynamic: they resolve against the effective appearance (light/dark) at draw time.
    public enum NSPalette {
        public static let canvas = NSColor.brand(light: "#e8eaec", dark: "#252a2e")
        /// brand.json "surface" (BUILD-PACK "card").
        public static let surface = NSColor.brand(light: "#fafbfb", dark: "#33383c")
        public static let ink = NSColor.brand(light: "#1c2126", dark: "#f5f7f9")
        public static let muted = NSColor.brand(light: "#63676b", dark: "#a2a5a8")
        public static let line = NSColor.brand(light: "#c9ccce", dark: "#44494c")
        public static let primary = NSColor.brand(light: "#98b0cc", dark: "#98b0cc")
        public static let onPrimary = NSColor.brand(light: "#141414", dark: "#141414")
        public static let accent = NSColor.brand(light: "#cacd7e", dark: "#cacd7e")
        public static let onAccent = NSColor.brand(light: "#141414", dark: "#141414")
        // From BUILD-PACK Part 1 / the approved mocks.
        public static let primaryPressed = NSColor.brand(light: "#7d90a7", dark: "#7d90a7")
        public static let secTint = NSColor.brand(light: "#e7e6e8", dark: "#434548")
        public static let divider = NSColor.brand(light: "#e4e5e6", dark: "#464b4f")
        public static let abMuted = NSColor.brand(light: "#63676b", dark: "#dcdee1")
        public static let tileLine = NSColor.brand(light: "#1c2126", dark: "#f5f7f9", lightAlpha: 0.08, darkAlpha: 0.10)
        /// Soft Form lighting: shadow falls down-right, highlight up-left, in both modes.
        public static let shade = NSColor.brand(light: "#1c2126", dark: "#141414", lightAlpha: 0.15, darkAlpha: 0.60)
        public static let glow = NSColor.brand(light: "#fafbfb", dark: "#f5f7f9", lightAlpha: 0.95, darkAlpha: 0.07)
    }

    public enum Palette {
        public static let canvas = Color(nsColor: NSPalette.canvas)
        public static let surface = Color(nsColor: NSPalette.surface)
        public static let ink = Color(nsColor: NSPalette.ink)
        public static let muted = Color(nsColor: NSPalette.muted)
        public static let line = Color(nsColor: NSPalette.line)
        public static let primary = Color(nsColor: NSPalette.primary)
        public static let onPrimary = Color(nsColor: NSPalette.onPrimary)
        public static let accent = Color(nsColor: NSPalette.accent)
        public static let onAccent = Color(nsColor: NSPalette.onAccent)
        public static let primaryPressed = Color(nsColor: NSPalette.primaryPressed)
        public static let secTint = Color(nsColor: NSPalette.secTint)
        public static let divider = Color(nsColor: NSPalette.divider)
        public static let abMuted = Color(nsColor: NSPalette.abMuted)
        public static let tileLine = Color(nsColor: NSPalette.tileLine)
        public static let shade = Color(nsColor: NSPalette.shade)
        public static let glow = Color(nsColor: NSPalette.glow)
        /// Dimmed layer behind modal sheets.
        public static let scrim = ink.opacity(0.42)
    }

    // MARK: Shape and spacing (Mac scale)

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let field: CGFloat = 8
        public static let chip: CGFloat = 9
        public static let button: CGFloat = 10
        public static let card: CGFloat = 16
        public static let popover: CGFloat = 14
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
        public static let control: CGFloat = 28
        public static let toolbarHeight: CGFloat = 48
        public static let statusBarHeight: CGFloat = 28
    }

    public enum Motion {
        public static let quick = Animation.easeOut(duration: 0.12)
        public static let standard = Animation.easeInOut(duration: 0.18)
        public static let slow = Animation.easeInOut(duration: 0.28)
    }

    // MARK: Fonts

    public enum Fonts {
        public static let headingFamily = "Inter Tight"
        public static let headingWeight = "600"
        public static let headingSize: CGFloat = 20
        public static let headingTracking: CGFloat = -0.8
        public static let bodyFamily = "Inter"
        public static let bodyWeight = "400"
        public static let bodySize: CGFloat = 13
        public static let bodyTracking: CGFloat = 0

        /// PostScript names read from the bundled TTFs (Inter 18pt text cut, Inter Tight variable for headings).
        public enum PostScript {
            public static let regular = "Inter18pt-Regular"
            public static let medium = "Inter18pt-Medium"
            public static let semibold = "Inter18pt-SemiBold"
            /// Named instance of the Inter Tight variable font (weight axis 600).
            public static let headingSemibold = "InterTight-Regular_SemiBold"
            public static let all = [regular, medium, semibold, headingSemibold]
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

        /// Inter Tight 600 (D-020). Pair with `.brandHeading` for the pack's tight tracking.
        public static func heading(_ size: CGFloat = Fonts.headingSize) -> Font {
            _ = Brand.fontsRegistered
            return .custom(PostScript.headingSemibold, fixedSize: size)
        }

        public static func nsBody(_ size: CGFloat = Fonts.bodySize, weight: Weight = .regular) -> NSFont {
            _ = Brand.fontsRegistered
            return NSFont(name: postScript(weight), size: size) ?? .systemFont(ofSize: size)
        }

        public static func nsHeading(_ size: CGFloat = Fonts.headingSize) -> NSFont {
            _ = Brand.fontsRegistered
            return NSFont(name: PostScript.headingSemibold, size: size) ?? .boldSystemFont(ofSize: size)
        }
    }

    // MARK: Font registration

    /// Registers the bundled Inter files for this process. Safe to call repeatedly. Call once at launch.
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
