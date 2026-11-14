import SwiftUI

/// The one primary action per window: solid steel, white label, a trailing arrow in a veiled square (Bento Grid
/// CTA). Press: scale 0.96 and the darker steel. One view, values only.
public struct PrimaryActionButtonStyle: ButtonStyle {
    public var showsArrow: Bool
    public init(showsArrow: Bool = true) { self.showsArrow = showsArrow }
    public func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration, showsArrow: showsArrow) }

    struct StyledBody: View {
        let configuration: Configuration
        let showsArrow: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            let shape = RoundedRectangle(cornerRadius: Brand.Radius.button, style: .continuous)
            HStack(spacing: 10) {
                configuration.label
                if showsArrow {
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.18)))
                        .offset(x: hovering && isEnabled ? 1.5 : 0)
                }
            }
            .font(Brand.Fonts.body(13.5, weight: .semibold)).tracking(-0.14)
            .foregroundStyle(Brand.Palette.onPrimary)
            .padding(.leading, 16).padding(.trailing, showsArrow ? 5 : 16)
            .frame(height: Brand.Size.button)
            .background(shape.fill(pressed ? Brand.Palette.primaryPressed : Brand.Palette.primary))
            .contentShape(shape)
            .scaleEffect(pressed ? Brand.Motion.pressScale : 1)
            .focusRing(isFocused, radius: Brand.Radius.button)
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering = $0 }
            .animation(Brand.Motion.resolved(Brand.Motion.press, reduceMotion: reduceMotion), value: pressed)
            .animation(Brand.Motion.resolved(Brand.Motion.settle, reduceMotion: reduceMotion), value: hovering)
        }
    }
}

/// Filled well button; pressing turns it ink with a light label and springs it down (Bento Grid secondary).
///
/// The view tree never changes between states, only the values drawn by `SecondarySurface`. Swapping
/// branches on `isPressed` would replace the button's view mid-click, and the click would never complete.
public struct SecondaryActionButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration) }

    struct StyledBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .font(Brand.Fonts.body(13.5, weight: .semibold)).tracking(-0.14)
                .foregroundStyle(pressed ? Brand.Palette.canvas : Brand.Palette.ink)
                .padding(.horizontal, 16)
                .frame(height: Brand.Size.button)
                .background(SecondarySurface(pressed: pressed, enabled: isEnabled, hovering: hovering))
                .contentShape(RoundedRectangle(cornerRadius: Brand.Radius.button, style: .continuous))
                .scaleEffect(pressed ? Brand.Motion.pressScale : 1)
                .focusRing(isFocused, radius: Brand.Radius.button)
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { hovering = $0 }
                .animation(Brand.Motion.resolved(Brand.Motion.press, reduceMotion: reduceMotion), value: pressed)
                .animation(Brand.Motion.resolved(Brand.Motion.settle, reduceMotion: reduceMotion), value: hovering)
        }
    }
}

/// Surface of the secondary button. One view; `pressed`, `enabled` and `hovering` only change values.
struct SecondarySurface: View {
    let pressed: Bool
    let enabled: Bool
    var hovering: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: Brand.Radius.button, style: .continuous)
            .fill(pressed ? Brand.Palette.ink : Brand.Palette.well)
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.button, style: .continuous)
                .fill(Brand.Palette.ink.opacity(hovering && enabled && !pressed ? 0.05 : 0)))
    }
}

/// Flat text tool in a toolbar: Highlight, Sign, Rotate... `isActive` marks a tool that is switched on.
public struct ToolbarItemButtonStyle: ButtonStyle {
    public var isActive: Bool
    public init(isActive: Bool = false) { self.isActive = isActive }
    public func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration, isActive: isActive) }

    struct StyledBody: View {
        let configuration: Configuration
        let isActive: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(Brand.Fonts.body(13, weight: .medium))
                .foregroundStyle(Brand.Palette.ink)
                .padding(.horizontal, 10)
                .frame(height: Brand.Size.control)
                .background(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                    .fill(isActive ? Brand.Palette.priTint : (configuration.isPressed ? Brand.Palette.well : (hovering ? Brand.Palette.well.opacity(0.7) : .clear))))
                .scaleEffect(configuration.isPressed ? Brand.Motion.pressScale : 1)
                .animation(Brand.Motion.press, value: configuration.isPressed)
                .animation(Brand.Motion.settle, value: hovering)
                .animation(Brand.Motion.settle, value: isActive)
                .focusRing(isFocused, radius: Brand.Radius.md)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    public static var primaryAction: PrimaryActionButtonStyle { .init() }
    public static func primaryAction(showsArrow: Bool) -> PrimaryActionButtonStyle { .init(showsArrow: showsArrow) }
}
extension ButtonStyle where Self == SecondaryActionButtonStyle {
    public static var secondaryAction: SecondaryActionButtonStyle { .init() }
}
extension ButtonStyle where Self == ToolbarItemButtonStyle {
    public static var toolbarItem: ToolbarItemButtonStyle { .init() }
    public static func toolbarItem(isActive: Bool) -> ToolbarItemButtonStyle { .init(isActive: isActive) }
}

extension View {
    /// Visible keyboard focus (only drawn when the system reports focus, i.e. keyboard navigation).
    func focusRing(_ on: Bool, radius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius + 3, style: radius >= 100 ? .circular : .continuous)
            .stroke(Brand.Palette.primaryText, lineWidth: 2).padding(-4).opacity(on ? 1 : 0).allowsHitTesting(false))
    }
}
