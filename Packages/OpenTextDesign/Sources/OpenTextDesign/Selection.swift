import SwiftUI

/// Kit segmented control: a quiet pill track; the selected option is a gradient pill (primary to abMHue, 140°)
/// that slides to the new option on a spring. Each option keeps one view; only values change.
public struct BrandSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    let accessibilityTitle: (Option) -> String
    @Binding var selection: Option
    var fill: Bool
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `fill`: options share the width equally (forms) instead of hugging their labels (toolbars).
    public init(_ options: [Option], selection: Binding<Option>, fill: Bool = false,
                title: @escaping (Option) -> String, accessibilityTitle: ((Option) -> String)? = nil) {
        self.options = options
        self._selection = selection
        self.fill = fill
        self.title = title
        self.accessibilityTitle = accessibilityTitle ?? title
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(Brand.Motion.resolved(Brand.Motion.settle, reduceMotion: reduceMotion)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(Brand.Fonts.body(13, weight: .semibold))
                        .foregroundStyle(on ? Brand.Palette.onPrimary : Brand.Palette.muted)
                        .padding(.horizontal, 13)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .frame(height: Brand.Size.control - 4)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.Palette.primary)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(accessibilityTitle(option))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.Palette.well))
    }
}

/// Plain button whose label springs down slightly while pressed. Values only.
public struct PressableStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Brand.Motion.pressScale : 1)
            .animation(Brand.Motion.press, value: configuration.isPressed)
    }
}

/// Kit list row selection: the selected row fills solid steel (put `BrandRowText` colours on its text);
/// hover is a quiet well wash.
public struct BrandRowBackground: View {
    let selected: Bool
    let hovering: Bool
    public init(selected: Bool, hovering: Bool = false) { self.selected = selected; self.hovering = hovering }
    public var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(selected ? Brand.Palette.primary : (hovering ? Brand.Palette.well : .clear))
            .animation(Brand.Motion.settle, value: selected)
            .animation(Brand.Motion.settle, value: hovering)
    }
}

/// Text colours on a list row: on-primary when the row is selected.
public enum BrandRowText {
    public static func primary(_ selected: Bool) -> Color { selected ? Brand.Palette.onPrimary : Brand.Palette.ink }
    public static func secondary(_ selected: Bool) -> Color { selected ? Brand.Palette.onPrimary.opacity(0.78) : Brand.Palette.muted }
}
