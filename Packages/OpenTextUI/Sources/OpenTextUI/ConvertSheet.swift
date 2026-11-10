import SwiftUI
import OpenTextDesign

/// Pick a target format and convert. `targets` and the result are lowercase extensions.
public struct ConvertSheet: View {
    let sourceFormat: String
    let targets: [String]
    let onConvert: (String) -> Void
    let onCancel: () -> Void
    @State private var selected: String?

    public init(sourceFormat: String, targets: [String], onConvert: @escaping (String) -> Void, onCancel: @escaping () -> Void = {}) {
        self.sourceFormat = sourceFormat
        self.targets = targets
        self.onConvert = onConvert
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            Text("Convert .\(sourceFormat)").brandHeading(Brand.Fonts.Scale.title)
            Text("A new file is made next to the original. The original is not changed.")
                .brandBody().foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(targets, id: \.self) { target in
                    let on = (selected ?? targets.first) == target
                    Button { withAnimation(Brand.Motion.settle) { selected = target } } label: {
                        HStack(spacing: Brand.Spacing.sm) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Brand.Palette.primaryText).opacity(on ? 1 : 0)
                                .frame(width: 14)
                            Text(Self.title(target)).font(Brand.Fonts.body(14, weight: .medium))
                            Spacer()
                            Text(".\(target)").font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted)
                        }
                        .foregroundStyle(Brand.Palette.ink)
                        .padding(.horizontal, 12).frame(height: Brand.Size.row)
                        .background(BrandRowBackground(selected: on))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(6)
            .cardSurface(radius: Brand.Radius.lg)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.secondaryAction).keyboardShortcut(.cancelAction)
                Button("Convert") { if let t = selected ?? targets.first { onConvert(t) } }
                    .buttonStyle(.primaryAction).keyboardShortcut(.defaultAction).disabled(targets.isEmpty)
            }
        }
        .padding(Brand.Spacing.xl).frame(width: 400).background(Brand.Palette.canvas).brandEnter()
    }

    static func title(_ ext: String) -> String {
        switch ext {
        case "pdf": "PDF"
        case "md": "Markdown"
        case "txt": "Plain text"
        case "rtf": "Rich text"
        case "html": "Web page"
        case "docx": "Word"
        case "png": "PNG image"
        case "jpg": "JPEG image"
        case "otlock": "Locked"
        default: ext.uppercased()
        }
    }
}
