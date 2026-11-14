import SwiftUI
import OpenTextDesign

public struct QuickCreateState: Equatable, Sendable {
    public static let formats = ["md", "txt", "csv", "html"]
    public var name: String
    /// Lowercase extension: "md", "txt", "csv" or "html".
    public var format: String
    /// Full folder path the file will be created in, e.g. "/Users/me/Desktop".
    public var folderPath: String

    public init(name: String = "Untitled", format: String = "md", folderPath: String = "~/Desktop") {
        self.name = name
        self.format = format
        self.folderPath = folderPath
    }

    /// Last path component for display ("Desktop").
    public var folderName: String {
        let expanded = (folderPath as NSString).expandingTildeInPath
        let last = (expanded as NSString).lastPathComponent
        return last.isEmpty ? "/" : last
    }
}

/// The 420 x 260 popover hanging from the menu bar item. Return creates, Esc closes.
/// `embedded: true` drops the fixed size, floating surface and key hints so a card (HomeView) can host the form.
public struct QuickCreateView: View {
    @Binding var state: QuickCreateState
    let onCreate: () -> Void
    let onChangeFolder: () -> Void
    let onCancel: () -> Void
    let embedded: Bool
    @FocusState private var nameFocused: Bool

    public init(state: Binding<QuickCreateState>, onCreate: @escaping () -> Void = {},
                onChangeFolder: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {},
                embedded: Bool = false) {
        _state = state
        self.embedded = embedded
        self.onCreate = onCreate
        self.onChangeFolder = onChangeFolder
        self.onCancel = onCancel
    }

    /// Popover: flexible 14pt+ gaps inside the fixed 260pt frame. Embedded: fixed gaps, the Create row optionally pushed to the bottom.
    @ViewBuilder private func gap(_ fixed: CGFloat, flexible: Bool = false) -> some View {
        if !embedded { Spacer(minLength: 14) }
        else if flexible { Spacer(minLength: fixed) }
        else { Color.clear.frame(height: fixed) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").brandLabel()
                TextField("Untitled", text: $state.name)
                    .focused($nameFocused)
                    .brandField(focused: nameFocused)
                    .onSubmit(onCreate)
            }
            gap(Brand.Spacing.lg)
            VStack(alignment: .leading, spacing: 6) {
                Text("Type").brandLabel()
                BrandSegmentedControl(QuickCreateState.formats, selection: $state.format, fill: true,
                                      title: { ".\($0)" }, accessibilityTitle: { "\($0) file" })
            }
            gap(Brand.Spacing.lg)
            if embedded {
                // Home tile: where it goes and Create share one row.
                HStack(spacing: Brand.Spacing.sm) { saveTo; Spacer(minLength: 8); createButton }
            } else {
                saveTo
                gap(Brand.Spacing.xl, flexible: true)
                HStack(spacing: Brand.Spacing.sm) {
                    Text("Return to create").font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.muted)
                    Text("·").foregroundStyle(Brand.Palette.muted)
                    Text("Esc to close").font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.muted)
                    Spacer()
                    createButton
                }
            }
        }
        .modifier(PopoverChrome(embedded: embedded))
        .onExitCommand(perform: onCancel)
        .onAppear { nameFocused = true }
    }

    private var saveTo: some View {
        HStack(spacing: 5) {
            Text("Save to").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
            Text(state.folderName).font(Brand.Fonts.body(13, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                .lineLimit(1).truncationMode(.middle)
            Text("·").foregroundStyle(Brand.Palette.muted)
            Button("Change", action: onChangeFolder)
                .buttonStyle(PressableStyle())
                .font(Brand.Fonts.body(13, weight: .semibold)).foregroundStyle(Brand.Palette.primary)
                .keyboardShortcut("o", modifiers: .command)
        }
    }

    private var createButton: some View {
        Button("Create", action: onCreate).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
    }
}

private struct PopoverChrome: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded {
            content.frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            content
                .padding(.top, 20).padding(.horizontal, 22).padding(.bottom, 18)
                .frame(width: 420, height: 260)
                .floatingSurface(radius: Brand.Radius.popover)
        }
    }
}
