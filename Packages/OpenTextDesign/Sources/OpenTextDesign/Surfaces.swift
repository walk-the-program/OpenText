import SwiftUI

/// Soft Form surfaces. One light source, top-left: highlight up-left, shadow down-right, in both modes.
extension View {
    /// Raised: cards and secondary buttons.
    public func raisedSurface(radius: CGFloat = Brand.Radius.card, fill: Color = Brand.Palette.canvas) -> some View {
        modifier(SurfaceModifier(kind: .raised, radius: radius, fill: fill))
    }

    /// Recessed: fields and wells.
    public func recessedSurface(radius: CGFloat = Brand.Radius.field, fill: Color = Brand.Palette.canvas) -> some View {
        modifier(SurfaceModifier(kind: .recessed, radius: radius, fill: fill))
    }

    /// Floating panel (popover, sheet): paper fill, hairline, soft drop shadow.
    public func floatingSurface(radius: CGFloat = Brand.Radius.popover) -> some View {
        modifier(SurfaceModifier(kind: .floating, radius: radius, fill: Brand.Palette.surface))
    }

    /// Flat paper (document sheet, toolbar, status bar).
    public func paperSurface() -> some View { background(Brand.Palette.surface) }

    /// Recessed single-line field: 28pt, 8pt corners, Inter 14 semibold.
    public func brandField() -> some View {
        self.textFieldStyle(.plain)
            .font(Brand.Fonts.body(14, weight: .semibold))
            .tracking(-0.28)
            .foregroundStyle(Brand.Palette.ink)
            .padding(.horizontal, Brand.Spacing.md)
            .frame(height: Brand.Size.control)
            .recessedSurface(radius: Brand.Radius.field)
    }

    /// Title style: Inter display SemiBold with the brand's tight tracking (-0.04em).
    public func brandHeading(_ size: CGFloat = Brand.Fonts.headingSize) -> some View {
        font(Brand.Fonts.heading(size)).tracking(-0.04 * size).foregroundStyle(Brand.Palette.ink)
    }

    /// Small section label (12pt, semibold, abMuted).
    public func brandLabel() -> some View {
        font(Brand.Fonts.body(12, weight: .semibold)).tracking(-0.12).foregroundStyle(Brand.Palette.abMuted)
    }

    /// Body text: Inter 13 regular, ink.
    public func brandBody(_ size: CGFloat = Brand.Fonts.bodySize) -> some View {
        font(Brand.Fonts.body(size)).foregroundStyle(Brand.Palette.ink)
    }
}

struct SurfaceModifier: ViewModifier {
    enum Kind { case raised, recessed, floating }
    let kind: Kind
    let radius: CGFloat
    let fill: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch kind {
        case .raised:
            content
                .background(shape.fill(fill)
                    .shadow(color: Brand.Palette.glow, radius: 2.5, x: -2, y: -2)
                    .shadow(color: Brand.Palette.shade, radius: 5, x: 3, y: 4))
        case .recessed:
            content
                .background(shape.fill(fill))
                .overlay(
                    ZStack {
                        shape.stroke(Brand.Palette.shade, lineWidth: 3).blur(radius: 2).offset(x: 1.5, y: 1.5)
                        shape.stroke(Brand.Palette.glow, lineWidth: 3).blur(radius: 2).offset(x: -1.5, y: -1.5)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                )
        case .floating:
            content
                .background(shape.fill(fill)
                    .shadow(color: Brand.Palette.shade, radius: 18, x: 6, y: 14))
                .overlay(shape.stroke(Brand.Palette.tileLine, lineWidth: 1))
        }
    }
}
