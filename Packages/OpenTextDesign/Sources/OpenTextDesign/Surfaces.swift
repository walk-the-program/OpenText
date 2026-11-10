import SwiftUI

/// Mesh Gradient surfaces: opaque white cards with a hairline and a two-layer neutral shadow, quiet wells,
/// fields with a fine edge. Nothing neumorphic, nothing translucent.
extension View {
    /// Card (`.card` depth) or small raised control such as a chip (`.control` depth).
    /// Older name kept from Soft Form; it now draws the kit card.
    public func raisedSurface(radius: CGFloat = Brand.Radius.card, fill: Color = Brand.Palette.card,
                              depth: SurfaceDepth = .card) -> some View {
        modifier(CardSurface(radius: radius, depth: depth, lifted: false))
    }

    /// Card that lifts (deeper shadow, 1pt up) while `lifted` is true, e.g. on hover.
    public func cardSurface(radius: CGFloat = Brand.Radius.card, lifted: Bool = false) -> some View {
        modifier(CardSurface(radius: radius, depth: .card, lifted: lifted))
    }

    /// Well: drop zones, tracks, quiet groups. Older name kept from Soft Form.
    public func recessedSurface(radius: CGFloat = Brand.Radius.field, fill: Color = Brand.Palette.abFill) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Brand.Palette.abFill))
            .overlay(shape.strokeBorder(Brand.Palette.abHair, lineWidth: 1))
    }

    /// Floating panel (popover, sheet, notice): card fill, hairline, large soft shadow.
    public func floatingSurface(radius: CGFloat = Brand.Radius.popover) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Brand.Palette.card)
                .shadow(color: Brand.Palette.shadowNear, radius: 2, y: 2)
                .shadow(color: Brand.Palette.shadowDeep, radius: 20, y: 18))
            .overlay(shape.strokeBorder(Brand.Palette.abHair, lineWidth: 1))
    }

    /// Flat paper (document page, toolbar).
    public func paperSurface() -> some View { background(Brand.Palette.card) }

    /// Single-line field: 32pt, 12pt corners, card fill, fine ink edge, Inter 14. Pass `focused` (from the
    /// caller's own @FocusState) to draw the kit's focus ring; the field itself owns no focus state.
    public func brandField(focused: Bool = false) -> some View { modifier(FieldSurface(focused: focused)) }

    /// Titles: Plus Jakarta Sans 600, tracking -0.01em.
    public func brandHeading(_ size: CGFloat = Brand.Fonts.headingSize) -> some View {
        font(Brand.Fonts.heading(size)).tracking(-0.01 * size).foregroundStyle(Brand.Palette.ink)
    }

    /// The one display title (welcome): Plus Jakarta Sans 300, tracking -0.01em.
    public func brandDisplay(_ size: CGFloat = Brand.Fonts.Scale.display) -> some View {
        font(Brand.Fonts.display(size)).tracking(-0.01 * size).foregroundStyle(Brand.Palette.ink)
    }

    /// Section label: Inter 600, 11pt, uppercase, tracking +0.1em, abMuted.
    public func brandLabel() -> some View {
        font(Brand.Fonts.body(Brand.Fonts.Scale.caption, weight: .semibold)).textCase(.uppercase)
            .tracking(1.1).foregroundStyle(Brand.Palette.abMuted)
    }

    /// Body text: Inter 14 regular, ink.
    public func brandBody(_ size: CGFloat = Brand.Fonts.bodySize) -> some View {
        font(Brand.Fonts.body(size)).foregroundStyle(Brand.Palette.ink)
    }

    /// Secondary text: Inter 13, muted.
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
        // Pills (radius 999) use circular corners: a continuous-style pill draws short flat sides.
        let shape = RoundedRectangle(cornerRadius: radius, style: radius >= 100 ? .circular : .continuous)
        let card = depth == .card
        content
            .background(shape.fill(Brand.Palette.card)
                .shadow(color: Brand.Palette.shadowNear, radius: 1, y: 1)
                .shadow(color: card ? Brand.Palette.shadowFar : Brand.Palette.shadowSoft,
                        radius: card ? (lifted ? 16 : 9) : 5, y: card ? (lifted ? 12 : 6) : 3))
            .overlay(shape.strokeBorder(Brand.Palette.abHair, lineWidth: 1))
            .offset(y: lifted ? -1 : 0)
            .animation(Brand.Motion.resolved(Brand.Motion.settle, reduceMotion: reduceMotion), value: lifted)
    }
}

struct FieldSurface: ViewModifier {
    let focused: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(Brand.Fonts.body(14))
            .foregroundStyle(Brand.Palette.ink)
            .padding(.horizontal, Brand.Spacing.md)
            .frame(height: Brand.Size.field)
            .background(shape.fill(Brand.Palette.card)
                .shadow(color: Brand.Palette.shadowNear, radius: 1, y: 1)
                .shadow(color: Brand.Palette.shadowSoft, radius: 5, y: 3))
            .overlay(shape.strokeBorder(focused ? Brand.Palette.primaryText : Brand.Palette.ink.opacity(0.22), lineWidth: 1))
            .overlay(shape.inset(by: -3).stroke(Brand.Palette.ring, lineWidth: focused ? 3 : 0).allowsHitTesting(false))
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
