import SwiftUI
import OpenTextDesign

public struct ImageEditorActions {
    /// Save the edited image back to its file (the app picks the encoder from the file's format).
    public var onSave: (NSImage) -> Void
    /// The one primary action. The app should save pending edits first if it needs to.
    public var onConvert: () -> Void
    /// Called after every edit with the current image.
    public var onChange: (NSImage) -> Void

    public init(onSave: @escaping (NSImage) -> Void = { _ in },
                onConvert: @escaping () -> Void = {},
                onChange: @escaping (NSImage) -> Void = { _ in }) {
        self.onSave = onSave
        self.onConvert = onConvert
        self.onChange = onChange
    }
}

public struct ImageEditorView: View {
    let actions: ImageEditorActions
    let header: DocumentHeader?
    let commands: DocumentCommands?
    @State private var canvasSize: CGSize = .zero
    @State private var image: CGImage
    @State private var display: NSImage                 // rebuilt only when `image` changes, never in body
    @State private var zoom: CGFloat = 1                // 1 = fit
    @State private var crop: CropRect?
    @State private var cropping = false
    @State private var grab: CropRect.Grab = .none
    @State private var dragStartRect: CropRect?
    @State private var resizing = false
    @State private var edited = false

    /// `commands`: when given, the app menu owns Zoom, Crop, Resize, Rotate and Flip shortcuts (they are dropped here),
    /// every edit marks `commands` dirty, and `commands.markSaved()` re-disables Save.
    public init(image: NSImage, actions: ImageEditorActions = .init(), header: DocumentHeader? = nil, commands: DocumentCommands? = nil) {
        self.commands = commands
        let cg = ImageOps.cgImage(from: image) ?? NSBitmapImageRep().cgImage ?? Self.blank
        self.actions = actions
        self.header = header
        _image = State(initialValue: cg)
        _display = State(initialValue: ImageOps.nsImage(from: cg))
    }

    private static var blank: CGImage {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func key(_ s: KeyboardShortcut) -> KeyboardShortcut? { commands == nil ? s : nil }

    private func registerCommands() {
        commands?.register(kind: .image, handlers: [
            .zoomIn: { zoom = min(zoom * 1.25, 8) }, .zoomOut: { zoom = max(zoom / 1.25, 0.25) }, .actualSize: { actualSize() },
            .crop: { toggleCrop() }, .resize: { resizing = true }, .rotate: { apply(ImageOps.rotate90(image)) },
            .flipHorizontal: { apply(ImageOps.flip(image, horizontal: true)) },
            .flipVertical: { apply(ImageOps.flip(image, horizontal: false)) },
        ], onSaved: { edited = false })
    }

    /// 100% of the image's pixels (1 image pixel = 1 point).
    private func actualSize() {
        let fit = min((canvasSize.width - 48) / CGFloat(image.width), (canvasSize.height - 48) / CGFloat(image.height))
        zoom = fit > 0 ? min(max(1 / fit, 0.05), 8) : 1
    }

    private var headerWithStatus: DocumentHeader? {
        guard var h = header else { return nil }
        h.status = "\(image.width) × \(image.height) px · \(zoom == 1 ? "Fit" : "\(Int(zoom * 100))% of fit")"
        return h
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolbarRow(header: headerWithStatus) {
                ToolButton(title: "Crop", shortcut: key(.init("k", modifiers: .command)), isActive: cropping) { toggleCrop() }
                ToolButton(title: String(format: "Resize  %d × %d", image.width, image.height), shortcut: key(.init("r", modifiers: [.option, .command]))) { resizing = true }
                ToolButton(title: "Rotate", shortcut: key(.init("r", modifiers: .command))) { apply(ImageOps.rotate90(image)) }
                flipMenu
                zoomMenu
                if cropping { cropButtons }
            } trailing: {
                Button("Save") { actions.onSave(display); edited = false }
                    .buttonStyle(.secondaryAction).keyboardShortcut("s", modifiers: .command).disabled(!edited)
                Button("Convert", action: actions.onConvert)
                    .buttonStyle(.primaryAction).keyboardShortcut("e", modifiers: [.command, .shift])
            }
            canvas
        }
        .background(Brand.Palette.canvas)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .onAppear { registerCommands() }
        .onDisappear { commands?.unregister() }
        .sheet(isPresented: $resizing) {
            ResizeSheet(width: image.width, height: image.height,
                        onApply: { w, h in resizing = false; apply(ImageOps.resize(image, width: w, height: h)) },
                        onCancel: { resizing = false })
        }
    }

    private var flipMenu: some View {
        Menu {
            Button("Flip Horizontal") { apply(ImageOps.flip(image, horizontal: true)) }.optionalShortcut(key(.init("h", modifiers: [.control, .command])))
            Button("Flip Vertical") { apply(ImageOps.flip(image, horizontal: false)) }.optionalShortcut(key(.init("v", modifiers: [.control, .command])))
        } label: { Text("Flip") }
        .menuStyle(.button).buttonStyle(.toolbarItem).menuIndicator(.hidden).fixedSize()
    }

    private var zoomMenu: some View {
        Menu {
            Button("Zoom In") { zoom = min(zoom * 1.25, 8) }.optionalShortcut(key(.init("=", modifiers: .command)))
            Button("Zoom Out") { zoom = max(zoom / 1.25, 0.25) }.optionalShortcut(key(.init("-", modifiers: .command)))
            Button("Fit") { zoom = 1 }
            Button("Actual Size") { actualSize() }.optionalShortcut(key(.init("0", modifiers: .command)))
        } label: { Text("Zoom") }
        .menuStyle(.button).buttonStyle(.toolbarItem).menuIndicator(.hidden).fixedSize()
    }

