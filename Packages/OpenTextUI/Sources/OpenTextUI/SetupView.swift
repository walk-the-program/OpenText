import SwiftUI
import AppKit
import OpenTextDesign

public struct SetupState: Equatable, Sendable {
    public var defaultAppsDone: Bool
    public var finderExtensionOn: Bool
    /// Hotkey in the settings.json spelling, e.g. "ctrl+opt+n".
    public var shortcut: String
    /// Shown under the shortcut, e.g. a clash with another app. nil when fine.
    public var shortcutWarning: String?

    public init(defaultAppsDone: Bool = false, finderExtensionOn: Bool = false, shortcut: String = "ctrl+opt+n", shortcutWarning: String? = nil) {
        self.defaultAppsDone = defaultAppsDone
        self.finderExtensionOn = finderExtensionOn
        self.shortcut = shortcut
        self.shortcutWarning = shortcutWarning
    }
}

public struct SetupActions {
    public var onMakeDefault: () -> Void
    public var onOpenFinderSettings: () -> Void
    /// New hotkey in "ctrl+opt+n" form after the user records one.
    public var onShortcutChanged: (String) -> Void
    public var onDone: () -> Void

    public init(onMakeDefault: @escaping () -> Void = {}, onOpenFinderSettings: @escaping () -> Void = {},
                onShortcutChanged: @escaping (String) -> Void = { _ in }, onDone: @escaping () -> Void = {}) {
        self.onMakeDefault = onMakeDefault
        self.onOpenFinderSettings = onOpenFinderSettings
        self.onShortcutChanged = onShortcutChanged
        self.onDone = onDone
    }
}

/// First-run window: three tiles and Done. No marketing, no account.
public struct SetupView: View {
    @Binding var state: SetupState
    let actions: SetupActions
    let shortcutRecorder: AnyView?
    @State private var recording = false

    /// `shortcutRecorder`: when given, replaces the built-in single-key recorder (e.g. `AnyView(KeyboardShortcuts.Recorder(...))`).
    /// The app then owns recording; `actions.onShortcutChanged` is not called by the view.
    public init(state: Binding<SetupState>, actions: SetupActions = .init(), shortcutRecorder: AnyView? = nil) {
        _state = state
        self.actions = actions
        self.shortcutRecorder = shortcutRecorder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xl) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up OpenText").brandHeading(26)
                Text("Three quick things. You can change them later.").brandBody().foregroundStyle(Brand.Palette.muted)
            }
            HStack(alignment: .top, spacing: Brand.Spacing.lg) {
                tile(title: "Make OpenText your default", detail: "Opens images, PDF, .txt and .md. macOS asks you to confirm each type.", done: state.defaultAppsDone) {
                    Button(state.defaultAppsDone ? "Set again" : "Make default", action: actions.onMakeDefault).buttonStyle(.secondaryAction)
                }
                tile(title: "Turn on Finder right-click", detail: "New Text File, New Markdown File and Convert to… in Finder. Switch it on in System Settings.", done: state.finderExtensionOn) {
                    Button(state.finderExtensionOn ? "Open Settings" : "Turn on…", action: actions.onOpenFinderSettings).buttonStyle(.secondaryAction)
                }
                tile(title: "Your new-file shortcut", detail: "Press it anywhere to make a file.", done: nil, note: state.shortcutWarning) {
                    if let shortcutRecorder {
                        shortcutRecorder
                    } else {
                        ShortcutField(shortcut: state.shortcut, recording: $recording) { new in
                            state.shortcut = new; actions.onShortcutChanged(new)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done", action: actions.onDone).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Brand.Palette.canvas)
    }

    private func tile<Control: View>(title: String, detail: String, done: Bool?, note: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            HStack(spacing: 6) {
                if let done {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                        .foregroundStyle(done ? Brand.Palette.ink : Brand.Palette.muted)
                        .accessibilityLabel(done ? "Done" : "Not done yet")
                }
                if let done { Text(done ? "Done" : "Not done").font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(done ? Brand.Palette.ink : Brand.Palette.muted) }
            }
            .frame(height: 16)
            Text(title).brandHeading(17).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control()
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 230, maxHeight: 230, alignment: .topLeading)
        .raisedSurface(radius: Brand.Radius.card, fill: Brand.Palette.surface)
    }
}

// MARK: Shortcut recorder

enum ShortcutFormat {
    static func glyphs(_ shortcut: String) -> String {
        shortcut.lowercased().split(separator: "+").map { part -> String in
            switch part {
            case "ctrl", "control": "⌃"
            case "opt", "option", "alt": "⌥"
            case "shift": "⇧"
            case "cmd", "command": "⌘"
            default: part.uppercased()
            }
        }.joined()
    }

    static func string(for event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1, !flags.isDisjoint(with: [.control, .option, .command]) else { return nil }
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        return (parts + [key]).joined(separator: "+")
    }
}

struct ShortcutField: View {
    let shortcut: String
    @Binding var recording: Bool
    let onChange: (String) -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text(recording ? "Press the new shortcut" : ShortcutFormat.glyphs(shortcut))
                .font(Brand.Fonts.body(14, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                .padding(.horizontal, 12).frame(height: Brand.Size.control).frame(minWidth: 96, alignment: .leading)
                .recessedSurface(radius: Brand.Radius.field)
                .background(ShortcutRecorder(recording: recording) { new in recording = false; if let new { onChange(new) } }.frame(width: 0, height: 0))
            Button(recording ? "Cancel" : "Change") { recording.toggle() }.buttonStyle(.secondaryAction)
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let recording: Bool
    let onFinish: (String?) -> Void

    func makeNSView(context: Context) -> RecorderView { RecorderView() }
    func updateNSView(_ view: RecorderView, context: Context) {
        view.onFinish = onFinish
        if recording { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
    }

    final class RecorderView: NSView {
        var onFinish: ((String?) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onFinish?(nil); return }          // Esc cancels
            if let s = ShortcutFormat.string(for: event) { onFinish?(s) } else { NSSound.beep() }
        }
    }
}
