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
    /// Shown under the "make default" tile, e.g. the file types macOS refused. nil when fine.
    public var defaultAppsNote: String?

    public init(defaultAppsDone: Bool = false, finderExtensionOn: Bool = false, shortcut: String = "ctrl+opt+n", shortcutWarning: String? = nil,
                defaultAppsNote: String? = nil) {
        self.defaultAppsDone = defaultAppsDone
        self.finderExtensionOn = finderExtensionOn
        self.shortcut = shortcut
        self.shortcutWarning = shortcutWarning
        self.defaultAppsNote = defaultAppsNote
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
            HStack(alignment: .center, spacing: Brand.Spacing.lg) {
                BrandMark(size: 52)
                VStack(alignment: .leading, spacing: 6) {
                    WelcomeTitle()
                    Text("Three quick things to set up OpenText. You can change them later.").brandSecondary(14)
                }
            }
            .brandEnter()
            HStack(alignment: .top, spacing: Brand.Spacing.lg) {
                tile(title: "Make OpenText your default", detail: "Opens images, PDF, .txt and .md. macOS asks you to confirm each type.", done: state.defaultAppsDone, note: state.defaultAppsNote) {
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
            .brandEnter(delay: 0.12)
        }
        .padding(Brand.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Brand.Palette.canvas)
    }

    private func tile<Control: View>(title: String, detail: String, done: Bool?, note: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            StatusBadge(done: done).frame(height: 22)
            Text(title).brandHeading(Brand.Fonts.Scale.title2).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control()
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 240, alignment: .topLeading)
        .modifier(HoverCard())
        .brandEnter(delay: 0.05)
    }
}

/// "Done" / "Not done" badge: pill, check in a priTint wash when done, quiet fill when not.
struct StatusBadge: View {
    let done: Bool?
    var body: some View {
        if let done {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark" : "circle.dotted").font(.system(size: 10, weight: .bold))
                Text(done ? "Done" : "Not done").font(Brand.Fonts.body(11, weight: .semibold))
            }
            .foregroundStyle(done ? Brand.Palette.ink : Brand.Palette.abMuted)
            .padding(.horizontal, 9).frame(height: 22)
            .background(Capsule().fill(done ? Brand.Palette.priTint : Brand.Palette.abFill))
            .overlay(Capsule().inset(by: 0.5).stroke(done ? Brand.Palette.primary.opacity(0.6) : Brand.Palette.abHair, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(done ? "Done" : "Not done yet")
            .animation(Brand.Motion.settle, value: done)
        }
    }
}

/// Card that lifts 1pt with a deeper shadow while the pointer is over it.
struct HoverCard: ViewModifier {
    var radius: CGFloat = Brand.Radius.card
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.cardSurface(radius: radius, lifted: hovering).brandHover($hovering)
    }
}

/// The welcome title: the brand tagline, unchanged, with an accent band low under its last word (BUILD-PACK Part 1).
struct WelcomeTitle: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Fuck ").brandDisplay()
            Text("Preview.").brandDisplay()
                .fixedSize()
                .background(alignment: .bottom) {
                    GeometryReader { g in
                        Rectangle().fill(Brand.Palette.accent)
                            .frame(height: Brand.Fonts.Scale.display * 0.16)
                            .offset(y: g.size.height * 0.92 - Brand.Fonts.Scale.display * 0.16)
                    }
                }
        }
        .accessibilityElement(children: .combine)
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
                .padding(.horizontal, 12).frame(height: Brand.Size.field).frame(minWidth: 96, alignment: .leading)
                .brandField(focused: recording)
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
