import SwiftUI

/// The one primary action per window: gradient pill (primary to abMHue, 135°), on-primary label, trailing arrow
/// in a white-veiled circle. Press: springs down to 0.97 with a recessed inner shadow. One view, values only.
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
            let shape = Capsule()
            HStack(spacing: 8) {
                configuration.label
                if showsArrow {
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                        .offset(x: hovering && isEnabled ? 2 : 0)
                }
            }
            .font(Brand.Fonts.body(13, weight: .semibold)).tracking(-0.13)
            .foregroundStyle(Brand.Palette.onPrimary)
            .padding(.leading, 18).padding(.trailing, showsArrow ? 7 : 18)
            .frame(height: Brand.Size.button)
            .background(shape.fill(Brand.Palette.gradient.shadow(.inner(color: pressed ? Brand.Palette.pressedInset : .clear, radius: 3, y: 2)))
                .shadow(color: Brand.Palette.shadowNear, radius: 1, y: 1)
                .shadow(color: Brand.Palette.shadowFar, radius: pressed ? 3 : (hovering ? 10 : 8), y: pressed ? 2 : (hovering ? 7 : 5)))
            .overlay(shape.strokeBorder(Brand.Palette.topLight, lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
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

/// Card-white pill with a fine ink ring; pressing tints it, insets it and springs it down. Disabled is faded.
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
                .font(Brand.Fonts.body(13, weight: .semibold)).tracking(-0.13)
                .foregroundStyle(Brand.Palette.ink)
                .padding(.horizontal, 16)
                .frame(height: Brand.Size.button)
                .background(SecondarySurface(pressed: pressed, enabled: isEnabled, hovering: hovering))
                .contentShape(Capsule())
                .scaleEffect(pressed ? Brand.Motion.pressScale : 1)
                .focusRing(isFocused, radius: Brand.Radius.button)
                .opacity(isEnabled ? 1 : 0.55)
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
        let shape = Capsule()
        shape.fill((pressed ? Brand.Palette.secTint : Brand.Palette.card)
                .shadow(.inner(color: pressed ? Brand.Palette.shadowSoft : .clear, radius: 3, y: 2)))
            .shadow(color: Brand.Palette.shadowNear.opacity(enabled ? 1 : 0), radius: 1, y: 1)
            .shadow(color: Brand.Palette.shadowSoft.opacity(enabled && !pressed ? 1 : 0), radius: hovering ? 7 : 5, y: hovering ? 4 : 3)
            .overlay(shape.inset(by: 0.5).stroke(Brand.Palette.ink.opacity(hovering && enabled ? 0.3 : 0.18), lineWidth: 1))
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
                    .fill(isActive ? Brand.Palette.priTint : (configuration.isPressed ? Brand.Palette.abFill : (hovering ? Brand.Palette.abFill.opacity(0.7) : .clear))))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                    .strokeBorder(Brand.Palette.primary.opacity(isActive ? 0.55 : 0), lineWidth: 1))
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
