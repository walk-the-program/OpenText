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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if onRename == nil {
                Text(title).brandHeading(Brand.Fonts.Scale.title2).lineLimit(1)
            } else if editing {
                RenameField(initial: title, onFinish: finish)
                    .frame(minWidth: 120, idealWidth: 220, maxWidth: 360)
                    .frame(height: 22)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .brandField(focused: true)
                    .frame(height: 28)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                Button { message = nil; withAnimation(Brand.Motion.press) { editing = true } } label: {
                    HStack(spacing: 6) {
                        Text(title).brandHeading(Brand.Fonts.Scale.title2).lineLimit(1)
                        Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.Palette.muted).opacity(hovering ? 1 : 0)
                    }
                    .padding(.horizontal, 6).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: Brand.Radius.sm, style: .continuous)
                        .fill(hovering ? Brand.Palette.abFill : .clear))
                    .contentShape(Rectangle())
                    .animation(Brand.Motion.settle, value: hovering)
                }
                    .buttonStyle(PressableStyle())
                    .brandHover($hovering)
                    .accessibilityLabel(title)
                    .accessibilityHint("Click to rename")
            }
            if let message {
                Text(message).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                    .lineLimit(1).fixedSize()
                    .transition(.move(edge: .leading).combined(with: .opacity))
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
