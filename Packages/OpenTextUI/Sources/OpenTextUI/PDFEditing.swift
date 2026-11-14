import AppKit
import PDFKit
import OpenTextDesign

// MARK: - Geometry (pure, unit-tested)

/// Move / resize maths for annotations, in page coordinates. Keeps annotations inside the page.
public enum AnnotationGeometry {
    public enum Handle: CaseIterable, Sendable { case bottomLeft, bottomRight, topLeft, topRight }

    /// Smallest size an annotation can be resized to, in points.
    public static let minimumSide: CGFloat = 12

    /// `rect` moved by `delta`, then pushed back inside `page`.
    public static func moved(_ rect: CGRect, by delta: CGSize, within page: CGRect) -> CGRect {
        clamp(rect.offsetBy(dx: delta.width, dy: delta.height), within: page)
    }

    /// Shifts `rect` (never resizes it, unless it is bigger than the page) so it lies inside `page`.
    public static func clamp(_ rect: CGRect, within page: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(r.width, page.width)
        r.size.height = min(r.height, page.height)
        r.origin.x = min(max(r.minX, page.minX), page.maxX - r.width)
        r.origin.y = min(max(r.minY, page.minY), page.maxY - r.height)
        return r
    }

    /// `rect` resized by dragging `handle` to `point`; the opposite corner stays put. With `keepAspect` the
    /// original width:height ratio is kept (the larger change wins). The result stays inside `page`.
    public static func resized(_ rect: CGRect, handle: Handle, to point: CGPoint, keepAspect: Bool, within page: CGRect) -> CGRect {
        let p = CGPoint(x: min(max(point.x, page.minX), page.maxX), y: min(max(point.y, page.minY), page.maxY))
        let anchor: CGPoint
        switch handle {
        case .bottomLeft: anchor = CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomRight: anchor = CGPoint(x: rect.minX, y: rect.maxY)
        case .topLeft: anchor = CGPoint(x: rect.maxX, y: rect.minY)
        case .topRight: anchor = CGPoint(x: rect.minX, y: rect.minY)
        }
        let signX: CGFloat = (handle == .bottomRight || handle == .topRight) ? 1 : -1
        let signY: CGFloat = (handle == .topLeft || handle == .topRight) ? 1 : -1
        var w = max(minimumSide, (p.x - anchor.x) * signX)
        var h = max(minimumSide, (p.y - anchor.y) * signY)
        if keepAspect, rect.width > 0, rect.height > 0 {
            let ratio = rect.width / rect.height
            if w / ratio > h { h = w / ratio } else { w = h * ratio }
            // Keep inside the page on the growing sides.
            let maxW = signX > 0 ? page.maxX - anchor.x : anchor.x - page.minX
            let maxH = signY > 0 ? page.maxY - anchor.y : anchor.y - page.minY
            let scale = min(1, maxW / w, maxH / h)
            w *= scale; h *= scale
        }
        let x = signX > 0 ? anchor.x : anchor.x - w
        let y = signY > 0 ? anchor.y : anchor.y - h
        return clamp(CGRect(x: x, y: y, width: w, height: h), within: page)
    }

    /// The handle under `point` (page coordinates) for a selection around `rect`; `tolerance` in page points.
    public static func handle(at point: CGPoint, for rect: CGRect, tolerance: CGFloat) -> Handle? {
        let corners: [(Handle, CGPoint)] = [
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)), (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)), (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
        return corners.first { abs($0.1.x - point.x) <= tolerance && abs($0.1.y - point.y) <= tolerance }?.0
    }
}

// MARK: - Annotations the app draws itself

/// Text box placed by the app. Drawn by OpenText and burned into the page on save, so every viewer shows it.
public final class TextBoxAnnotation: PDFAnnotation {
    public static let defaultFontSize: CGFloat = 14
    public var text: String { didSet { contents = text } }
    public var fontSize: CGFloat

    public init(text: String, bounds: CGRect, fontSize: CGFloat = TextBoxAnnotation.defaultFontSize) {
        self.text = text
        self.fontSize = fontSize
        super.init(bounds: bounds, forType: .freeText, withProperties: nil)
        contents = text
        color = .clear
    }

    public required init?(coder: NSCoder) { nil }      // never archived; decoding yields nothing instead of crashing

