import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import OpenTextDesign

public struct PDFReaderActions {
    /// The one primary action in the window.
    public var onConvert: () -> Void
    /// Returns the saved signature PNG, or nil if none was drawn yet (the pad opens instead).
    public var loadSignature: () -> Data?
    /// Called once with the PNG when the user finishes drawing.
    public var saveSignature: (Data) -> Void
    /// Forgets the saved signature (the next Sign opens the pad).
    public var clearSignature: () -> Void
    /// The document changed (pages moved/deleted/inserted/rotated, highlight or signature added). Mark dirty / autosave.
    public var onChange: () -> Void

    public init(onConvert: @escaping () -> Void = {},
                loadSignature: @escaping () -> Data? = { nil },
                saveSignature: @escaping (Data) -> Void = { _ in },
                clearSignature: @escaping () -> Void = {},
                onChange: @escaping () -> Void = {}) {
        self.onConvert = onConvert
        self.loadSignature = loadSignature
        self.saveSignature = saveSignature
        self.clearSignature = clearSignature
        self.onChange = onChange
    }
}

/// Reader/editor for a PDF: recessed thumbnail well, page canvas, tools, search, zoom, status line.
public struct PDFReaderView: View {
    let actions: PDFReaderActions
    let header: DocumentHeader?
    let commands: DocumentCommands?
    @State private var model: PDFReaderModel
    @FocusState private var sidebarFocused: Bool
    @FocusState private var searchFocused: Bool
    /// Snapshot hook: PDFView draws no page content when it is not in a window, so tests render a still of the page instead.
    private var offscreenStill = false

    func offscreenSnapshot(startingAt index: Int) -> Self {
        var c = self
        c.offscreenStill = true
        c.model.currentIndex = index
        c.model.selectedPages = [index]
        return c
    }

    /// `commands`: when given, the app menu owns Find, Zoom, Thumbnails and Rotate shortcuts (they are dropped here),
    /// every edit marks `commands` dirty, and the view registers its command handlers on it.
    public init(document: PDFDocument, actions: PDFReaderActions = .init(), header: DocumentHeader? = nil, commands: DocumentCommands? = nil) {
        self.actions = actions
        self.header = header
        self.commands = commands
        let m = PDFReaderModel(document: document)
        m.commands = commands
        m.actions = actions
        _model = State(initialValue: m)
    }

    /// In-view shortcut, dropped when the app menu owns it.
    private func key(_ s: KeyboardShortcut) -> KeyboardShortcut? { commands == nil ? s : nil }

    private func registerCommands() {
        commands?.register(kind: .pdf, handlers: [
            .find: { if !model.showsSearch { model.toggleSearch() }; searchFocused = true },
            .toggleThumbnails: { model.showsSidebar.toggle() },
            .zoomIn: { model.zoomIn() }, .zoomOut: { model.zoomOut() }, .actualSize: { model.actualSize() },
            .rotate: { model.rotate(by: 90) }, .rotateLeft: { model.rotate(by: -90) },
            .highlight: { model.highlight() }, .sign: { model.sign() }, .addText: { model.addTextBox() },
            .insertPages: { model.insertFromFile() }, .extractPages: { model.extractSelectedPages() },
            .deletePages: { model.deleteSelectedPages() },
        ])
    }

