import SwiftUI
import OpenTextDesign

/// Title area content for a document window: name + format chip. Pass to a view's `header:` and hide the
/// native title bar, or leave nil when the window shows its own title.
public struct DocumentHeader {
    public var title: String
    public var format: String
    public var targets: [String]
    public var onSwitchFormat: (String) -> Void
    /// Space kept free at the leading edge for the traffic-light buttons when the title bar is hidden.
    public var leadingInset: CGFloat
    /// Small muted text at the trailing end of the header ("120 words · Saved", "3 pages"). Set by the document view.
    public var status: String?
    /// Click-to-rename: gets the new name (no extension) and returns a short message when it can't be used, nil
    /// when the file was renamed. nil here means the title is plain text (read-only, locked, still loading...).
    public var onRename: ((String) async -> String?)?

    public init(title: String, format: String, targets: [String] = [], leadingInset: CGFloat = 0,
                onSwitchFormat: @escaping (String) -> Void = { _ in }) {
        self.title = title
        self.format = format
        self.targets = targets
        self.leadingInset = leadingInset
        self.onSwitchFormat = onSwitchFormat
    }
}

/// One toolbar row: [header] | tools ... trailing. 48pt high, paper fill, hairline below.
struct ToolbarRow<Tools: View, Trailing: View>: View {
    var header: DocumentHeader?
    /// Opacity of tools + trailing actions (the title and chip stay). Used by the fading editor toolbar.
    var toolsOpacity: Double = 1
    @ViewBuilder var tools: Tools
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Brand.Spacing.sm) {
            if let header {
                Color.clear.frame(width: header.leadingInset, height: 1)
                HeaderTitle(title: header.title, onRename: header.onRename)
                FormatChip(format: header.format, targets: header.targets, onSelect: header.onSwitchFormat)
                Rectangle().fill(Brand.Palette.abHair).frame(width: 1, height: 20).padding(.horizontal, 6)
            }
            HStack(spacing: Brand.Spacing.sm) {
                tools
                Spacer(minLength: Brand.Spacing.md)
                trailing
            }
            .opacity(toolsOpacity)
            .allowsHitTesting(toolsOpacity > 0.5)
            .accessibilityHidden(toolsOpacity < 0.5)
            if let status = header?.status {
                Text(status)
                    .font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Brand.Motion.settle, value: status)
                    .lineLimit(1).fixedSize().padding(.leading, Brand.Spacing.sm)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Brand.Size.toolbarHeight)
        .background(Brand.Palette.chrome)
    }
}

/// Text tool button with an optional keyboard shortcut.
struct ToolButton: View {
    var title: String
    var shortcut: KeyboardShortcut? = nil
    var isActive = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.toolbarItem(isActive: isActive))
            .optionalShortcut(shortcut)
            .accessibilityLabel(title)
    }
}

extension View {
    @ViewBuilder func optionalShortcut(_ s: KeyboardShortcut?) -> some View {
        if let s { keyboardShortcut(s) } else { self }
    }
}

/// Bento tool group: tools share one well track; the active one fills steel.
struct ToolGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.Palette.well))
    }
}

/// Label of one tool in a `ToolGroup`. Values only, so presses never swap the view.
struct GroupedToolLabel: View {
    let title: String
    let active: Bool
    var body: some View {
        Text(title)
            .font(Brand.Fonts.body(13, weight: .semibold))
            .foregroundStyle(active ? Brand.Palette.onPrimary : Brand.Palette.muted)
            .padding(.horizontal, 12).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? Brand.Palette.primary : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .animation(Brand.Motion.settle, value: active)
    }
}

struct GroupedTool: View {
    let title: String
    var active = false
    var shortcut: KeyboardShortcut? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) { GroupedToolLabel(title: title, active: active) }
            .buttonStyle(PressableStyle())
            .optionalShortcut(shortcut)
            .accessibilityLabel(title)
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}