    var attributed: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        // Ink is fixed dark on paper: a PDF page is white in light and dark mode.
        // No ligatures: a joined "ff" glyph from the variable font reads back as "!" when the PDF's text is
        // copied or searched, so every letter is drawn as itself.
        return NSAttributedString(string: text, attributes: [
            .font: Brand.Fonts.nsBody(fontSize), .foregroundColor: NSColor(white: 0.11, alpha: 1), .paragraphStyle: style,
            .ligature: 0,
        ])
    }

    /// Height needed for the current text at the box's width.
    func fittingHeight(width: CGFloat) -> CGFloat {
        let r = attributed.boundingRect(with: CGSize(width: max(width - 8, 1), height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(r.height) + 8
    }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        Self.drawText(attributed, in: bounds, context: context)
    }

    static func drawText(_ text: NSAttributedString, in rect: CGRect, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(with: rect.insetBy(dx: 4, dy: 4), options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The selection frame around the annotation being edited: a primary-coloured edge and four corner handles.
/// Never saved (removed before writing).
final class SelectionFrameAnnotation: PDFAnnotation {
    var handleSize: CGFloat = 8
    var showsHandles = true

    init(around rect: CGRect) { super.init(bounds: rect, forType: .square, withProperties: nil) }
    required init?(coder: NSCoder) { nil }      // never archived; decoding yields nothing instead of crashing

    func frame(around rect: CGRect) {
        let pad = handleSize
        bounds = rect.insetBy(dx: -pad, dy: -pad)
    }

    var target: CGRect { bounds.insetBy(dx: handleSize, dy: handleSize) }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let r = target
        context.saveGState()
        context.setStrokeColor(Brand.NSPalette.primaryText.cgColor)
        context.setLineWidth(max(handleSize / 6, 0.75))
        context.stroke(r)
        if showsHandles {
            let s = handleSize
            for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                let h = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: h)
                context.strokeEllipse(in: h)
            }
        }
        context.restoreGState()
    }
}

extension PDFAnnotation {
    /// Annotations the Select tool can pick: the app's own (signature, text box) and common markup in the file.
    var isEditableByOpenText: Bool {
        if self is SelectionFrameAnnotation { return false }
        if self is ImageStampAnnotation || self is TextBoxAnnotation { return true }
        switch type.map({ PDFAnnotationSubtype(rawValue: $0) }) {
        case .highlight?, .ink?, .square?, .circle?, .line?, .freeText?, .stamp?, .underline?, .strikeOut?: return true
        default: return false
        }
    }

    /// Movable and resizable (highlights follow their text and can only be deleted).
    var isMovable: Bool {
        guard let t = type.map({ PDFAnnotationSubtype(rawValue: $0) }) else { return false }
        return ![.highlight, .underline, .strikeOut].contains(t)
    }

    var keepsAspect: Bool { self is ImageStampAnnotation }
}

// MARK: - PDFView with the Select tool

/// PDFView that lets the user select, move, resize, nudge and delete annotations, and edit text boxes.
/// All changes go through `PDFReaderModel`, which records undo.
final class EditablePDFView: PDFView {
    weak var model: PDFReaderModel?
    private enum Drag { case move(start: CGPoint, original: CGRect), resize(AnnotationGeometry.Handle, original: CGRect) }
    private var drag: Drag?
    private var editor: NSTextField?

    override var acceptsFirstResponder: Bool { true }

    /// Point in page space and the page under a window-space event.
    func pagePoint(for event: NSEvent) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    var handleTolerance: CGFloat { 9 / max(scaleFactor, 0.1) }