    private var cropButtons: some View {
        HStack(spacing: 4) {
            Rectangle().fill(Brand.Palette.line).frame(width: 1, height: 20).padding(.horizontal, 4)
            ToolButton(title: "Apply Crop", shortcut: .init(.return, modifiers: [])) { applyCrop() }
            ToolButton(title: "Cancel", shortcut: .init(.escape, modifiers: [])) { cropping = false; crop = nil }
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let fit = min((geo.size.width - 48) / CGFloat(image.width), (geo.size.height - 48) / CGFloat(image.height))
            let scale = max(fit, 0.01) * zoom
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    Image(nsImage: display).resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(Brand.Palette.tileLine, lineWidth: 1))
                    if cropping { cropOverlay(size: size) }
                }
                .frame(width: max(size.width + 48, geo.size.width), height: max(size.height + 48, geo.size.height))
            }
            .scrollIndicators(.automatic)
            .background(Brand.Palette.canvas)
        }
    }

    private func cropOverlay(size: CGSize) -> some View {
        let r = crop?.rect
        return ZStack(alignment: .topLeading) {
            if let r {
                let frame = CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
                Path { p in p.addRect(CGRect(origin: .zero, size: size)); p.addRect(frame) }
                    .fill(Brand.Palette.ink.opacity(0.42), style: FillStyle(eoFill: true))
                Rectangle().stroke(Brand.Palette.surface, lineWidth: 2).frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                Rectangle().stroke(Brand.Palette.ink, lineWidth: 1).frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                ForEach([CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                         CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)], id: \.x) { c in
                    Rectangle().fill(Brand.Palette.surface).overlay(Rectangle().stroke(Brand.Palette.ink, lineWidth: 1))
                        .frame(width: 10, height: 10).offset(x: c.x - 5 + (c.x == frame.maxX ? 0 : 0), y: c.y - 5)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let norm = { (p: CGPoint) in CGPoint(x: p.x / size.width, y: p.y / size.height) }
                if dragStartRect == nil {
                    let start = norm(v.startLocation)
                    dragStartRect = crop ?? CropRect(.zero)
                    grab = crop?.grab(at: start, tolerance: 12 / min(size.width, size.height)) ?? .none
                }
                let now = norm(v.location)
                switch grab {
                case let .corner(c): crop = dragStartRect?.resized(corner: c, to: now)
                case .inside: crop = dragStartRect?.moved(by: CGSize(width: v.translation.width / size.width, height: v.translation.height / size.height))
                case .none: crop = CropRect.spanning(norm(v.startLocation), now)
                }
            }
            .onEnded { _ in dragStartRect = nil; grab = .none })
    }

    // MARK: Edits

    private func toggleCrop() {
        cropping.toggle()
        crop = cropping ? CropRect(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)) : nil
    }

    private func applyCrop() {
        guard let crop else { return }
        apply(ImageOps.crop(image, to: crop.pixelRect(width: image.width, height: image.height)))
        cropping = false; self.crop = nil
    }

    private func apply(_ new: CGImage?) {
        guard let new else { return }
        let ns = ImageOps.nsImage(from: new)
        image = new
        display = ns
        edited = true
        zoom = 1
        commands?.markDirty()
        actions.onChange(ns)
    }
}

struct ResizeSheet: View {
    let width: Int, height: Int
    var onApply: (Int, Int) -> Void
    var onCancel: () -> Void
    @State private var w: Int
    @State private var h: Int
    @State private var keepAspect = true
    @State private var limited = false

    init(width: Int, height: Int, onApply: @escaping (Int, Int) -> Void, onCancel: @escaping () -> Void) {
        self.width = width; self.height = height; self.onApply = onApply; self.onCancel = onCancel
        _w = State(initialValue: width); _h = State(initialValue: height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            Text("Resize").brandHeading(Brand.Fonts.Scale.title)
            HStack(spacing: Brand.Spacing.md) {
                field("Width", value: Binding(get: { w }, set: { set(width: $0) }))
                Text("×").foregroundStyle(Brand.Palette.muted).padding(.top, 16)
                field("Height", value: Binding(get: { h }, set: { set(height: $0) }))
            }
            Toggle("Keep aspect ratio", isOn: $keepAspect).toggleStyle(.checkbox).brandBody()
            Text("Original is \(width) × \(height) px.").brandLabel()
            if limited { Text("Limited to \(ImageOps.maxSide.formatted()) px per side and \((ImageOps.maxPixels / 1_000_000).formatted()) megapixels.").brandLabel() }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.secondaryAction).keyboardShortcut(.cancelAction)
                Button("Resize") { let c = ImageOps.clampedSize(width: w, height: h); onApply(c.width, c.height) }.buttonStyle(.primaryAction(showsArrow: false)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.Spacing.xl).frame(width: 360).background(Brand.Palette.surface)
    }

    private func set(width new: Int) {
        let nw = max(1, new)
        commit(nw, keepAspect ? ImageOps.height(forWidth: nw, keepingAspectOf: (width, height)) : h)
    }

    private func set(height new: Int) {
        let nh = max(1, new)
        commit(keepAspect ? ImageOps.width(forHeight: nh, keepingAspectOf: (width, height)) : w, nh)
    }

    private func commit(_ nw: Int, _ nh: Int) {
        let c = ImageOps.clampedSize(width: nw, height: nh)
        limited = c.width != nw || c.height != nh
        w = c.width; h = c.height
    }

    private func field(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).brandLabel()
            TextField("", value: value, format: .number.grouping(.never)).brandField()
        }
    }
}
