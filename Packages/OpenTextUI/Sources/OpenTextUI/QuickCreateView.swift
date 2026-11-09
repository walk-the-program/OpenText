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
public struct QuickCreateView: View {
    @Binding var state: QuickCreateState
    let onCreate: () -> Void
    let onChangeFolder: () -> Void
    let onCancel: () -> Void
    @FocusState private var nameFocused: Bool

    public init(state: Binding<QuickCreateState>, onCreate: @escaping () -> Void = {},
                onChangeFolder: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}) {
        _state = state
        self.onCreate = onCreate
        self.onChangeFolder = onChangeFolder
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").brandLabel()
                TextField("Untitled", text: $state.name)
                    .brandField()
                    .focused($nameFocused)
                    .onSubmit(onCreate)
            }
            Spacer(minLength: 14)
            VStack(alignment: .leading, spacing: 6) {
                Text("Type").brandLabel()
                HStack(spacing: 6) {
                    ForEach(QuickCreateState.formats, id: \.self) { format in
                        let on = state.format == format
                        Button { state.format = format } label: {
                            Text(".\(format)").font(Brand.Fonts.body(13, weight: .semibold)).tracking(-0.13)
                                .foregroundStyle(on ? Brand.Palette.onPrimary : Brand.Palette.ink)
                                .frame(maxWidth: .infinity).frame(height: Brand.Size.control)
                                .background(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                                    .fill(on ? Brand.Palette.primary : Brand.Palette.canvas))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(format) file").accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Spacer(minLength: 14)
            HStack(spacing: 4) {
                Text("Save to:").font(Brand.Fonts.body(13, weight: .medium)).foregroundStyle(Brand.Palette.ink)
                Text(state.folderName).font(Brand.Fonts.body(13, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                Text("·").foregroundStyle(Brand.Palette.muted).padding(.horizontal, 2)
                Button("Change", action: onChangeFolder)
                    .buttonStyle(.plain)
                    .font(Brand.Fonts.body(13, weight: .semibold)).underline(true).foregroundStyle(Brand.Palette.ink)
                    .keyboardShortcut("o", modifiers: .command)
            }
            Spacer(minLength: 14)
            HStack(spacing: Brand.Spacing.sm) {
                Text("Return to create").font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.muted)
                Text("·").foregroundStyle(Brand.Palette.muted)
                Text("Esc to close").font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.muted)
                Spacer()
                Button("Create", action: onCreate).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 20).padding(.horizontal, 22).padding(.bottom, 18)
        .frame(width: 420, height: 260)
        .floatingSurface(radius: Brand.Radius.popover)
        .onExitCommand(perform: onCancel)
        .onAppear { nameFocused = true }
    }
}
