import SwiftUI

/// Command and dirty-state bridge between one document window and the app.
///
/// The app creates one per window, passes it to the document view (`commands:`), and publishes it with
/// `.focusedSceneValue(\.documentCommands, commands)` so menu items can reach the focused window:
///
///     @FocusedValue(\.documentCommands) var commands
///     Button("Zoom In") { commands?.perform(.zoomIn) }.disabled(!(commands?.isAvailable(.zoomIn) ?? false))
///
/// The view registers handlers while it is on screen, so `isAvailable` is false for commands the current
/// window type (or mode) does not support.
@MainActor @Observable
public final class DocumentCommands {
    public enum Kind: Sendable { case pdf, image, text }

    public enum Command: Hashable, Sendable {
        // PDF
        case find, toggleThumbnails, highlight, sign, addText, rotateLeft, insertPages, extractPages, deletePages
        // PDF and image
        case zoomIn, zoomOut, actualSize, rotate
        // Image
        case crop, resize, flipHorizontal, flipVertical
        // Text (Markdown unless noted)
        case heading(Int)          // 1...3
        case bold, italic, list, link, togglePreview
        case toggleMonospace       // .txt only
    }

    /// Window type of the registered view; nil before a view appears.
    public private(set) var kind: Kind?
    private var handlers: [Command: () -> Void] = [:]
    private var savedHandler: (() -> Void)?

    /// True when the document has changes the app has not reported as saved.
    public private(set) var isDirty = false
    /// Fires whenever `isDirty` flips (not on repeated marks).
    @ObservationIgnored public var onDirtyChange: ((Bool) -> Void)?

    public init() {}

    // MARK: App side

    public func isAvailable(_ command: Command) -> Bool { handlers[command] != nil }

    /// Runs the command. Returns false (and does nothing) when it is unavailable.
    @discardableResult
    public func perform(_ command: Command) -> Bool {
        guard let handler = handlers[command] else { return false }
        handler()
        return true
    }

    /// Call after the document was written to disk successfully. Clears the dirty flag.
    public func markSaved() {
        savedHandler?()
        setDirty(false)
    }

    // MARK: View side

    /// Replaces all handlers. Views call this on appear and when their mode changes.
    public func register(kind: Kind, handlers: [Command: () -> Void], onSaved: (() -> Void)? = nil) {
        self.kind = kind
        self.handlers = handlers
        self.savedHandler = onSaved
    }

    public func unregister() {
        kind = nil
        handlers = [:]
        savedHandler = nil
    }

    /// Views call this on any edit.
    public func markDirty() { setDirty(true) }

    private func setDirty(_ value: Bool) {
        guard isDirty != value else { return }
        isDirty = value
        onDirtyChange?(value)
    }
}

private struct DocumentCommandsKey: FocusedValueKey {
    typealias Value = DocumentCommands
}

public extension FocusedValues {
    /// The focused window's `DocumentCommands`; set with `.focusedSceneValue(\.documentCommands, commands)`.
    var documentCommands: DocumentCommands? {
        get { self[DocumentCommandsKey.self] }
        set { self[DocumentCommandsKey.self] = newValue }
    }
}
