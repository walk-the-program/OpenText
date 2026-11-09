import AppKit
import Foundation
import Testing
@testable import OpenTextUI

@Suite struct WordCounterTests {
    @Test func counts() {
        #expect(WordCounter.count("") == 0)
        #expect(WordCounter.count("   \n ") == 0)
        #expect(WordCounter.count("one two  three\nfour") == 4)
        #expect(WordCounter.count("# Heading\n- item one\n- item two") == 5)
        #expect(WordCounter.count("Don't stop — $1,200 spent") == 4)
        #expect(WordCounter.label("a") == "1 word")
        #expect(WordCounter.label("a b") == "2 words")
    }
}

@Suite struct MarkdownSyntaxHighlighterTests {
    func texts(_ s: String, _ kind: MarkdownSyntaxHighlighter.Kind) -> [String] {
        let ns = s as NSString
        return MarkdownSyntaxHighlighter.spans(in: s).filter { $0.kind == kind }.map { ns.substring(with: $0.range) }
    }

    @Test func heading() {
        let s = "# Christmas 2026\n## Mom"
        #expect(texts(s, .syntax) == ["#", "##"])
        #expect(texts(s, .heading(1)) == ["Christmas 2026"])
        #expect(texts(s, .heading(2)) == ["Mom"])
    }

    @Test func boldItalicAndList() {
        let s = "- **Budget:** $1,200 and *The Order of Time*"
        #expect(texts(s, .syntax) == ["-", "**", "**", "*", "*"])
        #expect(texts(s, .bold) == ["Budget:"])
        #expect(texts(s, .italic) == ["The Order of Time"])
    }

    @Test func codeLinksQuotesAndFences() {
        #expect(texts("use `swift build` now", .code) == ["swift build"])
        #expect(texts("see [site](https://x.y) ok", .syntax) == ["[", "](https://x.y)"])
        #expect(texts("> quoted", .syntax) == [">"])
        let fenced = "```\n# not a heading\n```"
        #expect(texts(fenced, .heading(1)).isEmpty)
        #expect(texts(fenced, .code) == ["# not a heading"])
    }

    @Test func plainTextHasNoSpans_andPriceIsNotListMarker() {
        #expect(MarkdownSyntaxHighlighter.spans(in: "just words, 3 * 4 = 12 and a-b").isEmpty)
        #expect(MarkdownSyntaxHighlighter.spans(in: "").isEmpty)
    }

    @Test func rangesAreInsideTextAndUTF16Correct() {
        let s = "héllo 😀\n## Tëst **b**"
        let len = (s as NSString).length
        for span in MarkdownSyntaxHighlighter.spans(in: s) { #expect(NSMaxRange(span.range) <= len) }
        #expect(texts(s, .bold) == ["b"])
    }
}

@Suite struct MarkdownFormattingTests {
    func apply(_ c: MarkdownCommand, _ text: String, _ sel: NSRange) -> (String, NSRange) {
        let e = MarkdownFormatting.edit(c, in: text, selection: sel)
        return ((text as NSString).replacingCharacters(in: e.range, with: e.replacement), e.selection)
    }

    @Test func bold() {
        let (t, s) = apply(.bold, "hello world", NSRange(location: 6, length: 5))
        #expect(t == "hello **world**" && s == NSRange(location: 8, length: 5))
        let (u, _) = apply(.bold, t, s)
        #expect(u == "hello world")
        #expect(apply(.bold, "", NSRange(location: 0, length: 0)).0 == "**bold**")
    }

    @Test func headingCycles() {
        var (t, s) = apply(.heading, "Title\nbody", NSRange(location: 2, length: 0))
        #expect(t == "# Title\nbody")
        (t, s) = apply(.heading, t, s); #expect(t == "## Title\nbody")
        (t, s) = apply(.heading, t, s); #expect(t == "### Title\nbody")
        (t, _) = apply(.heading, t, s); #expect(t == "Title\nbody")
    }

