import SwiftUI
import AppKit
import OpenTextDesign

public struct RichTextActions {
    public var onConvert: () -> Void
    /// "txt" or "md": the app converts next to the original.
    public var onSaveAs: (String) -> Void

    public init(onConvert: @escaping () -> Void = {}, onSaveAs: @escaping (String) -> Void = { _ in }) {
        self.onConvert = onConvert
        self.onSaveAs = onSaveAs
    }
}

/// Read-only viewer for rtf / docx / doc / odt content. The document keeps its own fonts and colours, so the
/// page stays white in dark mode too (like a printed page). Selectable; nothing is ever edited or saved.
public struct RichTextView: View {
    let attributed: NSAttributedString
    let actions: RichTextActions
    let header: DocumentHeader?
    @State private var wordLabel: String

    public init(attributed: NSAttributedString, actions: RichTextActions = .init(), header: DocumentHeader? = nil) {
        self.attributed = attributed
        self.actions = actions
        self.header = header
        _wordLabel = State(initialValue: WordCounter.label(attributed.string))
    }

    private var headerWithStatus: DocumentHeader? {
        guard var h = header else { return nil }
        h.status = "\(wordLabel) · Read-only"
        return h
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolbarRow(header: headerWithStatus) {
                ToolButton(title: "Copy Text") { copyText() }
                ToolButton(title: "Save as .txt") { actions.onSaveAs("txt") }
                ToolButton(title: "Save as .md") { actions.onSaveAs("md") }
            } trailing: {
                Button("Convert", action: actions.onConvert)
                    .buttonStyle(.primaryAction).keyboardShortcut("e", modifiers: [.command, .shift])
            }
            ZStack {
                Brand.Palette.canvas
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RichTextBody(attributed: attributed)
                        .padding(.horizontal, 56).padding(.vertical, 8)
                        .frame(maxWidth: 860, maxHeight: .infinity)
                        .background(Color.white)
                        .overlay(alignment: .leading) { Rectangle().fill(Brand.Palette.line).frame(width: 1) }
                        .overlay(alignment: .trailing) { Rectangle().fill(Brand.Palette.line).frame(width: 1) }
                    Spacer(minLength: 0)
                }
            }
        }
        .task(id: attributed.length) { wordLabel = WordCounter.label(attributed.string) }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(attributed.string, forType: .string)
    }
}

private struct RichTextBody: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        // Pinned to Aqua: document text without its own colour is black, and the page is white.
        scroll.appearance = NSAppearance(named: .aqua)
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.isRichText = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 0, height: 28)
            tv.textStorage?.setAttributedString(attributed)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.textStorage?.length != attributed.length else { return }
        tv.textStorage?.setAttributedString(attributed)
    }
}
