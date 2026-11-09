import SwiftUI
import AppKit
import OpenTextDesign

/// Shows the one-time recovery key. Copy and Save as Text have built-in behaviour (pasteboard, save panel)
/// unless the app supplies its own closures.
public struct RecoveryKeySheet: View {
    let displayString: String
    let onDone: () -> Void
    let onCopy: ((String) -> Void)?
    let onSaveAsText: ((String) -> Void)?
    @State private var copied = false

    public init(displayString: String, onDone: @escaping () -> Void = {},
                onCopy: ((String) -> Void)? = nil, onSaveAsText: ((String) -> Void)? = nil) {
        self.displayString = displayString
        self.onDone = onDone
        self.onCopy = onCopy
        self.onSaveAsText = onSaveAsText
    }

    var groups: [String] { displayString.split(separator: "-").map(String.init) }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            Text("Your recovery key").brandHeading(20)
            Text("This is the only way to open locked files if you forget your password. It is shown once. Print it or save it somewhere offline.")
                .brandBody().foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Text(group).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(Brand.Palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 32)
                }
            }
            .padding(14).frame(maxWidth: .infinity)
            .recessedSurface(radius: Brand.Radius.lg)
            .textSelection(.enabled)
            .accessibilityElement(children: .ignore).accessibilityLabel("Recovery key").accessibilityValue(displayString)
            HStack(spacing: Brand.Spacing.sm) {
                Button(copied ? "Copied" : "Copy") { copy() }.buttonStyle(.secondaryAction).keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Save as Text") { save() }.buttonStyle(.secondaryAction).keyboardShortcut("s", modifiers: [.command, .shift])
                Spacer()
                Button("I've stored it", action: onDone).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.Spacing.xl).frame(width: 480).background(Brand.Palette.canvas)
    }

    private func copy() {
        if let onCopy { onCopy(displayString) } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(displayString, forType: .string)
        }
        copied = true
    }

    private func save() {
        if let onSaveAsText { onSaveAsText(displayString); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OpenText recovery key.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            let body = "OpenText recovery key\n\n\(displayString)\n\nKeep this offline. Anyone with it can open your locked files.\n"
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