    @Test func listAndLink() {
        let (t, _) = apply(.list, "a\nb\nc", NSRange(location: 0, length: 5))
        #expect(t == "- a\n- b\n- c")
        #expect(apply(.list, t, NSRange(location: 0, length: t.count)).0 == "a\nb\nc")
        #expect(apply(.link, "see docs", NSRange(location: 4, length: 4)).0 == "see [docs](https://)")
    }
}

@Suite struct MarkdownPreviewTests {
    @Test func blocks() {
        let b = MarkdownPreviewParser.blocks("# Title\n\nSome **bold** text\nwraps.\n\n- one\n- two\n1. first\n\n```\ncode\n```\n---")
        #expect(b.count == 7)
        if case let .heading(level, text) = b[0] { #expect(level == 1 && String(text.characters) == "Title") } else { Issue.record("heading") }
        if case let .paragraph(text) = b[1] { #expect(String(text.characters) == "Some bold text wraps.") } else { Issue.record("para") }
        #expect(b[6] == .rule)
        if case let .code(c) = b[5] { #expect(c == "code") } else { Issue.record("code") }
    }
}

@Suite struct CropRectTests {
    @Test func grabMoveResize() {
        let c = CropRect(CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        #expect(c.grab(at: CGPoint(x: 0.21, y: 0.2), tolerance: 0.02) == .corner(.topLeft))
        #expect(c.grab(at: CGPoint(x: 0.4, y: 0.4), tolerance: 0.02) == .inside)
        #expect(c.grab(at: CGPoint(x: 0.9, y: 0.9), tolerance: 0.02) == .none)
        #expect(c.moved(by: CGSize(width: 1, height: 0)).rect.maxX == 1)
        let r = c.resized(corner: .bottomRight, to: CGPoint(x: 2, y: 0.8)).rect
        #expect(abs(r.maxX - 1) < 1e-9 && abs(r.maxY - 0.8) < 1e-9 && r.minX == 0.2 && r.minY == 0.2)
        #expect(CropRect(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)).pixelRect(width: 200, height: 100) == CGRect(x: 50, y: 50, width: 100, height: 25))
    }
}

@Suite struct ImageOpsTests {
    /// 4x2 image: left half red, right half blue; top-left pixel marked green.
    func sample() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 2, y: 0, width: 2, height: 2))
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 1, width: 1, height: 1))  // CG origin bottom-left => top-left pixel
        return ctx.makeImage()!
    }

    /// Pixel at (x, y) from the top-left as "r", "g", "b".
    func px(_ image: CGImage, _ x: Int, _ y: Int) -> String {
        let rep = NSBitmapImageRep(cgImage: image)
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return c.redComponent > 0.5 ? "r" : c.greenComponent > 0.5 ? "g" : "b"
    }

    @Test func cropClampsAndSizes() {
        let img = sample()
        let c = ImageOps.crop(img, to: CGRect(x: 2, y: 0, width: 10, height: 10))
        #expect(c?.width == 2 && c?.height == 2)
        #expect(px(c!, 0, 0) == "b")
        #expect(ImageOps.crop(img, to: CGRect(x: 10, y: 10, width: 3, height: 3)) == nil)
    }

    @Test func resizeAndAspect() {
        let img = sample()
        let r = ImageOps.resize(img, width: 8, height: 4)
        #expect(r?.width == 8 && r?.height == 4)
        #expect(ImageOps.height(forWidth: 100, keepingAspectOf: (4032, 3024)) == 75)
        #expect(ImageOps.width(forHeight: 75, keepingAspectOf: (4032, 3024)) == 100)
        #expect(ImageOps.resize(img, width: 0, height: 4) == nil)
    }

    @Test func rotate() {
        let img = sample()
        let cw = ImageOps.rotate90(img, clockwise: true)!
        #expect(cw.width == 2 && cw.height == 4)
        #expect(px(cw, 1, 0) == "g")          // top-left goes to top-right when rotating clockwise
        #expect(px(cw, 0, 0) == "r" && px(cw, 0, 3) == "b")   // left column: former bottom row, left->right becomes top->bottom
        let ccw = ImageOps.rotate90(img, clockwise: false)!
        #expect(px(ccw, 0, 3) == "g")          // top-left goes to bottom-left
        let back = ImageOps.rotate90(cw, clockwise: false)!
        #expect(back.width == 4 && px(back, 0, 0) == "g")
    }

    @Test func flip() {
        let img = sample()
        let h = ImageOps.flip(img, horizontal: true)!
        #expect(px(h, 3, 0) == "g" && px(h, 0, 0) == "b")
        let v = ImageOps.flip(img, horizontal: false)!
        #expect(px(v, 0, 1) == "g" && px(v, 0, 0) == "r")
    }

    @Test func nsImageRoundTrip() {
        let ns = ImageOps.nsImage(from: sample())
        #expect(ImageOps.pixelSize(of: ns) == (4, 2))
        #expect(ImageOps.cgImage(from: ns)?.width == 4)
    }
}

@Suite struct SignatureTests {
    @Test func pngIsTightAndTransparent() throws {
        let strokes: [[CGPoint]] = [[CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40), CGPoint(x: 110, y: 20)]]
        let data = try #require(SignaturePad.png(strokes: strokes, size: CGSize(width: 440, height: 180)))
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.hasAlpha)
        #expect(rep.pixelsWide == (100 + 12) * 2 && rep.pixelsHigh == (30 + 12) * 2)
        #expect(rep.colorAt(x: 0, y: 0)?.alphaComponent == 0)
        #expect(SignaturePad.png(strokes: [], size: .zero) == nil)
    }
}

@Suite struct QuickCreateStateTests {
    @Test func folderName() {
        #expect(QuickCreateState(folderPath: "~/Desktop").folderName == "Desktop")
        #expect(QuickCreateState(folderPath: "/Users/x/Documents/Notes").folderName == "Notes")
        #expect(QuickCreateState().name == "Untitled" && QuickCreateState().format == "md")
        #expect(ShortcutFormat.glyphs("ctrl+opt+n") == "⌃⌥N")
    }
}
