import AppKit
import KeyboardShortcuts
import OpenTextAppLogic

extension KeyboardShortcuts.Name {
    /// Global new-file shortcut. Default control-option-N.
    static let quickCreate = Self("quickCreate", default: .init(.n, modifiers: [.control, .option]))
}

/// Global shortcut via KeyboardShortcuts. settings.json "hotkey" is a readable mirror
/// ("ctrl+opt+n") so the file can be edited by hand or by an AI.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var listening = false

    func start(onPress: @escaping () -> Void) {
        guard !listening, !SelfTest.enabled else { return }
        listening = true
        KeyboardShortcuts.onKeyUp(for: .quickCreate, action: onPress)
    }

    /// Current shortcut as a settings string, or nil if cleared / not representable.
    var currentString: String? {
        guard let s = KeyboardShortcuts.getShortcut(for: .quickCreate) else { return nil }
        return HotkeyParser.format(HotkeySpec(keyCode: UInt32(s.carbonKeyCode), modifiers: UInt32(s.carbonModifiers)))
    }

    /// Applies a settings string to KeyboardShortcuts. Returns false if it can't be parsed.
    @discardableResult
    func apply(_ text: String) -> Bool {
        guard let spec = try? HotkeyParser.parse(text) else { return false }
        KeyboardShortcuts.setShortcut(
            .init(carbonKeyCode: Int(spec.keyCode), carbonModifiers: Int(spec.modifiers)), for: .quickCreate)
        return true
    }
}