    private var headerWithStatus: DocumentHeader? {
        guard var h = header else { return nil }
        h.status = model.statusText
        return h
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolbarRow(header: headerWithStatus) {
                ToolGroup {
                    GroupedTool(title: "Select", active: !model.highlightMode) { model.highlightMode = false }
                    GroupedTool(title: "Highlight", active: model.highlightMode, shortcut: key(.init("h", modifiers: [.command, .shift]))) { model.highlight() }
                    GroupedTool(title: "Text", shortcut: key(.init("t", modifiers: [.command, .shift]))) { model.addTextBox() }
                    signMenu
                }
                pagesMenu
                ToolButton(title: "Search", shortcut: key(.init("f", modifiers: .command)), isActive: model.showsSearch) { model.toggleSearch() }
                zoomMenu
            } trailing: {
                Button("Convert", action: actions.onConvert)
                    .buttonStyle(.primaryAction).keyboardShortcut("e", modifiers: [.command, .shift])
            }
            if model.showsSearch { searchBar }
            if model.highlightMode { highlightHint }
            HStack(spacing: 14) {
                if model.showsSidebar { sidebar }
                Group {
                    if offscreenStill { PageStill(model: model) } else { PDFCanvas(model: model) }
                }
                .background(Brand.Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.card, style: .continuous))
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        HStack(spacing: 14) {
                            Text(toast).font(Brand.Fonts.body(13, weight: .medium))
                            Button("Undo") { model.undo.undo(); model.toast = nil }
                                .buttonStyle(PressableStyle())
                                .font(Brand.Fonts.body(13, weight: .semibold))
                                .padding(.horizontal, 12).frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.Palette.canvas.opacity(0.16)))
                        }
                        .foregroundStyle(Brand.Palette.canvas)
                        .padding(.leading, 16).padding(.trailing, 7).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.Palette.ink))
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(Brand.Motion.enter, value: model.toast)
            }
            .padding(14)
        }
        .background(Brand.Palette.canvas)
        .animation(Brand.Motion.settle, value: model.showsSearch)
        .animation(Brand.Motion.settle, value: model.highlightMode)
        .onAppear { registerCommands() }
        .onDisappear { commands?.unregister() }
        .sheet(isPresented: $model.showsSignaturePad) {
            SignaturePad(onDone: { png in model.showsSignaturePad = false; actions.saveSignature(png); model.place(png: png) },
                         onCancel: { model.showsSignaturePad = false })
        }
    }

    /// Sign: places the saved signature (selected, ready to drag and resize); the menu draws a new one or clears it.
    private var signMenu: some View {
        Menu {
            Button("New Signature…") { model.newSignature() }
            Button("Clear Saved Signature") { actions.clearSignature() }
        } label: { GroupedToolLabel(title: "Sign", active: false) } primaryAction: { model.sign() }
        .menuStyle(.button).buttonStyle(PressableStyle()).menuIndicator(.hidden).fixedSize()
        .optionalShortcut(key(.init("s", modifiers: [.control, .command])))
        .accessibilityLabel("Sign")
    }

    private var pagesMenu: some View {
        Menu {
            Button("Rotate Right") { model.rotate(by: 90) }.optionalShortcut(key(.init("r", modifiers: .command)))
            Button("Rotate Left") { model.rotate(by: -90) }.optionalShortcut(key(.init("r", modifiers: [.command, .shift])))
            Divider()
            Button("Insert Pages from File…") { model.insertFromFile() }
            Button(model.selectedPages.count > 1 ? "Extract \(model.selectedPages.count) Pages…" : "Extract Page…") { model.extractSelectedPages() }
            Divider()
            Button(model.selectedPages.count > 1 ? "Delete \(model.selectedPages.count) Pages" : "Delete Page") { model.deleteSelectedPages() }
                .disabled(model.selectedPages.count >= model.pageCount)
        } label: { Text("Pages") }
        .menuStyle(.button).buttonStyle(.toolbarItem).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Pages")
    }

    private var highlightHint: some View {
        HStack(spacing: Brand.Spacing.sm) {
            Circle().fill(Brand.Palette.accent).frame(width: 8, height: 8)
            Text("Highlight is on: select text to highlight it.").font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.ink)
            Spacer()
            Button("Done") { model.highlightMode = false }.buttonStyle(.toolbarItem)
        }
        .padding(.horizontal, 14).frame(height: 36)
        .background(Brand.Palette.priTint)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var zoomMenu: some View {
        Menu {
            Button("Zoom In") { model.zoomIn() }.optionalShortcut(key(.init("=", modifiers: .command)))
            Button("Zoom Out") { model.zoomOut() }.optionalShortcut(key(.init("-", modifiers: .command)))
            Button("Fit Width") { model.fit() }.optionalShortcut(key(.init("0", modifiers: .command)))
            Button("Actual Size") { model.actualSize() }
        } label: { Text("Zoom") }
        .menuStyle(.button).buttonStyle(.toolbarItem).menuIndicator(.hidden).fixedSize()
    }

    private var searchBar: some View {
        HStack(spacing: Brand.Spacing.sm) {
            TextField("Find in document", text: $model.query)
                .brandField().frame(width: 260)
                .focused($searchFocused)
                .onSubmit { model.next() }
                .onChange(of: model.query) { _, _ in model.runSearch() }
            Text(model.searchSummary).font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.muted)
            Button("Previous") { model.previous() }.buttonStyle(.toolbarItem).keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Next") { model.next() }.buttonStyle(.toolbarItem).keyboardShortcut("g", modifiers: .command)
            Spacer()
            Button("Done") { model.toggleSearch() }.buttonStyle(.toolbarItem).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(Brand.Palette.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.Palette.abHair).frame(height: 1) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            Text("Pages").brandLabel().padding(.leading, 6)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        ThumbnailCell(model: model, index: index)
                            .draggable(model.pagePayload(index))
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first, let from = model.pageIndex(fromPayload: raw) else { return false }
                                model.move(from: from, to: index); return true
                            }
                            .dropDestination(for: URL.self) { urls, _ in model.insertFiles(urls, at: index + 1) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(14)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .cardSurface(radius: Brand.Radius.card)
        .dropDestination(for: URL.self) { urls, _ in model.insertFiles(urls, at: model.pageCount) }
        .focusable()
        .focused($sidebarFocused)
        .focusEffectDisabled()
        .onDeleteCommand { model.deleteSelectedPages() }
        .accessibilityLabel("Page thumbnails")
    }
}

