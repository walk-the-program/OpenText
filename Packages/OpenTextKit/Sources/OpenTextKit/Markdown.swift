import Foundation
import Markdown

/// Markdown → HTML using swift-markdown's parser (CommonMark + GFM).
enum MD {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func toHTML(_ markdown: String) -> String {
        var v = HTMLVisitor()
        return v.visit(Document(parsing: markdown))
    }

    static func document(body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title></head>
        <body>
        \(body)
        </body></html>
        """
    }

    /// Plain text → HTML paragraphs (blank-line separated; single newlines become <br>).
    static func plainToHTML(_ text: String) -> String {
        let paras = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return paras.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map {
            "<p>" + escape($0.trimmingCharacters(in: .newlines)).replacingOccurrences(of: "\n", with: "<br>\n") + "</p>"
        }.joined(separator: "\n")
    }
}

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func children(_ m: Markup) -> String {
        var out = ""
        for c in m.children { out += visit(c) }
        return out
    }
    mutating func defaultVisit(_ m: Markup) -> String { children(m) }
    mutating func visitText(_ t: Text) -> String { MD.escape(t.string) }
    mutating func visitParagraph(_ p: Paragraph) -> String { "<p>\(children(p))</p>\n" }
    mutating func visitHeading(_ h: Heading) -> String { "<h\(h.level)>\(children(h))</h\(h.level)>\n" }
    mutating func visitEmphasis(_ e: Emphasis) -> String { "<em>\(children(e))</em>" }
    mutating func visitStrong(_ s: Strong) -> String { "<strong>\(children(s))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(children(s))</del>" }
    mutating func visitInlineCode(_ c: InlineCode) -> String { "<code>\(MD.escape(c.code))</code>" }
    mutating func visitCodeBlock(_ c: CodeBlock) -> String { "<pre><code>\(MD.escape(c.code))</code></pre>\n" }
    mutating func visitBlockQuote(_ b: BlockQuote) -> String { "<blockquote>\n\(children(b))</blockquote>\n" }
    mutating func visitThematicBreak(_ t: ThematicBreak) -> String { "<hr>\n" }
    mutating func visitLineBreak(_ l: LineBreak) -> String { "<br>\n" }
    mutating func visitSoftBreak(_ s: SoftBreak) -> String { "\n" }
    mutating func visitInlineHTML(_ h: InlineHTML) -> String { MD.escape(h.rawHTML) }
    mutating func visitHTMLBlock(_ h: HTMLBlock) -> String { "<p>\(MD.escape(h.rawHTML.trimmingCharacters(in: .newlines)))</p>\n" }
    mutating func visitLink(_ l: Link) -> String { "<a href=\"\(MD.escape(l.destination ?? ""))\">\(children(l))</a>" }
    mutating func visitImage(_ i: Image) -> String {
        // Never emit <img>: conversion must not fetch remote or file:// resources.
        MD.escape(i.plainText.isEmpty ? (i.source ?? "") : i.plainText)
    }
    mutating func visitUnorderedList(_ l: UnorderedList) -> String { "<ul>\n\(children(l))</ul>\n" }
    mutating func visitOrderedList(_ l: OrderedList) -> String { "<ol>\n\(children(l))</ol>\n" }
    mutating func visitListItem(_ i: ListItem) -> String {
        // Tight lists: unwrap single paragraphs.
        var inner = ""
        for c in i.children {
            if let p = c as? Paragraph { inner += children(p) + "\n" } else { inner += visit(c) }
        }
        return "<li>\(inner.trimmingCharacters(in: .newlines))</li>\n"
    }
    mutating func visitTable(_ t: Markdown.Table) -> String { "<table>\n\(children(t))</table>\n" }
    mutating func visitTableHead(_ t: Markdown.Table.Head) -> String { "<thead><tr>\(children(t))</tr></thead>\n" }
    mutating func visitTableBody(_ t: Markdown.Table.Body) -> String { "<tbody>\n\(children(t))</tbody>\n" }
    mutating func visitTableRow(_ t: Markdown.Table.Row) -> String { "<tr>\(children(t))</tr>\n" }
    mutating func visitTableCell(_ t: Markdown.Table.Cell) -> String { "<td>\(children(t))</td>" }
}

