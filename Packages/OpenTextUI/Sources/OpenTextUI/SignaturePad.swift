import SwiftUI
import AppKit
import OpenTextDesign

/// Sheet: draw a signature with the trackpad or mouse. `onDone` receives a transparent PNG.
public struct SignaturePad: View {
    public var onDone: (Data) -> Void
    public var onCancel: () -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var size: CGSize = CGSize(width: 440, height: 180)

    public init(onDone: @escaping (Data) -> Void = { _ in }, onCancel: @escaping () -> Void = {}) {
        self.onDone = onDone
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            Text("Draw your signature").brandHeading(20)
            Text("Use the trackpad or mouse. It is saved on this Mac and reused next time.").brandBody().foregroundStyle(Brand.Palette.muted)
            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, _ in
                        for stroke in strokes where stroke.count > 1 {
                            var p = Path(); p.addLines(stroke)
                            ctx.stroke(p, with: .color(Brand.Palette.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        }
                    }
                    if strokes.isEmpty {
                        Text("Sign here").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
                    }
                    Rectangle().fill(Brand.Palette.line).frame(height: 1).padding(.horizontal, 20).offset(y: 44)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if v.translation == .zero { strokes.append([v.location]) }
                        else if !strokes.isEmpty { strokes[strokes.count - 1].append(v.location) }
                    })
                .onAppear { size = geo.size }
                .onChange(of: geo.size) { _, new in size = new }
            }
            .frame(height: 180)
            .recessedSurface(radius: Brand.Radius.lg)
            HStack {
                Button("Clear") { strokes = [] }.buttonStyle(.secondaryAction).disabled(strokes.isEmpty)
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.secondaryAction).keyboardShortcut(.cancelAction)
                Button("Use Signature") { if let png = Self.png(strokes: strokes, size: size) { onDone(png) } }
                    .buttonStyle(.primaryAction).keyboardShortcut(.defaultAction).disabled(strokes.isEmpty)
            }
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 488)
        .background(Brand.Palette.surface)
    }

    /// Renders strokes (view coordinates, top-left origin) to a tight-cropped transparent PNG in ink-black.
    nonisolated public static func png(strokes: [[CGPoint]], size: CGSize) -> Data? {
        let points = strokes.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let pad: CGFloat = 6, scale: CGFloat = 2
        let w = max(maxX - minX, 1) + pad * 2, h = max(maxY - minY, 1) + pad * 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        var ink = CGColor(gray: 0, alpha: 1)
        // Signature ink is the light-mode ink token whatever the current theme.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { ink = Brand.NSPalette.ink.cgColor }
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(2.4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for stroke in strokes where stroke.count > 0 {
            let mapped = stroke.map { CGPoint(x: $0.x - minX + pad, y: h - ($0.y - minY + pad)) }
            if mapped.count == 1 { ctx.fillEllipse(in: CGRect(x: mapped[0].x - 1.2, y: mapped[0].y - 1.2, width: 2.4, height: 2.4)); continue }
            ctx.addLines(between: mapped); ctx.strokePath()
        }
        return rep.representation(using: .png, properties: [:])
    }
}
