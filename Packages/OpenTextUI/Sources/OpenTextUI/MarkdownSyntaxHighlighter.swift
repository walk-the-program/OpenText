import Foundation

/// Finds Markdown structure in plain text. Pure: returns ranges; the editor paints them.
public enum MarkdownSyntaxHighlighter {
    public enum Kind: Equatable, Sendable {
        /// Characters like `#`, `**`, `-`, backticks, brackets: drawn muted.
        case syntax
        /// Text of a heading line (level 1...6).
        case heading(Int)
        case bold
        case italic
        case code
    }

    public struct Span: Equatable, Sendable {
        public var range: NSRange
        public var kind: Kind
        public init(_ range: NSRange, _ kind: Kind) { self.range = range; self.kind = kind }
    }

    /// Documents longer than this (UTF-16 units, about 1 MB) get no highlighting.
    public static let maxDocumentLength = 1_048_576
    /// Lines longer than this are left as plain body text.
    public static let maxLineLength = 5_000

    public static func spans(in text: String) -> [Span] { spans(in: text, range: nil) }

    /// Spans for whole lines intersecting `range` (nil = whole text). Fence state at the start of the range
    /// is found with a cheap prefix scan, so a paragraph can be restyled without a full pass.
    /// `lineLimit` is exposed so tests can exercise the regexes on very long lines.
    public static func spans(in text: String, range: NSRange?, lineLimit: Int = maxLineLength) -> [Span] {
        let ns = text as NSString
        guard ns.length <= maxDocumentLength else { return [] }
        var spans: [Span] = []
        let target = range.map { ns.lineRange(for: $0) } ?? NSRange(location: 0, length: ns.length)
        var inFence = false
        if target.location > 0 {
            ns.enumerateSubstrings(in: NSRange(location: 0, length: target.location), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
                if isFence(ns, lineRange) { inFence.toggle() }
            }
        }
        ns.enumerateSubstrings(in: target, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            if isFence(ns, lineRange) {
                inFence.toggle()
                spans.append(Span(lineRange, .syntax))
                return
            }
            if lineRange.length > lineLimit { return }
            if inFence { spans.append(Span(lineRange, .code)); return }
            spans.append(contentsOf: lineSpans(ns.substring(with: lineRange), offset: lineRange.location))
        }
        return spans
    }

    /// True when the line starts a code fence. Cheap: looks at three characters only.
    static func isFence(_ ns: NSString, _ lineRange: NSRange) -> Bool {
        guard lineRange.length >= 3 else { return false }
        let head = ns.substring(with: NSRange(location: lineRange.location, length: 3))
        return head == "```" || head == "~~~"
    }

    // MARK: Lines

    private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,6})([ \t]+)(.*)$"#)
    private static let listRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)"#)
    private static let quoteRegex = try! NSRegularExpression(pattern: #"^([ \t]*>)+"#)
    private static let ruleRegex = try! NSRegularExpression(pattern: #"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"(`+)(.{1,300}?)\1"#)
    private static let boldRegex = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.{1,300}?)(?<=\S)\1"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<![*_\w])([*_])(?=[^\s*_])(.{1,300}?)(?<=[^\s*_])\1(?![*_\w])"#)
    private static let linkRegex = try! NSRegularExpression(pattern: #"!?\[([^\]\n]*)\]\(([^)\n]*)\)"#)

    private static func lineSpans(_ line: String, offset: Int) -> [Span] {
        var spans: [Span] = []
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }

        if ruleRegex.firstMatch(in: line, range: full) != nil { return [Span(shift(full), .syntax)] }

        var inlineStart = 0
        if let m = headingRegex.firstMatch(in: line, range: full) {
            let hashes = m.range(at: 1), textRange = m.range(at: 3)
            spans.append(Span(shift(NSRange(location: hashes.location, length: hashes.length)), .syntax))
            if textRange.length > 0 { spans.append(Span(shift(textRange), .heading(hashes.length))) }
            inlineStart = textRange.location
        } else if let m = listRegex.firstMatch(in: line, range: full) {
            spans.append(Span(shift(m.range(at: 2)), .syntax))
            inlineStart = m.range.upperBound
        } else if let m = quoteRegex.firstMatch(in: line, range: full) {
            spans.append(Span(shift(m.range), .syntax))
            inlineStart = m.range.upperBound
        }

        let inline = NSRange(location: inlineStart, length: ns.length - inlineStart)
        guard inline.length > 0 else { return spans }
        var taken: [NSRange] = []   // code spans claim their characters first
        for m in codeRegex.matches(in: line, range: inline) {
            let tick = m.range(at: 1)
            spans.append(Span(shift(NSRange(location: m.range.location, length: tick.length)), .syntax))
            spans.append(Span(shift(m.range(at: 2)), .code))
            spans.append(Span(shift(NSRange(location: m.range.upperBound - tick.length, length: tick.length)), .syntax))
            taken.append(m.range)
        }
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }
        for m in boldRegex.matches(in: line, range: inline) where free(m.range) {
            let mark = m.range(at: 1)
            spans.append(Span(shift(NSRange(location: m.range.location, length: mark.length)), .syntax))
            spans.append(Span(shift(m.range(at: 2)), .bold))
            spans.append(Span(shift(NSRange(location: m.range.upperBound - mark.length, length: mark.length)), .syntax))
            taken.append(m.range)
        }
        for m in italicRegex.matches(in: line, range: inline) where free(m.range) {
            spans.append(Span(shift(NSRange(location: m.range.location, length: 1)), .syntax))
            spans.append(Span(shift(m.range(at: 2)), .italic))
            spans.append(Span(shift(NSRange(location: m.range.upperBound - 1, length: 1)), .syntax))
            taken.append(m.range)
        }
        for m in linkRegex.matches(in: line, range: inline) where free(m.range) {
            let label = m.range(at: 1)
            // "[" / "![", then "](url)" are syntax; the label stays ink.
            spans.append(Span(shift(NSRange(location: m.range.location, length: label.location - m.range.location)), .syntax))
            let tailStart = label.upperBound
            spans.append(Span(shift(NSRange(location: tailStart, length: m.range.upperBound - tailStart)), .syntax))
        }
        return spans
    }
}
