import Foundation

public enum MarkdownCommand: Sendable { case heading, headingLevel(Int), bold, italic, list, link }

/// A single text replacement, applied by the editor as one undoable edit.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange          // range in the original text to replace
    public var replacement: String
    public var selection: NSRange      // selection after the edit, in the new text
}

public enum MarkdownFormatting {
    public static func edit(_ command: MarkdownCommand, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let sel = NSRange(location: min(selection.location, ns.length), length: min(selection.length, ns.length - min(selection.location, ns.length)))
        switch command {
        case .bold: return wrap(ns, sel, marker: "**", placeholder: "bold")
        case .link: return link(ns, sel)
        case .italic: return wrap(ns, sel, marker: "*", placeholder: "italic")
        case .heading: return heading(ns, sel)
        case let .headingLevel(level): return heading(ns, sel, level: level)
        case .list: return list(ns, sel)
        }
    }

    private static func wrap(_ ns: NSString, _ sel: NSRange, marker: String, placeholder: String) -> TextEdit {
        let m = (marker as NSString).length
        // Toggle off when the selection is already wrapped.
        if sel.location >= m, sel.upperBound + m <= ns.length,
           ns.substring(with: NSRange(location: sel.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: sel.upperBound, length: m)) == marker, sel.length > 0 {
            let whole = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            let inner = ns.substring(with: sel)
            return TextEdit(range: whole, replacement: inner, selection: NSRange(location: whole.location, length: sel.length))
        }
        let inner = sel.length > 0 ? ns.substring(with: sel) : placeholder
        return TextEdit(range: sel, replacement: marker + inner + marker,
                        selection: NSRange(location: sel.location + m, length: (inner as NSString).length))
    }

    private static func link(_ ns: NSString, _ sel: NSRange) -> TextEdit {
        let label = sel.length > 0 ? ns.substring(with: sel) : "link text"
        let url = "https://"
        let replacement = "[\(label)](\(url))"
        let urlStart = sel.location + (label as NSString).length + 3
        return TextEdit(range: sel, replacement: replacement, selection: NSRange(location: urlStart, length: (url as NSString).length))
    }

    /// Cycles the heading level of the first selected line: none -> # -> ## -> ### -> none.
    /// With `level` it sets that level, or removes it when the line already has it.
    private static func heading(_ ns: NSString, _ sel: NSRange, level: Int? = nil) -> TextEdit {
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let hasNewline = lineRange.length > 0 && (ns.substring(with: NSRange(location: lineRange.upperBound - 1, length: 1)) as String).rangeOfCharacter(from: .newlines) != nil
        let contentRange = NSRange(location: lineRange.location, length: lineRange.length - (hasNewline ? 1 : 0))
        let line = ns.substring(with: contentRange)
        let hashes = line.prefix { $0 == "#" }.count
        let rest = line.dropFirst(hashes).drop { $0 == " " }
        let next: Int
        if let level { let l = min(max(level, 1), 3); next = hashes == l ? 0 : l } else { next = hashes >= 3 ? 0 : hashes + 1 }
        let new = (next == 0 ? "" : String(repeating: "#", count: next) + " ") + rest
        let delta = (new as NSString).length - contentRange.length
        return TextEdit(range: contentRange, replacement: new,
                        selection: NSRange(location: max(contentRange.location, sel.location + delta), length: sel.length))
    }

    /// Prefixes every selected line with "- " (or removes the prefix when all already have it).
    private static func list(_ ns: NSString, _ sel: NSRange) -> TextEdit {
        let block = ns.lineRange(for: sel)
        let hasNewline = block.length > 0 && ns.substring(with: NSRange(location: block.upperBound - 1, length: 1)).rangeOfCharacter(from: .newlines) != nil
        let content = NSRange(location: block.location, length: block.length - (hasNewline ? 1 : 0))
        let lines = ns.substring(with: content).components(separatedBy: "\n")
        let allListed = lines.allSatisfy { $0.hasPrefix("- ") }
        let out = lines.map { allListed ? String($0.dropFirst(2)) : "- " + $0 }.joined(separator: "\n")
        return TextEdit(range: content, replacement: out, selection: NSRange(location: content.location, length: (out as NSString).length))
    }
}