/// A flat image of the current page; only used for off-screen snapshots.
private struct PageStill: View {
    let model: PDFReaderModel
    var body: some View {
        if let page = model.document.page(at: model.currentIndex) {
            let box = page.bounds(for: .cropBox)
            let image = page.thumbnail(of: CGSize(width: 1100, height: 1100 * box.height / box.width), for: .cropBox)
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 560)
                .padding(.top, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct ThumbnailCell: View {
    let model: PDFReaderModel
    let index: Int
    var body: some View {
        let selected = model.selectedPages.contains(index)
        VStack(spacing: 4) {
            Group {
                if let image = model.thumbnail(index) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Brand.Palette.surface
                }
            }
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm)
                .stroke(selected ? Brand.Palette.primary : Brand.Palette.line, lineWidth: selected ? 2.5 : 1))
            .scaleEffect(selected ? 1 : 0.97)
            .animation(Brand.Motion.settle, value: selected)
            Text("\(index + 1)").font(Brand.Fonts.body(11, weight: .semibold))
                .foregroundStyle(selected ? Brand.Palette.ink : Brand.Palette.abMuted)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            model.clickThumbnail(index, command: flags.contains(.command), shift: flags.contains(.shift))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Model

@MainActor @Observable
final class PDFReaderModel {
    let document: PDFDocument
    /// Identifies this document in page-drag payloads so drops from another document are ignored.
    let id = UUID()
    weak var pdfView: EditablePDFView?
    @ObservationIgnored var actions = PDFReaderActions()
    /// Every page and annotation change is undoable. In a window this is the window's undo manager, so Edit >
    /// Undo (⌘Z / ⇧⌘Z) reaches it from any view in the window; without a window (tests) a private one.
    @ObservationIgnored private let detachedUndo = UndoManager()
    var undo: UndoManager { pdfView?.window?.undoManager ?? detachedUndo }
    var currentIndex = 0
    /// Thumbnails selected with ⌘-click / ⇧-click, always including the current page.
    var selectedPages: Set<Int> = [0]
    var revision = 0                 // bumps when pages change; thumbnails and counts refresh
    var showsSearch = false
    var showsSidebar = true
    /// Highlight tool: text selected with the mouse is highlighted when the button is released.
    var highlightMode = false
    @ObservationIgnored var commands: DocumentCommands?
    var showsSignaturePad = false
    /// Short confirmation at the foot of the page ("Signature placed…" with Undo); clears itself.
    var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    var query = ""
    var results: [PDFSelection] = []
    var resultIndex = 0
    private(set) var selectedAnnotation: PDFAnnotation?
    @ObservationIgnored private var frame: SelectionFrameAnnotation?
    @ObservationIgnored weak var editingBox: TextBoxAnnotation?
    private var thumbnails: [ObjectIdentifier: NSImage] = [:]

    init(document: PDFDocument) {
        self.document = document
    }

    var pageCount: Int { _ = revision; return document.pageCount }
    var statusText: String {
        let base = "Page \(min(currentIndex + 1, max(pageCount, 1))) of \(pageCount)"
        return selectedPages.count > 1 ? "\(selectedPages.count) pages selected · " + base : base
    }
    var searchSummary: String {
        if query.isEmpty { return "" }
        return results.isEmpty ? "No matches" : "\(resultIndex + 1) of \(results.count)"
    }

    func pagePayload(_ index: Int) -> String { "opentext-page:\(id.uuidString):\(index)" }

    /// The page index in a payload made by this document; nil for other documents or malformed text.
    func pageIndex(fromPayload raw: String) -> Int? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "opentext-page", parts[1] == Substring(id.uuidString),
              let index = Int(parts[2]), index >= 0, index < document.pageCount else { return nil }
        return index
    }

    func thumbnail(_ index: Int) -> NSImage? {
        _ = revision
        guard let page = document.page(at: index) else { return nil }
        let key = ObjectIdentifier(page)
        if let cached = thumbnails[key], page.rotation == cached.accessibilityDescription.flatMap({ Int($0) }) { return cached }
        let image = page.thumbnail(of: CGSize(width: 140, height: 160), for: .cropBox)
        image.accessibilityDescription = "\(page.rotation)"
        thumbnails[key] = image
        return image
    }

    func go(to index: Int) {
        guard let page = document.page(at: index) else { return }
        currentIndex = index
        selectedPages = [index]
        pdfView?.go(to: page)
    }

    /// ⌘-click toggles a page in the selection, ⇧-click selects the range from the current page.
    func clickThumbnail(_ index: Int, command: Bool, shift: Bool) {
        if shift {
            selectedPages = Set(min(currentIndex, index)...max(currentIndex, index))
        } else if command {
            if selectedPages.contains(index), selectedPages.count > 1 { selectedPages.remove(index) } else { selectedPages.insert(index) }
        } else {
            go(to: index); return
        }
        currentIndex = index
        if let page = document.page(at: index) { pdfView?.go(to: page) }
    }

    func pageChanged() {
        if let page = pdfView?.currentPage {
            let index = document.index(for: page)
            if index != currentIndex { currentIndex = index; if selectedPages.count <= 1 { selectedPages = [index] } }
        }
    }

    private var sortedSelection: [Int] { selectedPages.filter { $0 < document.pageCount }.sorted() }

    // MARK: Page operations (undoable)

    func move(from: Int, to: Int) {
        guard PDFPageOps.move(in: document, from: from, to: to) else { return }
        undo.registerUndo(withTarget: self) { $0.move(from: to, to: from) }
        undo.setActionName("Move Page")
        currentIndex = to
        selectedPages = [to]
        changed()
    }

    func rotate(by degrees: Int = 90) {
        let pages = sortedSelection
        for i in pages { PDFPageOps.rotate(in: document, pageAt: i, by: degrees) }
        undo.registerUndo(withTarget: self) { m in m.selectedPages = Set(pages); m.rotate(by: -degrees) }
        undo.setActionName("Rotate")
        changed()
    }

    func deleteSelectedPages() {
        let indexes = sortedSelection
        guard indexes.count < document.pageCount else { NSSound.beep(); return }
        let removed = indexes.compactMap { i in document.page(at: i).map { (i, $0) } }
        guard PDFPageOps.delete(in: document, at: indexes) > 0 else { return }
        undo.registerUndo(withTarget: self) { m in
            for (i, page) in removed { m.document.insert(page, at: min(i, m.document.pageCount)) }
            m.undo.registerUndo(withTarget: m) { $0.selectedPages = Set(indexes); $0.deleteSelectedPages() }
            m.selectedPages = Set(indexes)
            m.changed()
        }
        undo.setActionName(indexes.count == 1 ? "Delete Page" : "Delete Pages")
        currentIndex = min(indexes.first ?? 0, document.pageCount - 1)
        selectedPages = [currentIndex]
        changed()
        go(to: currentIndex)
    }

    @discardableResult func insertFiles(_ urls: [URL], at index: Int) -> Bool {
        var position = min(max(index, 0), document.pageCount)
        let start = position
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            guard let other = PDFDocument(url: url), !other.isLocked else { continue }
            position += PDFPageOps.insert(other, into: document, at: position)
        }
        let added = position - start
        guard added > 0 else { return false }
        undo.registerUndo(withTarget: self) { m in
            let pages = (start..<start + added).compactMap { m.document.page(at: $0) }
            for _ in 0..<added { m.document.removePage(at: start) }
            m.undo.registerUndo(withTarget: m) { m2 in
                for (k, page) in pages.enumerated() { m2.document.insert(page, at: start + k) }
                m2.changed()
            }
            m.changed()
        }
        undo.setActionName("Insert Pages")
        changed()
        return true
    }

    /// Asks for PDF files and inserts their pages after the current page.
    func insertFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.prompt = "Insert"
        panel.begin { [weak self] r in
            guard r == .OK else { return }
            MainActor.assumeIsolated { _ = self?.insertFiles(panel.urls, at: (self?.currentIndex ?? 0) + 1) }
        }
    }

