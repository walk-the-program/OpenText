import SwiftUI
import AppKit
import OpenTextDesign

public struct TextEditorActions {
    public var onConvert: () -> Void
    public var onLock: () -> Void
    /// .txt only: flip between Geist and Geist Mono (D-016). The app stores the choice and passes `monospace` back.
    public var onToggleMonospace: () -> Void

    public init(onConvert: @escaping () -> Void = {}, onLock: @escaping () -> Void = {}, onToggleMonospace: @escaping () -> Void = {}) {
        self.onConvert = onConvert
        self.onLock = onLock
        self.onToggleMonospace = onToggleMonospace
    }
}

/// Plain-text editor. Never rich text. For Markdown files: syntax characters muted, Edit/Preview, formatting tools.
/// The tool row fades out shortly after typing starts and returns when the mouse moves.
public struct TextEditorView: View {
    @Binding var text: String
    let isMarkdown: Bool
    let monospace: Bool
    let isSaved: Bool
    let actions: TextEditorActions
    let header: DocumentHeader?
    let commands: DocumentCommands?

    @State private var mode: Mode = .edit
    @State private var toolbarOpacity: Double = 1
    @State private var fadeTask: Task<Void, Never>?
    @State private var controller = TextEditorController()
    @State private var wordLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Mode: String, CaseIterable { case edit = "Edit", preview = "Preview" }

    /// Snapshot/testing hooks (internal): start with the tool row already faded, or in Preview.
    func startingFaded() -> Self { var c = self; c._toolbarOpacity = State(initialValue: 0); return c }
    func startingInPreview() -> Self { var c = self; c._mode = State(initialValue: .preview); return c }

    /// Seconds between the first keystroke and the toolbar starting to fade.
    static let fadeDelay: Duration = .milliseconds(400)

    public init(text: Binding<String>, isMarkdown: Bool, monospace: Bool = false, isSaved: Bool = true,
                actions: TextEditorActions = .init(), header: DocumentHeader? = nil, commands: DocumentCommands? = nil) {
        self.commands = commands
        _text = text
        _wordLabel = State(initialValue: WordCounter.label(text.wrappedValue))
        self.isMarkdown = isMarkdown
        self.monospace = monospace
        self.isSaved = isSaved
        self.actions = actions
        self.header = header
    }

    /// `commands`: when given, the app menu owns Heading, Bold, Italic, List and Link shortcuts (they are dropped here),
    /// every change to `text` marks `commands` dirty, and the view registers its command handlers on it.
    private func key(_ s: KeyboardShortcut) -> KeyboardShortcut? { commands == nil ? s : nil }

    private func registerCommands() {
        var h: [DocumentCommands.Command: () -> Void] = [:]
        if isMarkdown {
            if mode == .edit {
                for level in 1...3 { h[.heading(level)] = { controller.perform(.headingLevel(level)) } }
                h[.bold] = { controller.perform(.bold) }
                h[.italic] = { controller.perform(.italic) }
                h[.list] = { controller.perform(.list) }
                h[.link] = { controller.perform(.link) }
            }
            h[.togglePreview] = { mode = mode == .edit ? .preview : .edit }
        } else {
            h[.toggleMonospace] = { actions.onToggleMonospace() }
        }
        commands?.register(kind: .text, handlers: h)
    }

