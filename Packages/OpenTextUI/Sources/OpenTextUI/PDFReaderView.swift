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
    /// The document changed (pages moved/deleted/inserted/rotated, highlight or signature added). Mark dirty / autosave.
    public var onChange: () -> Void

    public init(onConvert: @escaping () -> Void = {},
                loadSignature: @escaping () -> Data? = { nil },
                saveSignature: @escaping (Data) -> Void = { _ in },
                onChange: @escaping () -> Void = {}) {
        self.onConvert = onConvert
        self.loadSignature = loadSignature
        self.saveSignature = saveSignature
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
        _model = State(initialValue: m)
    }

    /// In-view shortcut, dropped when the app menu owns it.
    private func key(_ s: KeyboardShortcut) -> KeyboardShortcut? { commands == nil ? s : nil }

    private func registerCommands() {
        commands?.register(kind: .pdf, handlers: [
            .find: { if !model.showsSearch { model.toggleSearch() }; searchFocused = true },
            .toggleThumbnails: { model.showsSidebar.toggle() },
            .zoomIn: { model.zoomIn() }, .zoomOut: { model.zoomOut() }, .actualSize: { model.actualSize() },
            .rotate: { model.rotate(actions) }, .highlight: { model.highlight(actions) }, .sign: { model.sign(actions) },
        ])
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolbarRow(header: header) {
                ToolButton(title: "Highlight", shortcut: .init("h", modifiers: [.command, .shift])) { model.highlight(actions) }
                ToolButton(title: "Sign", shortcut: .init("s", modifiers: [.control, .command])) { model.sign(actions) }
                ToolButton(title: "Rotate", shortcut: key(.init("r", modifiers: .command))) { model.rotate(actions) }
                ToolButton(title: "Search", shortcut: key(.init("f", modifiers: .command)), isActive: model.showsSearch) { model.toggleSearch() }
                zoomMenu
            } trailing: {
                Button("Convert", action: actions.onConvert)
                    .buttonStyle(.primaryAction).keyboardShortcut("e", modifiers: [.command, .shift])
            }
            if model.showsSearch { searchBar }
            HStack(spacing: 0) {
                if model.showsSidebar { sidebar }
                Group {
                    if offscreenStill { PageStill(model: model) } else { PDFCanvas(model: model) }
                }
                .background(Brand.Palette.canvas)
            }
            StatusBar { Text(model.statusText) }
        }
        .background(Brand.Palette.canvas)
        .onAppear { registerCommands() }
        .onDisappear { commands?.unregister() }
        .sheet(isPresented: $model.showsSignaturePad) {
            SignaturePad(onDone: { png in model.showsSignaturePad = false; actions.saveSignature(png); model.place(png: png, actions) },
                         onCancel: { model.showsSignaturePad = false })
        }
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
        .padding(.horizontal, 14).frame(height: 40)
        .background(Brand.Palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.Palette.line).frame(height: 1) }
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
                                model.move(from: from, to: index, actions); return true
                            }
                            .dropDestination(for: URL.self) { urls, _ in model.insertFiles(urls, at: index + 1, actions) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(12)
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .top)
        .recessedSurface(radius: Brand.Radius.lg, fill: Brand.Palette.secTint)
        .dropDestination(for: URL.self) { urls, _ in model.insertFiles(urls, at: model.pageCount, actions) }
        .padding(10)
        .focusable()
        .focused($sidebarFocused)
        .focusEffectDisabled()
        .onDeleteCommand { model.deleteSelected(actions) }
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
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 860)
                .overlay(Rectangle().stroke(Brand.Palette.tileLine, lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct ThumbnailCell: View {
    let model: PDFReaderModel
    let index: Int
    var body: some View {
        let selected = index == model.currentIndex
        VStack(spacing: 4) {
            Group {
                if let image = model.thumbnail(index) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Brand.Palette.surface
                }
            }
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(Brand.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm)
                .stroke(selected ? Brand.Palette.ink : Brand.Palette.tileLine, lineWidth: selected ? 2 : 1))
            Text("\(index + 1)").font(Brand.Fonts.body(11, weight: .semibold))
                .foregroundStyle(selected ? Brand.Palette.ink : Brand.Palette.abMuted)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.go(to: index) }
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
    weak var pdfView: PDFView?
    var currentIndex = 0
    var revision = 0                 // bumps when pages change; thumbnails and counts refresh
    var showsSearch = false
    var showsSidebar = true
    @ObservationIgnored var commands: DocumentCommands?
    var showsSignaturePad = false
    var query = ""
    var results: [PDFSelection] = []
    var resultIndex = 0
    private var thumbnails: [ObjectIdentifier: NSImage] = [:]

    init(document: PDFDocument) { self.document = document }

    var pageCount: Int { _ = revision; return document.pageCount }
    var statusText: String { "Page \(min(currentIndex + 1, max(pageCount, 1))) of \(pageCount)" }
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
        pdfView?.go(to: page)
    }

    func pageChanged() {
        if let page = pdfView?.currentPage { currentIndex = document.index(for: page) }
    }

    // Page operations
    func move(from: Int, to: Int, _ actions: PDFReaderActions) {
        if PDFPageOps.move(in: document, from: from, to: to) { currentIndex = to; changed(actions) }
    }

    func deleteSelected(_ actions: PDFReaderActions) {
        guard PDFPageOps.delete(in: document, at: [currentIndex]) > 0 else { return }
        currentIndex = min(currentIndex, document.pageCount - 1)
        changed(actions)
        go(to: currentIndex)
    }

    @discardableResult func insertFiles(_ urls: [URL], at index: Int, _ actions: PDFReaderActions) -> Bool {
        var position = index, any = false
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            guard let other = PDFDocument(url: url) else { continue }
            position += PDFPageOps.insert(other, into: document, at: position)
            any = true
        }
        if any { changed(actions) }
        return any
    }

    func rotate(_ actions: PDFReaderActions) {
        PDFPageOps.rotate(in: document, pageAt: currentIndex)
        changed(actions)
    }

    func highlight(_ actions: PDFReaderActions) {
        guard let selection = pdfView?.currentSelection, !PDFPageOps.addHighlight(for: selection).isEmpty else { return }
        pdfView?.clearSelection()
        changed(actions)
    }

    func sign(_ actions: PDFReaderActions) {
        if let png = actions.loadSignature() { place(png: png, actions) } else { showsSignaturePad = true }
    }

    func place(png: Data, _ actions: PDFReaderActions) {
        guard let image = NSImage(data: png), let page = document.page(at: currentIndex) else { return }
        PDFPageOps.stampImage(image, on: page, bounds: PDFPageOps.defaultStampBounds(for: image, on: page))
        changed(actions)
    }

    private func changed(_ actions: PDFReaderActions) {
        revision += 1
        thumbnails = [:]
        pdfView?.layoutDocumentView()
        pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
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
    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func fit() { pdfView?.autoScales = true }
    func actualSize() { pdfView?.autoScales = false; pdfView?.scaleFactor = 1 }
}

// MARK: - PDFView wrapper

struct PDFCanvas: NSViewRepresentable {
    let model: PDFReaderModel

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = model.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
        view.backgroundColor = Brand.NSPalette.canvas
        model.pdfView = view
        context.coordinator.observe(view, model: model)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== model.document { view.document = model.document }
        view.backgroundColor = Brand.NSPalette.canvas
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        nonisolated(unsafe) private var token: NSObjectProtocol?
        func observe(_ view: PDFView, model: PDFReaderModel) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.pageChanged() }
            }
        }
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}
