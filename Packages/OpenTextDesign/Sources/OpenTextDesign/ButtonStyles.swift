import SwiftUI

/// The one primary action per window: `Palette.primary` fill, on-primary label, trailing diagonal arrow.
public struct PrimaryActionButtonStyle: ButtonStyle {
    public var showsArrow: Bool
    public init(showsArrow: Bool = true) { self.showsArrow = showsArrow }
    public func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration, showsArrow: showsArrow) }

    struct StyledBody: View {
        let configuration: Configuration
        let showsArrow: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            HStack(spacing: 6) {
                configuration.label
                if showsArrow { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)) }
            }
            .font(Brand.Fonts.body(13, weight: .semibold)).tracking(-0.13)
            .foregroundStyle(Brand.Palette.onPrimary)
            .padding(.leading, 16).padding(.trailing, showsArrow ? 10 : 16)
            .frame(height: Brand.Size.control)
            .background(RoundedRectangle(cornerRadius: Brand.Radius.button, style: .continuous)
                .fill(configuration.isPressed ? Brand.Palette.primaryPressed : Brand.Palette.primary))
            .focusRing(isFocused, radius: Brand.Radius.button)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Brand.Motion.quick, value: configuration.isPressed)
        }
    }
}

/// Raised canvas button; pressing flips it to recessed, disabled is flat canvas.
///
/// The view tree never changes between those states, only the values drawn by `SecondarySurface`. Swapping
/// branches on `isPressed` would replace the button's view mid-click, and the click would never complete.
public struct SecondaryActionButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration) }

    struct StyledBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .font(Brand.Fonts.body(13, weight: .semibold)).tracking(-0.13)
                .foregroundStyle(Brand.Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: Brand.Size.control)
                .background(SecondarySurface(pressed: pressed, enabled: isEnabled))
                .focusRing(isFocused, radius: Brand.Radius.button)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Brand.Motion.quick, value: pressed)
        }
    }
}

/// Canvas surface of the secondary button. One view; `pressed` and `enabled` only change values: the raised
/// shadows fade out and the recessed inner shading fades in.
struct SecondarySurface: View {
    let pressed: Bool
    let enabled: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.Radius.button, style: .continuous)
        let raised = enabled && !pressed
        shape.fill(Brand.Palette.canvas)
            .shadow(color: Brand.Palette.glow.opacity(raised ? 1 : 0), radius: 1, x: -1, y: -1)
            .shadow(color: Brand.Palette.shade.opacity(raised ? 1 : 0), radius: 2, x: 1, y: 1.5)
            .overlay(
                ZStack {
                    shape.stroke(Brand.Palette.shade, lineWidth: 4).blur(radius: 3).offset(x: 1.5, y: 1.5).opacity(pressed ? 0.6 : 0)
                    shape.stroke(Brand.Palette.glow, lineWidth: 4).blur(radius: 3).offset(x: -1.5, y: -1.5).opacity(pressed ? 0.8 : 0)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            )
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
                    .fill(isActive || configuration.isPressed ? Brand.Palette.secTint : (hovering ? Brand.Palette.secTint.opacity(0.6) : .clear)))
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
        overlay(RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
            .stroke(Brand.Palette.ink, lineWidth: 2).padding(-3).opacity(on ? 1 : 0))
    }
}
