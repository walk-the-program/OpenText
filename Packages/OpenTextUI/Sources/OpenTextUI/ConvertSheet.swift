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
            Text("Convert .\(sourceFormat)").brandHeading(20)
            Text("A new file is made next to the original. The original is not changed.")
                .brandBody().foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(targets, id: \.self) { target in
                    let on = (selected ?? targets.first) == target
                    Button { selected = target } label: {
                        HStack {
                            Text(Self.title(target)).font(Brand.Fonts.body(13, weight: .semibold))
                            Spacer()
                            Text(".\(target)").font(Brand.Fonts.body(12, weight: .medium))
                        }
                        .foregroundStyle(on ? Brand.Palette.onPrimary : Brand.Palette.ink)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous).fill(on ? Brand.Palette.primary : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(6)
            .recessedSurface(radius: Brand.Radius.lg)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.secondaryAction).keyboardShortcut(.cancelAction)
                Button("Convert") { if let t = selected ?? targets.first { onConvert(t) } }
                    .buttonStyle(.primaryAction).keyboardShortcut(.defaultAction).disabled(targets.isEmpty)
            }
        }
        .padding(Brand.Spacing.xl).frame(width: 380).background(Brand.Palette.canvas)
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
