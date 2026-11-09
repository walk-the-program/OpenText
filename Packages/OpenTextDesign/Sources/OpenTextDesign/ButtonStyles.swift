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

/// Raised canvas button; pressing flips it to recessed.
public struct SecondaryActionButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration) }

    struct StyledBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            let base = configuration.label
                .font(Brand.Fonts.body(13, weight: .semibold)).tracking(-0.13)
                .foregroundStyle(Brand.Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: Brand.Size.control)
            Group {
                if !isEnabled { base.background(RoundedRectangle(cornerRadius: Brand.Radius.button, style: .continuous).fill(Brand.Palette.canvas)) }
                else if configuration.isPressed { base.recessedSurface(radius: Brand.Radius.button) }
                else { base.raisedSurface(radius: Brand.Radius.button, depth: .control) }
            }
            .focusRing(isFocused, radius: Brand.Radius.button)
            .opacity(isEnabled ? 1 : 0.45)
        }
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
