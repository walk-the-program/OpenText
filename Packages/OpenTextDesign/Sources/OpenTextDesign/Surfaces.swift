import SwiftUI

/// Bento Grid surfaces: tiles on a darker canvas, the contrast between them is the only depth. No borders,
/// no shadows on tiles; fields, tracks and drop zones are a quiet `well` fill inside a tile.
extension View {
    /// Tile (`.card`) or small filled control such as a chip (`.control`). Older name kept from Soft Form.
    public func raisedSurface(radius: CGFloat = Brand.Radius.card, fill: Color = Brand.Palette.card,
                              depth: SurfaceDepth = .card) -> some View {
        modifier(CardSurface(radius: radius, depth: depth, lifted: false))
    }

    /// Tile; `lifted` (hover) brightens the fill a touch instead of casting a shadow.
    public func cardSurface(radius: CGFloat = Brand.Radius.card, lifted: Bool = false) -> some View {
        modifier(CardSurface(radius: radius, depth: .card, lifted: lifted))
    }

    /// Well: fields, tracks, drop zones, secondary fills. Older name kept from Soft Form.
    public func recessedSurface(radius: CGFloat = Brand.Radius.field, fill: Color = Brand.Palette.well) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Brand.Palette.well))
    }

    /// Floating panel (sheet, popover, notice, toast): a tile with a soft shadow so it reads above the window.
    public func floatingSurface(radius: CGFloat = Brand.Radius.popover) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Brand.Palette.card)
                .shadow(color: Brand.Palette.shadowNear, radius: 2, y: 1)
                .shadow(color: Brand.Palette.shadowFar, radius: 22, y: 14))
    }

    /// Flat paper (document page, toolbar).
    public func paperSurface() -> some View { background(Brand.Palette.card) }

    /// Single-line field: 38pt, 12pt corners, well fill, Geist 15 medium. Pass `focused` (from the caller's own
    /// @FocusState) to show the kit focus: tile fill with a 2pt primary ring.
    public func brandField(focused: Bool = false) -> some View { modifier(FieldSurface(focused: focused)) }

    /// Titles: Geist 600, tracking -0.015em.
    public func brandHeading(_ size: CGFloat = Brand.Fonts.headingSize) -> some View {
        font(Brand.Fonts.heading(size)).tracking(-0.015 * size).foregroundStyle(Brand.Palette.ink)
    }

    /// The one display title (welcome): Geist 300, tracking -0.01em.
    public func brandDisplay(_ size: CGFloat = Brand.Fonts.Scale.display) -> some View {
        font(Brand.Fonts.display(size)).tracking(-0.01 * size).foregroundStyle(Brand.Palette.ink)
    }

    /// Section label: Geist 600, 12pt, sentence case, muted.
    public func brandLabel() -> some View {
        font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.muted)
    }

    /// Body text: Geist 14 regular, ink.
    public func brandBody(_ size: CGFloat = Brand.Fonts.bodySize) -> some View {
        font(Brand.Fonts.body(size)).foregroundStyle(Brand.Palette.ink)
    }

    /// Secondary text: Geist 13, muted.
    public func brandSecondary(_ size: CGFloat = Brand.Fonts.Scale.callout) -> some View {
        font(Brand.Fonts.body(size)).foregroundStyle(Brand.Palette.muted)
    }

    /// Content entering (window, sheet, panel): opacity, scale 0.98 to 1 and a 6pt rise on a spring, once.
    /// `delay` staggers siblings. Reduce Motion: appears at once.
    public func brandEnter(delay: Double = 0) -> some View { modifier(EnterModifier(delay: delay)) }

    /// A quick horizontal shake when `trigger` changes to a non-nil value (wrong password, invalid name).
    public func brandShake<T: Equatable>(trigger: T?) -> some View { modifier(ShakeModifier(trigger: trigger)) }

    /// Hover lift for cards and rows: tracks the pointer and passes `hovering` to the content via the closure.
    public func brandHover(_ hovering: Binding<Bool>) -> some View { modifier(HoverModifier(hovering: hovering)) }
}

/// Shadow scale: `.control` is the small kit shadow for chips and buttons.
public enum SurfaceDepth: Sendable { case card, control }

struct CardSurface: ViewModifier {
    let radius: CGFloat
    let depth: SurfaceDepth
    let lifted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: radius >= 100 ? .circular : .continuous)
        content
            .background(shape.fill(depth == .card ? Brand.Palette.card : Brand.Palette.well))
            .overlay(shape.fill(Color.white.opacity(lifted ? 0.035 : 0)).allowsHitTesting(false))
            .animation(Brand.Motion.resolved(Brand.Motion.settle, reduceMotion: reduceMotion), value: lifted)
    }
}

struct FieldSurface: ViewModifier {
    let focused: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(Brand.Fonts.body(15, weight: .medium))
            .foregroundStyle(Brand.Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: Brand.Size.field)
            .background(shape.fill(focused ? Brand.Palette.card : Brand.Palette.well))
            .overlay(shape.strokeBorder(Brand.Palette.primary, lineWidth: focused ? 2 : 0).allowsHitTesting(false))
            .animation(Brand.Motion.settle, value: focused)
    }
}

struct EnterModifier: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.brandStaticRendering) private var staticRendering
    private var reduceMotion: Bool { systemReduceMotion || staticRendering }

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.98)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else { withAnimation(Brand.Motion.enter.delay(delay)) { shown = true } }
            }
    }
}

struct HoverModifier: ViewModifier {
    @Binding var hovering: Bool
    func body(content: Content) -> some View {
        content.onHover { hovering = $0 }
    }
}

extension EnvironmentValues {
    /// Snapshot rendering: everything appears in its final state, no entrance motion.
    @Entry public var brandStaticRendering: Bool = false
}

struct ShakeModifier<T: Equatable>: ViewModifier {
    let trigger: T?
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(phase: phase))
            .onChange(of: trigger) { _, new in
                guard new != nil, !reduceMotion else { return }
                phase = 0
                withAnimation(.linear(duration: 0.36)) { phase = 1 }
            }
    }
}

struct ShakeEffect: GeometryEffect {
    var phase: CGFloat
    var animatableData: CGFloat { get { phase } set { phase = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(phase * .pi * 6) * (1 - phase), y: 0))
    }
}