    /// Writes the selected pages (signatures and text boxes burned in) to a new PDF the user names.
    func extractSelectedPages() {
        let indexes = sortedSelection
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Pages \(indexes.map { "\($0 + 1)" }.joined(separator: ", ")).pdf"
        panel.begin { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { _ = self?.extract(pages: indexes, to: url) }
        }
    }

    /// Extract without UI (tests, self-test). Returns false when nothing was written.
    @discardableResult func extract(pages: [Int], to url: URL) -> Bool {
        let out = PDFPageOps.extract(pages: pages, from: document)
        return out.pageCount > 0 && out.write(to: url)
    }

    // MARK: Annotations (undoable)

    func select(_ annotation: PDFAnnotation?) {
        guard annotation !== selectedAnnotation || annotation == nil else { refreshSelectionFrame(); return }
        if let frame, let page = frame.page { page.removeAnnotation(frame); pdfView?.annotationsChanged(on: page) }
        frame = nil
        selectedAnnotation = annotation
        guard let annotation, let page = annotation.page else { return }
        let f = SelectionFrameAnnotation(around: annotation.bounds)
        f.showsHandles = annotation.isMovable
        frame = f
        page.addAnnotation(f)
        refreshSelectionFrame()
        // Delete, arrows and Escape go to the PDF view right away.
        if let v = pdfView, v.window?.firstResponder !== v, !v.isEditingText { v.window?.makeFirstResponder(v) }
    }

