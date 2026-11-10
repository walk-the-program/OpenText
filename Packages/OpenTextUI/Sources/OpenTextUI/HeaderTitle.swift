import SwiftUI
import AppKit
import OpenTextDesign

/// The file name in the document header. With `onRename` a single click turns it into a text field with the name
/// selected: Return renames, Escape or clicking elsewhere cancels. A name that can't be used keeps the old one and
/// says why, next to the title, for a few seconds.
struct HeaderTitle: View {
    let title: String
    var onRename: ((String) async -> String?)?
    @State private var editing = false
    @State private var message: String?
    @State private var clearTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            if onRename == nil {
                Text(title).brandHeading(18).lineLimit(1)
            } else if editing {
                RenameField(initial: title, onFinish: finish)
                    .frame(minWidth: 120, idealWidth: 220, maxWidth: 360)
                    .frame(height: 22)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .recessedSurface(radius: Brand.Radius.field)
            } else {
                Button { message = nil; editing = true } label: { Text(title).brandHeading(18).lineLimit(1) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityHint("Click to rename")
            }
            if let message {
                Text(message).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                    .lineLimit(1).fixedSize()
            }
        }
    }

    private func finish(_ outcome: RenameField.Outcome) {
        editing = false
        guard case .commit(let name) = outcome, name != title, let onRename else { return }
        Task { @MainActor in
            guard let problem = await onRename(name) else { return }
            message = problem
            clearTask?.cancel()
            clearTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { message = nil }
            }
        }
    }
}

/// Single-line text field that takes focus with its text selected and reports how editing ended.
struct RenameField: NSViewRepresentable {
    enum Outcome { case commit(String), cancel }
    let initial: String
    let onFinish: (Outcome) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeNSView(context: Context) -> NSTextField {
        let f = FocusingTextField(string: initial)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Brand.Fonts.nsHeading(18)
        f.textColor = Brand.NSPalette.ink
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.delegate = context.coordinator
        f.setAccessibilityLabel("File name")
        return f
    }

    /// Takes focus, with all text selected, as soon as it is in a window.
    final class FocusingTextField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window === w else { return }
                w.makeFirstResponder(self)
                self.currentEditor()?.selectAll(nil)
            }
        }
    }

    func updateNSView(_ f: NSTextField, context: Context) { context.coordinator.onFinish = onFinish }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var onFinish: (Outcome) -> Void
        private var finished = false
        init(onFinish: @escaping (Outcome) -> Void) { self.onFinish = onFinish }

        private func finish(_ outcome: Outcome) {
            guard !finished else { return }
            finished = true
            onFinish(outcome)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): finish(.commit(control.stringValue)); return true
            case #selector(NSResponder.cancelOperation(_:)): finish(.cancel); return true
            default: return false
            }
        }

        /// Clicking elsewhere ends editing without Return: that cancels.
        func controlTextDidEndEditing(_ notification: Notification) { finish(.cancel) }
    }
}