    /// Word count and saved state live in the header, top right; the editor has no bottom bar.
    private var headerWithStatus: DocumentHeader? {
        guard var h = header else { return nil }
        h.status = "\(wordLabel) · \(isSaved ? "Saved" : "Edited")"
        return h
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolbarRow(header: headerWithStatus, toolsOpacity: toolbarOpacity) {
                if isMarkdown {
                    BrandSegmented(options: Mode.allCases.map(\.rawValue), selection: Binding(
                        get: { mode.rawValue }, set: { mode = Mode(rawValue: $0) ?? .edit }))
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                    Rectangle().fill(Brand.Palette.line).frame(width: 1, height: 20).padding(.horizontal, 4)
                    ToolButton(title: "Heading", shortcut: key(.init("1", modifiers: [.command, .option]))) { controller.perform(.heading) }.disabled(mode == .preview)
                    ToolButton(title: "Bold", shortcut: key(.init("b", modifiers: .command))) { controller.perform(.bold) }.disabled(mode == .preview)
                    ToolButton(title: "List", shortcut: key(.init("l", modifiers: [.command, .shift]))) { controller.perform(.list) }.disabled(mode == .preview)
                    ToolButton(title: "Link", shortcut: key(.init("k", modifiers: .command))) { controller.perform(.link) }.disabled(mode == .preview)
                } else {
                    // Shows the font in use; picking the other one switches (⇧⌘M toggles).
                    BrandSegmentedControl(["Geist", "Mono"], selection: Binding(
                        get: { monospace ? "Mono" : "Geist" },
                        set: { if ($0 == "Mono") != monospace { actions.onToggleMonospace() } }),
                        title: { $0 }, accessibilityTitle: { "\($0) font" })
                    .background(Button("") { actions.onToggleMonospace() }
                        .keyboardShortcut("m", modifiers: [.command, .shift]).opacity(0).allowsHitTesting(false))
                }
            } trailing: {
                ToolButton(title: "Lock", shortcut: .init("l", modifiers: [.command, .option])) { actions.onLock() }
                Button("Convert", action: actions.onConvert)
                    .buttonStyle(.primaryAction).keyboardShortcut("e", modifiers: [.command, .shift])
            }
            ZStack {
                Brand.Palette.canvas
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack {
                        if isMarkdown && mode == .preview {
                            ScrollView { MarkdownPreview(markdown: text).padding(.horizontal, 88).padding(.vertical, 44) }
                                .transition(.opacity.combined(with: .offset(y: 6)))
                        } else {
                            PlainTextView(text: $text, isMarkdown: isMarkdown, monospace: monospace, controller: controller, onTyping: typed)
                                .padding(.horizontal, 80).padding(.vertical, 8)
                                .transition(.opacity)
                        }
                    }
                    .animation(Brand.Motion.settle, value: mode)
                    .frame(maxWidth: 820, maxHeight: .infinity)
                    .background(UnevenRoundedRectangle(topLeadingRadius: Brand.Radius.card, topTrailingRadius: Brand.Radius.card,
                                                       style: .continuous).fill(Brand.Palette.card))
                    .padding(.top, 14)
                    Spacer(minLength: 0)
                }
            }
        }
        .onContinuousHover { phase in if case .active = phase { revealToolbar() } }
        .onAppear { registerCommands() }
        .onChange(of: mode) { _, _ in registerCommands() }
        .onChange(of: text) { _, _ in commands?.markDirty() }
        .task(id: text) {
            // Word count is a full scan; wait for typing to pause.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            wordLabel = WordCounter.label(text)
        }
        .onDisappear { fadeTask?.cancel(); commands?.unregister() }
    }

    private func typed() {
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: Self.fadeDelay)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : Brand.Motion.enter) { toolbarOpacity = 0 }
        }
    }

    private func revealToolbar() {
        fadeTask?.cancel()
        guard toolbarOpacity < 1 else { return }
        withAnimation(reduceMotion ? nil : Brand.Motion.settle) { toolbarOpacity = 1 }
    }
}

/// One segmented control: a recessed track holding the segments. The selected segment is
/// `Palette.ink` with canvas text, the others are clear with ink text (primary stays on the one action button).
struct BrandSegmented: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        BrandSegmentedControl(options, selection: $selection, title: { $0 })
    }
}

// MARK: - NSTextView wrapper

@MainActor final class TextEditorController {
    weak var textView: NSTextView?

    func perform(_ command: MarkdownCommand) {
        guard let tv = textView else { return }
        let edit = MarkdownFormatting.edit(command, in: tv.string, selection: tv.selectedRange())
        guard tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        tv.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        tv.didChangeText()
        tv.setSelectedRange(edit.selection)
        tv.window?.makeFirstResponder(tv)
    }
}

struct PlainTextView: NSViewRepresentable {
    @Binding var text: String
    let isMarkdown: Bool
    let monospace: Bool
    let controller: TextEditorController
    var onTyping: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 36)
        tv.insertionPointColor = Brand.NSPalette.ink
        tv.delegate = context.coordinator
        tv.setAccessibilityLabel("Document text")
        controller.textView = tv
        tv.string = text
        tv.textStorage?.delegate = context.coordinator
        context.coordinator.style(tv, parent: self, force: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        context.coordinator.parent = self
        controller.textView = tv
        if tv.string != text { tv.string = text }
        context.coordinator.style(tv, parent: self)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: PlainTextView
        private var lastStyleKey = ""
        private var fenceTouched = false
        init(_ parent: PlainTextView) { self.parent = parent }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            parent.onTyping()
            // A code fence leaving or entering the text changes how later lines read.
            let ns = textView.string as NSString
            fenceTouched = parent.isMarkdown
                && (PlainTextStyler.containsFence(ns, in: ns.paragraphRange(for: affectedCharRange))
                    || (replacementString?.contains("```") ?? false) || (replacementString?.contains("~~~") ?? false))
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        /// Restyles only the paragraphs an edit touched.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            nonisolated(unsafe) let textStorage = textStorage
            MainActor.assumeIsolated {
                let range = PlainTextStyler.restyleRange(in: textStorage.string as NSString, edited: editedRange, fenceTouched: fenceTouched)
                fenceTouched = false
                PlainTextStyler.apply(to: textStorage, range: range, isMarkdown: parent.isMarkdown, monospace: parent.monospace)
            }
        }

        /// Full restyle, only when the markdown/monospace mode changed (or `force`).
        func style(_ tv: NSTextView, parent: PlainTextView, force: Bool = false) {
            let key = "\(parent.isMarkdown)|\(parent.monospace)"
            guard force || key != lastStyleKey, let storage = tv.textStorage else { return }
            lastStyleKey = key
            PlainTextStyler.apply(to: storage, isMarkdown: parent.isMarkdown, monospace: parent.monospace)
            tv.typingAttributes = PlainTextStyler.baseAttributes(monospace: parent.monospace)
        }
    }
}