    /// PDFKit's inner page view takes every click for text selection and never passes it up. Claim the click
    /// here when it lands on an editable annotation or a handle, or while something is selected (a click
    /// elsewhere then deselects); everything else (text selection, links) stays with PDFKit.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // Only clicks and drags; scrolling, magnify and hover keep PDFKit's own handling.
        let clicks: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        guard let type = NSApp.currentEvent?.type, clicks.contains(type),
              bounds.contains(local), let model else { return super.hitTest(point) }
        if let editor, editor.frame.contains(local) { return super.hitTest(point) }
        if editor != nil || model.selectedAnnotation != nil { return self }
        guard let page = page(for: local, nearest: false) else { return super.hitTest(point) }
        let p = convert(local, to: page)
        let over = page.annotations.contains { $0.isEditableByOpenText && $0.bounds.insetBy(dx: -2, dy: -2).contains(p) }
        return over ? self : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        endTextEditing(commit: true)
        guard let model, let (page, point) = pagePoint(for: event) else { return super.mouseDown(with: event) }
        if let selected = model.selectedAnnotation, selected.page === page, selected.isMovable,
           let handle = AnnotationGeometry.handle(at: point, for: selected.bounds, tolerance: handleTolerance) {
            drag = .resize(handle, original: selected.bounds)
            return
        }
        if let hit = page.annotations.reversed().first(where: { $0.isEditableByOpenText && $0.bounds.insetBy(dx: -2, dy: -2).contains(point) }) {
            model.select(hit)
            if event.clickCount == 2, let box = hit as? TextBoxAnnotation { beginTextEditing(box); return }
            if hit.isMovable { drag = .move(start: point, original: hit.bounds); NSCursor.closedHand.set() }
            return
        }
        // A click on empty page while something was selected only deselects (the next click selects text).
        model.select(nil)
        drag = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let model, let annotation = model.selectedAnnotation, let page = annotation.page,
              let (_, point) = pagePoint(for: event) else { return }
        let box = page.bounds(for: .cropBox)
        switch drag {
        case let .move(start, original):
            annotation.bounds = AnnotationGeometry.moved(original, by: CGSize(width: point.x - start.x, height: point.y - start.y), within: box)
        case let .resize(handle, original):
            let keep = annotation.keepsAspect != event.modifierFlags.contains(.shift)
            annotation.bounds = AnnotationGeometry.resized(original, handle: handle, to: point, keepAspect: keep, within: box)
        }
        model.refreshSelectionFrame()
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; NSCursor.arrow.set() }
        guard let drag, let model, let annotation = model.selectedAnnotation else { return }
        switch drag {
        case let .move(_, original), let .resize(_, original):
            model.commitGeometryChange(annotation, from: original)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let model, let (page, point) = pagePoint(for: event) else { return }
        if let s = model.selectedAnnotation, s.page === page, s.isMovable,
           AnnotationGeometry.handle(at: point, for: s.bounds, tolerance: handleTolerance) != nil {
            NSCursor.crosshair.set()
        } else if page.annotations.contains(where: { $0.isEditableByOpenText && $0.isMovable && $0.bounds.contains(point) }) {
            NSCursor.openHand.set()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let model, model.selectedAnnotation != nil else { return super.keyDown(with: event) }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117: model.deleteSelectedAnnotation()                      // Delete, Forward Delete
        case 53: model.select(nil)                                          // Escape
        case 123: model.nudge(dx: -step, dy: 0)
        case 124: model.nudge(dx: step, dy: 0)
        case 125: model.nudge(dx: 0, dy: -step)
        case 126: model.nudge(dx: 0, dy: step)
        case 36, 76: if let box = model.selectedAnnotation as? TextBoxAnnotation { beginTextEditing(box) } else { super.keyDown(with: event) }
        default: super.keyDown(with: event)
        }
    }

    // MARK: Text box editing

    func beginTextEditing(_ box: TextBoxAnnotation) {
        guard let page = box.page else { return }
        endTextEditing(commit: true)
        model?.hideSelectionFrame(true)
        let rect = convert(box.bounds, from: page)
        let field = NSTextField(frame: rect.insetBy(dx: -2, dy: -2))
        field.stringValue = box.text
        field.font = Brand.Fonts.nsBody(box.fontSize * scaleFactor)
        field.isBordered = true
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = .white
        field.textColor = NSColor(white: 0.11, alpha: 1)
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.target = self
        field.action = #selector(commitEditor)
        field.setAccessibilityLabel("Text box")
        addSubview(field)
        editor = field
        model?.editingBox = box
        box.shouldDisplay = false
        annotationsChanged(on: page)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @objc private func commitEditor() { endTextEditing(commit: true) }

    override func cancelOperation(_ sender: Any?) {
        if editor != nil { endTextEditing(commit: false) } else { super.cancelOperation(sender) }
    }

    func endTextEditing(commit: Bool) {
        guard let field = editor, let box = model?.editingBox else { return }
        editor = nil
        model?.editingBox = nil
        let text = field.stringValue
        field.removeFromSuperview()
        box.shouldDisplay = true
        model?.hideSelectionFrame(false)
        if commit { model?.setText(text, of: box) } else if let page = box.page { annotationsChanged(on: page) }
        window?.makeFirstResponder(self)
    }

    var isEditingText: Bool { editor != nil }
}
