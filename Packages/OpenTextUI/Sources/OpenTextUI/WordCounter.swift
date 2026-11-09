import Foundation

public enum WordCounter {
    /// Words are runs of non-whitespace containing at least one letter or digit ("-" or "#" alone don't count).
    public static func count(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }

    public static func label(_ text: String) -> String {
        let n = count(text)
        return "\(n) \(n == 1 ? "word" : "words")"
    }
}