/// Paints text storage attributes. Characters are never changed; only fonts and colours.
enum PlainTextStyler {
    /// Roomy reading text: 16pt Inter with ~1.7 line height and a little air after each paragraph.
    static let size: CGFloat = 16

    static func baseFont(monospace: Bool) -> NSFont {
        monospace ? Brand.Fonts.nsMono(15) : Brand.Fonts.nsBody(size)
    }

    static func baseAttributes(monospace: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        // About 1.7 line height, as in the approved Bento render; list lines stay close, paragraphs breathe.
        style.lineSpacing = monospace ? 8 : 10
        style.paragraphSpacing = monospace ? 2 : 3
        var attrs: [NSAttributedString.Key: Any] = [.font: baseFont(monospace: monospace), .foregroundColor: Brand.NSPalette.ink,
                                                    .paragraphStyle: style]
        if !monospace { attrs[.kern] = 0.16 }
        return attrs
    }

    /// Full restyle (load, md/txt or monospace switch).
    static func apply(to storage: NSTextStorage, isMarkdown: Bool, monospace: Bool) {
        storage.beginEditing()
        apply(to: storage, range: NSRange(location: 0, length: storage.length), isMarkdown: isMarkdown, monospace: monospace)
        storage.endEditing()
    }

    /// The range an edit must restyle: whole paragraphs around `edited`; to the end of the text when
    /// a code fence was involved (fences change how every later line reads).
    static func restyleRange(in string: NSString, edited: NSRange, fenceTouched: Bool) -> NSRange {
        let clamped = NSIntersectionRange(edited, NSRange(location: 0, length: string.length))
        var r = string.paragraphRange(for: NSRange(location: min(edited.location, string.length), length: clamped.length))
        if fenceTouched || containsFence(string, in: r) { r.length = string.length - r.location }
        return r
    }

    static func containsFence(_ string: NSString, in range: NSRange) -> Bool {
        var found = false
        string.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, line, _, stop in
            if MarkdownSyntaxHighlighter.isFence(string, line) { found = true; stop.pointee = true }
        }
        return found
    }

    /// Restyles `range` only (caller supplies begin/endEditing). Over-limit documents and lines stay plain body.
    static func apply(to storage: NSTextStorage, range: NSRange, isMarkdown: Bool, monospace: Bool) {
        storage.setAttributes(baseAttributes(monospace: monospace), range: range)
        guard isMarkdown, storage.length <= MarkdownSyntaxHighlighter.maxDocumentLength else { return }
        let ns = storage.string as NSString
        for span in MarkdownSyntaxHighlighter.spans(in: storage.string, range: range) where NSMaxRange(span.range) <= storage.length {
            switch span.kind {
            case .syntax: storage.addAttribute(.foregroundColor, value: Brand.NSPalette.muted, range: span.range)
            case let .heading(level):
                let line = ns.lineRange(for: NSRange(location: span.range.location, length: 0))
                let end = min(NSMaxRange(span.range), NSMaxRange(line))
                let range = NSRange(location: line.location, length: end - line.location)
                let pt: CGFloat = level == 1 ? 26 : level == 2 ? 20 : 17
                storage.addAttribute(.font, value: Brand.Fonts.nsHeading(pt), range: range)
            case .bold: storage.addAttribute(.font, value: Brand.Fonts.nsBody(size, weight: .semibold), range: span.range)
            case .italic: storage.addAttribute(.obliqueness, value: 0.18, range: span.range)
            case .code: storage.addAttribute(.font, value: Brand.Fonts.nsMono(13.5), range: span.range)
            }
        }
    }
}