    func refreshSelectionFrame() {
        guard let frame, let selected = selectedAnnotation, let page = selected.page else { return }
        frame.handleSize = 8 / max(pdfView?.scaleFactor ?? 1, 0.1)
        frame.frame(around: selected.bounds)
        pdfView?.annotationsChanged(on: page)
    }

    func hideSelectionFrame(_ hidden: Bool) {
        frame?.shouldDisplay = !hidden
        if let page = frame?.page { pdfView?.annotationsChanged(on: page) }
    }

    /// Records the move or resize that just finished (bounds already applied) as one undo step.
    func commitGeometryChange(_ annotation: PDFAnnotation, from original: CGRect) {
        guard annotation.bounds != original else { return }
        let now = annotation.bounds
        undo.registerUndo(withTarget: self) { $0.setBounds(original, of: annotation, redo: now) }
        undo.setActionName("Move")
        changed(thumbnailsOnly: true)
    }

    private func setBounds(_ rect: CGRect, of annotation: PDFAnnotation, redo: CGRect) {
        annotation.bounds = rect
        undo.registerUndo(withTarget: self) { $0.setBounds(redo, of: annotation, redo: rect) }
        if selectedAnnotation === annotation { refreshSelectionFrame() } else if let page = annotation.page { pdfView?.annotationsChanged(on: page) }
        changed(thumbnailsOnly: true)
    }

    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let a = selectedAnnotation, a.isMovable, let page = a.page else { return }
        let original = a.bounds
        a.bounds = AnnotationGeometry.moved(original, by: CGSize(width: dx, height: dy), within: page.bounds(for: .cropBox))
        refreshSelectionFrame()
        commitGeometryChange(a, from: original)
    }

    /// Adds `annotation` to `page` (undo removes it) and selects it.
    func add(_ annotation: PDFAnnotation, to page: PDFPage, name: String) {
        page.addAnnotation(annotation)
        undo.registerUndo(withTarget: self) { $0.remove(annotation, name: name) }
        undo.setActionName(name)
        pdfView?.annotationsChanged(on: page)
        if annotation.isEditableByOpenText { select(annotation) }
        changed(thumbnailsOnly: true)
    }

    func remove(_ annotation: PDFAnnotation, name: String) {
        guard let page = annotation.page else { return }
        if selectedAnnotation === annotation { select(nil) }
        page.removeAnnotation(annotation)
        undo.registerUndo(withTarget: self) { $0.add(annotation, to: page, name: name) }
        undo.setActionName(name)
        pdfView?.annotationsChanged(on: page)
        changed(thumbnailsOnly: true)
    }

    func deleteSelectedAnnotation() {
        guard let a = selectedAnnotation else { return }
        remove(a, name: "Delete")
    }

    func setText(_ text: String, of box: TextBoxAnnotation) {
        let old = box.text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { remove(box, name: "Delete Text"); return }
        guard text != old else { refreshSelectionFrame(); return }
        box.text = text
        if let page = box.page {
            var b = box.bounds
            let h = box.fittingHeight(width: b.width)
            b.origin.y -= h - b.height
            b.size.height = h
            box.bounds = AnnotationGeometry.clamp(b, within: page.bounds(for: .cropBox))
        }
        undo.registerUndo(withTarget: self) { $0.setText(old, of: box) }
        undo.setActionName("Edit Text")
        refreshSelectionFrame()
        changed(thumbnailsOnly: true)
    }

    /// Centre of the visible part of the current page, in page coordinates.
    private func visibleCenter(on page: PDFPage) -> CGPoint {
        let box = page.bounds(for: .cropBox)
        guard let view = pdfView else { return CGPoint(x: box.midX, y: box.midY) }
        let visible = view.convert(view.bounds, to: page).intersection(box)
        return visible.isNull ? CGPoint(x: box.midX, y: box.midY) : CGPoint(x: visible.midX, y: visible.midY)
    }

    /// Text tool: a box in the middle of the visible page, in edit mode.
    func addTextBox() {
        guard let page = document.page(at: currentIndex) else { return }
        let c = visibleCenter(on: page)
        let rect = AnnotationGeometry.clamp(CGRect(x: c.x - 110, y: c.y - 14, width: 220, height: 28), within: page.bounds(for: .cropBox))
        let box = TextBoxAnnotation(text: "Text", bounds: rect)
        add(box, to: page, name: "Add Text")
        pdfView?.beginTextEditing(box)
    }

    func highlight() {
        guard let selection = pdfView?.currentSelection else { highlightMode.toggle(); return }
        let added = PDFPageOps.addHighlight(for: selection)
        guard !added.isEmpty else { highlightMode.toggle(); return }
        pdfView?.clearSelection()
        undo.registerUndo(withTarget: self) { m in for a in added { m.remove(a, name: "Highlight") } }
        undo.setActionName("Highlight")
        changed(thumbnailsOnly: true)
    }

    /// Called when a mouse text selection ends; in highlight mode it becomes a highlight.
    func textSelectionEnded() {
        guard highlightMode, let s = pdfView?.currentSelection, !(s.string ?? "").isEmpty else { return }
        highlight()
    }

    func sign() {
        if let png = actions.loadSignature() { place(png: png) } else { showsSignaturePad = true }
    }

    /// Places the signature in the middle of the visible page, selected so it can be dragged and resized at once.
    func place(png: Data) {
        guard let image = NSImage(data: png), let page = document.page(at: currentIndex) else { return }
        var rect = PDFPageOps.defaultStampBounds(for: image, on: page)
        let c = visibleCenter(on: page)
        rect.origin = CGPoint(x: c.x - rect.width / 2, y: c.y - rect.height / 2)
        add(ImageStampAnnotation(image: image, bounds: AnnotationGeometry.clamp(rect, within: page.bounds(for: .cropBox))),
            to: page, name: "Signature")
        showToast("Signature placed. Drag to move, corners to resize.")
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func newSignature() { showsSignaturePad = true }

    private func changed(thumbnailsOnly: Bool = false) {
        revision += 1
        thumbnails = [:]
        if !thumbnailsOnly {
            if selectedAnnotation?.page == nil { select(nil) }
            pdfView?.layoutDocumentView()
        }
        pdfView?.needsDisplay = true
        commands?.markDirty()
        actions.onChange()
    }

    // Search
    func toggleSearch() {
        showsSearch.toggle()
        if !showsSearch { query = ""; results = []; pdfView?.highlightedSelections = nil }
    }

    func runSearch() {
        guard !query.isEmpty else { results = []; pdfView?.highlightedSelections = nil; return }
        results = document.findString(query, withOptions: .caseInsensitive)
        for r in results { r.color = Brand.NSPalette.accent }
        pdfView?.highlightedSelections = results
        resultIndex = 0
        reveal()
    }

    func next() { guard !results.isEmpty else { return }; resultIndex = (resultIndex + 1) % results.count; reveal() }
    func previous() { guard !results.isEmpty else { return }; resultIndex = (resultIndex - 1 + results.count) % results.count; reveal() }
    private func reveal() {
        guard results.indices.contains(resultIndex) else { return }
        pdfView?.setCurrentSelection(results[resultIndex], animate: true)
        pdfView?.go(to: results[resultIndex])
    }

    // Zoom
    func zoomIn() { pdfView?.zoomIn(nil); refreshSelectionFrame() }
    func zoomOut() { pdfView?.zoomOut(nil); refreshSelectionFrame() }
    func fit() { pdfView?.autoScales = true; refreshSelectionFrame() }
    func actualSize() { pdfView?.autoScales = false; pdfView?.scaleFactor = 1; refreshSelectionFrame() }
}

