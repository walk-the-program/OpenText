import SwiftUI
import OpenTextDesign

/// Block structure of a Markdown document for the Preview pane. Inline styling uses `AttributedString(markdown:)`.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case bullet(AttributedString)
    case numbered(Int, AttributedString)
    case quote(AttributedString)
    case code(String)
    case rule
}

public enum MarkdownPreviewParser {
    public static func blocks(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func inline(_ s: String) -> AttributedString {
            (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        }
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(inline(paragraph.joined(separator: " ")))); paragraph = [] }
        }
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(line); continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); continue }
            if let m = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flush(); blocks.append(.heading(level: m.1.count, text: inline(String(m.2))))
            } else if trimmed.wholeMatch(of: /([-*_])(\s*\1){2,}/) != nil {
                flush(); blocks.append(.rule)
            } else if let m = line.firstMatch(of: /^\s*[-*+]\s+(.*)$/) {
                flush(); blocks.append(.bullet(inline(String(m.1))))
            } else if let m = line.firstMatch(of: /^\s*(\d{1,9})[.)]\s+(.*)$/) {
                flush(); blocks.append(.numbered(Int(m.1) ?? 1, inline(String(m.2))))
            } else if let m = line.firstMatch(of: /^\s*>\s?(.*)$/) {
                flush(); blocks.append(.quote(inline(String(m.1))))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

struct MarkdownPreview: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownPreviewParser.blocks(markdown)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(text).brandHeading(level == 1 ? 26 : level == 2 ? 20 : 16)
                        .padding(.top, level == 1 ? 4 : 10)
                case let .paragraph(text):
                    Text(text).font(Brand.Fonts.body(15)).foregroundStyle(Brand.Palette.ink).lineSpacing(4)
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Brand.Palette.muted)
                        Text(text).lineSpacing(4)
                    }.font(Brand.Fonts.body(15)).foregroundStyle(Brand.Palette.ink)
                case let .numbered(n, text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(Brand.Palette.muted)
                        Text(text).lineSpacing(4)
                    }.font(Brand.Fonts.body(15)).foregroundStyle(Brand.Palette.ink)
                case let .quote(text):
                    HStack(spacing: 10) {
                        Capsule().fill(Brand.Palette.primary).frame(width: 3)
                        Text(text).font(Brand.Fonts.body(15)).foregroundStyle(Brand.Palette.muted)
                    }
                case let .code(code):
                    Text(code).font(Brand.Fonts.mono(13)).foregroundStyle(Brand.Palette.ink)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .recessedSurface(radius: Brand.Radius.md, fill: Brand.Palette.canvas)
                case .rule:
                    Rectangle().fill(Brand.Palette.line).frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
