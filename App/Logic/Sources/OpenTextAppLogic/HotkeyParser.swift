import Foundation

/// A parsed global shortcut. `modifiers` uses Carbon's masks
/// (cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000) so it can be
/// passed straight to RegisterEventHotKey without importing Carbon here.
public struct HotkeySpec: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum HotkeyParseError: Error, Equatable {
    case empty, noModifier, noKey, multipleKeys, unknownToken(String)
}

public enum HotkeyParser {
    public static let cmd: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    static let modifierNames: [String: UInt32] = [
        "cmd": cmd, "command": cmd, "shift": shift,
        "opt": option, "option": option, "alt": option,
        "ctrl": control, "control": control,
    ]

    /// ANSI virtual key codes.
    static let keyCodes: [String: UInt32] = {
        var m: [String: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
            "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
            "return": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
        ]
        let f: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, c) in f.enumerated() { m["f\(i + 1)"] = c }
        return m
    }()

    /// Parses strings like "ctrl+opt+n". Case-insensitive; needs >= 1 modifier and exactly 1 key.
    public static func parse(_ text: String) throws -> HotkeySpec {
        let tokens = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if tokens.allSatisfy({ $0.isEmpty }) { throw HotkeyParseError.empty }
        var mods: UInt32 = 0
        var key: UInt32?
        for t in tokens {
            if t.isEmpty { throw HotkeyParseError.unknownToken("") }
            if let m = modifierNames[t] { mods |= m; continue }
            guard let code = keyCodes[t] else { throw HotkeyParseError.unknownToken(t) }
            if key != nil { throw HotkeyParseError.multipleKeys }
            key = code
        }
        guard let key else { throw HotkeyParseError.noKey }
        guard mods != 0 else { throw HotkeyParseError.noModifier }
        return HotkeySpec(keyCode: key, modifiers: mods)
    }

    /// Inverse of parse: "ctrl+opt+n". Returns nil for key codes the parser doesn't know.
    public static func format(_ spec: HotkeySpec) -> String? {
        guard let name = keyCodes.first(where: { $0.value == spec.keyCode && $0.key != "esc" })?.key else { return nil }
        var parts: [String] = []
        if spec.modifiers & control != 0 { parts.append("ctrl") }
        if spec.modifiers & option != 0 { parts.append("opt") }
        if spec.modifiers & shift != 0 { parts.append("shift") }
        if spec.modifiers & cmd != 0 { parts.append("cmd") }
        return (parts + [name]).joined(separator: "+")
    }
}