// MARK: - PDFView wrapper

struct PDFCanvas: NSViewRepresentable {
    let model: PDFReaderModel

    func makeNSView(context: Context) -> EditablePDFView {
        let view = EditablePDFView()
        view.model = model
        view.document = model.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
        view.backgroundColor = Brand.NSPalette.well
        model.pdfView = view
        context.coordinator.observe(view, model: model)
        return view
    }

    func updateNSView(_ view: EditablePDFView, context: Context) {
        if view.document !== model.document { view.document = model.document }
        view.backgroundColor = Brand.NSPalette.well
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        nonisolated(unsafe) private var token: NSObjectProtocol?
        nonisolated(unsafe) private var scaleToken: NSObjectProtocol?
        nonisolated(unsafe) private var mouseUpMonitor: Any?
        func observe(_ view: PDFView, model: PDFReaderModel) {
            // PDFKit's page view keeps the mouse-up of a text selection; watch for it to finish a highlight.
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak view, weak model] e in
                if let view, e.window === view.window {
                    DispatchQueue.main.async { MainActor.assumeIsolated { model?.textSelectionEnded() } }
                }
                return e
            }
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.pageChanged() }
            }
            // Handles keep their on-screen size at every zoom.
            scaleToken = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.refreshSelectionFrame() }
            }
        }
        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            if let scaleToken { NotificationCenter.default.removeObserver(scaleToken) }
            if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        }
    }
}
