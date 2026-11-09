import AppKit
import Foundation
import Testing
@testable import OpenTextUI

@Suite @MainActor struct HighlightPerformanceTests {
    static let pathological = String(repeating: "a *b ", count: 8_000)   // 40 KB, one line

    @Test func pathologicalLineIsFastEvenWithoutTheLineLimit() {
        let start = Date()
        _ = MarkdownSyntaxHighlighter.spans(in: Self.pathological, range: nil, lineLimit: .max)
        #expect(Date().timeIntervalSince(start) < 0.2)
    }

    @Test func overLimitLinesAndDocumentsStayPlain() {
        let start = Date()
        #expect(MarkdownSyntaxHighlighter.spans(in: Self.pathological).isEmpty)
        #expect(MarkdownSyntaxHighlighter.spans(in: "**ok**\n" + Self.pathological).count == 3)
        let big = String(repeating: "**bold** line\n", count: 100_000)
        #expect(big.utf16.count > MarkdownSyntaxHighlighter.maxDocumentLength)
        #expect(MarkdownSyntaxHighlighter.spans(in: big).isEmpty)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func rangeSpansMatchFullSpansAndRespectFences() {
        let text = "intro *a*\n```\n**not bold**\n```\n**bold** end\n"
        let ns = text as NSString
        let full = MarkdownSyntaxHighlighter.spans(in: text)
        let inside = ns.range(of: "**not bold**")
        let part = MarkdownSyntaxHighlighter.spans(in: text, range: inside)
        #expect(part.map(\.kind) == [.code])
        let tail = ns.range(of: "**bold** end")
        #expect(MarkdownSyntaxHighlighter.spans(in: text, range: tail).allSatisfy { full.contains($0) })
    }

    @Test func paragraphEditOnlyTouchesItsParagraph() {
        let text = "first *one*\nsecond **two**\nthird\n"
        let storage = NSTextStorage(string: text)
        PlainTextStyler.apply(to: storage, isMarkdown: true, monospace: false)
        let ns = storage.string as NSString
        // Mark an untouched paragraph so we can see whether a restyle reaches it.
        let first = ns.range(of: "first *one*\n")
        storage.addAttribute(.backgroundColor, value: NSColor.red, range: first)
        let secondEdit = NSRange(location: ns.range(of: "two").location, length: 3)
        let range = PlainTextStyler.restyleRange(in: ns, edited: secondEdit, fenceTouched: false)
        #expect(range == ns.range(of: "second **two**\n"))
        storage.beginEditing()
        PlainTextStyler.apply(to: storage, range: range, isMarkdown: true, monospace: false)
        storage.endEditing()
        #expect(storage.attribute(.backgroundColor, at: first.location, effectiveRange: nil) != nil)
        // A fence edit restyles through the end of the text.
        let fence = PlainTextStyler.restyleRange(in: ns, edited: NSRange(location: 0, length: 1), fenceTouched: true)
        #expect(NSMaxRange(fence) == ns.length)
    }
}
