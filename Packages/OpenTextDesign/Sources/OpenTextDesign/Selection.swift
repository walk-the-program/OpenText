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
                        .font(Brand.Fonts.body(13, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Brand.Palette.onPrimary : Brand.Palette.abMuted)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .frame(height: Brand.Size.control - 4)
                        .background {
                            if on {
                                Capsule().fill(Brand.Palette.selectionGradient)
                                    .shadow(color: Brand.Palette.shadowNear, radius: 1, y: 1)
                                    .shadow(color: Brand.Palette.shadowSoft, radius: 5, y: 3)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(accessibilityTitle(option))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Brand.Palette.abFill))
        .overlay(Capsule().inset(by: 0.5).stroke(Brand.Palette.abHair, lineWidth: 1))
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

/// Kit list row selection: priTint wash, a primary edge and a check mark. Hover: abFill wash.
public struct BrandRowBackground: View {
    let selected: Bool
    let hovering: Bool
    public init(selected: Bool, hovering: Bool = false) { self.selected = selected; self.hovering = hovering }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
        shape.fill(selected ? Brand.Palette.priTint : (hovering ? Brand.Palette.abFill : .clear))
            .overlay(shape.strokeBorder(Brand.Palette.primary.opacity(selected ? 0.7 : 0), lineWidth: 1))
            .animation(Brand.Motion.settle, value: selected)
            .animation(Brand.Motion.settle, value: hovering)
    }
}
