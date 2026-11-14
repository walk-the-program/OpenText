import SwiftUI

/// The ".pdf ▾" chip: shows the file's format and offers the formats it can switch to.
/// Formats are lowercase extension strings.
public struct FormatChip: View {
    public var format: String
    public var targets: [String]
    public var onSelect: (String) -> Void

    public init(format: String, targets: [String] = [], onSelect: @escaping (String) -> Void = { _ in }) {
        self.format = format
        self.targets = targets
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            ForEach(targets, id: \.self) { target in
                Button(".\(target)") { onSelect(target) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(".\(format.lowercased())")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(Brand.Fonts.body(12, weight: .semibold)).tracking(-0.12)
            .foregroundStyle(Brand.Palette.ink)
            .padding(.leading, 10).padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: Brand.Radius.chip, style: .continuous).fill(Brand.Palette.well))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(targets.isEmpty)
        .accessibilityLabel("File format .\(format)")
    }
}
