import AppKit
import PDFKit
import SwiftUI
import Testing
import OpenTextDesign
@testable import OpenTextUI

/// Off-screen rendering: NSHostingView that is never put in a window, drawn with cacheDisplay.
@MainActor
enum Snap {
    static let outDir: URL = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("design/snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @discardableResult
    static func render<V: View>(_ view: V, name: String, dark: Bool, size: CGSize = CGSize(width: 1280, height: 800), trafficLights: Bool = false, center: Bool = false,
                                settle: TimeInterval = 0.6) -> NSBitmapImageRep {
        _ = NSApplication.shared
        let content = ZStack(alignment: .topLeading) {
            Brand.Palette.canvas
            if center { view.frame(maxWidth: .infinity, maxHeight: .infinity) } else { view }
            if trafficLights {
                HStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Brand.Palette.ink.opacity(0.2)).frame(width: 12, height: 12) } }
                    .padding(.leading, 14).padding(.top, 18)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.brandStaticRendering, true)
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        let end = Date().addingTimeInterval(settle)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = outDir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        return rep
    }

    /// Fraction of pixels differing from the dominant corner colour (detects blank output).
    static func inkFraction(_ rep: NSBitmapImageRep, in rect: CGRect? = nil) -> Double {
        let r = rect ?? CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        guard let base = rep.colorAt(x: Int(r.minX) + 1, y: Int(r.minY) + 1)?.usingColorSpace(.deviceRGB) else { return 0 }
        var differing = 0, total = 0
        for y in stride(from: Int(r.minY), to: Int(r.maxY), by: 3) {
            for x in stride(from: Int(r.minX), to: Int(r.maxX), by: 3) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += 1
                if abs(c.redComponent - base.redComponent) + abs(c.greenComponent - base.greenComponent) + abs(c.blueComponent - base.blueComponent) > 0.06 { differing += 1 }
            }
        }
        return total == 0 ? 0 : Double(differing) / Double(total)
    }
}

// MARK: Fixtures

enum Fixture {
    /// Paragraphs; `wrapped` breaks them to fit the 612pt page with 60pt margins.
    static let leaseParagraphs: [String] = [
        "3.1 Monthly Rent. Tenant shall pay Landlord rent of $2,400.00 per month, due on or before the first day of each month, beginning January 1, 2026, and ending with the payment due December 1, 2026.",
        "3.2 Late Charge. Rent received after the fifth (5th) day of the month carries a late charge of $75.00, plus $10.00 for each additional day until paid in full.",
        "3.3 Security Deposit. Tenant shall pay a security deposit of $2,400.00 at signing, to be held in a separate account until the Lease ends. The deposit is not a limit on Tenant's liability and may not be applied as the final month's rent.",
        "3.4 Return of Deposit. Within thirty (30) days after Tenant vacates the Premises, Landlord shall return the deposit with an itemized list of lawful deductions, no later than January 30, 2027.",
    ]

    static func wrapped(_ paragraphs: [String], width: CGFloat, fontSize: CGFloat) -> [String] {
        let font = NSFont.systemFont(ofSize: fontSize)
        func measure(_ s: String) -> CGFloat {
            CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font])), nil, nil, nil)
        }
        var lines: [String] = []
        for (i, para) in paragraphs.enumerated() {
            if i > 0 { lines.append("") }
            var current = ""
            for word in para.split(separator: " ") {
                let next = current.isEmpty ? String(word) : current + " " + word
                if measure(next) > width, !current.isEmpty { lines.append(current); current = String(word) } else { current = next }
            }
            if !current.isEmpty { lines.append(current) }
        }
        return lines
    }

    @MainActor static func leasePDF(pages: Int = 12) -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for n in 1...pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(box)
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            func draw(_ s: String, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular) {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.black]))
                ctx.textPosition = CGPoint(x: 60, y: y); CTLineDraw(line, ctx)
            }
            draw("Residential Lease Agreement", 730, 9)
            draw("\(n). Rent and Deposit", 690, 20, .semibold)
            for (i, l) in wrapped(leaseParagraphs, width: 612 - 120, fontSize: 10).enumerated() { draw(l, 650 - CGFloat(i) * 22, 10) }
            draw("Initials ______ ______ · Page \(n) of \(pages)", 40, 8)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return PDFDocument(data: data as Data)!
    }

    /// A real 4032 x 3024 bitmap (not a drawing handler), so the editor reports 4032 x 3024.
    static func photo() -> NSImage {
        let w = 4032, h = 3024
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: w, height: h)
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        Brand.NSPalette.secTint.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        Brand.NSPalette.primary.setFill(); NSBezierPath(ovalIn: NSRect(x: 2400, y: 1800, width: 800, height: 800)).fill()
        Brand.NSPalette.line.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4032, height: 900)).fill()
        Brand.NSPalette.muted.setFill(); NSBezierPath(rect: NSRect(x: 600, y: 900, width: 1100, height: 1500)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    static let markdown = """
    # Christmas 2026
    **Budget:** $1,200 · **Spent so far:** $640

    ## Mom
    - Le Creuset dutch oven — $420
    - Linen robe, sage green — $88
    - Framed print from the Portland trip — $65

    ## Dad
    - Leather work gloves — $60
    - Pour-over coffee set — $95
    - Book: *The Order of Time* — $18

    ## Sam
    - Climbing shoes, size 9 — $140
    - Concert tickets for March 14 — $110

    ## Notes
    - Order everything by December 8 so it ships before the 20th.
    - Wrap on the 22nd. Dinner at Mom's is the 25th.
    """
}

@Suite @MainActor struct SnapshotTests {
    let pdfHeader = DocumentHeader(title: "Q3-lease", format: "pdf", targets: ["md", "txt", "docx", "png", "otlock"], leadingInset: 78)

    @Test func pdfReader() {
        for dark in [false, true] {
            let doc = Fixture.leasePDF()
            if let sel = doc.findString("Tenant shall pay a security deposit", withOptions: []).first(where: { doc.index(for: $0.pages[0]) == 2 }) {
                PDFPageOps.addHighlight(for: sel)
            }
            let rep = Snap.render(PDFReaderView(document: doc, header: pdfHeader).offscreenSnapshot(startingAt: 2), name: "pdf-reader", dark: dark, trafficLights: true, settle: 1.2)
            #expect(Snap.inkFraction(rep, in: CGRect(x: 0, y: 0, width: 1280, height: 96)) > 0.01)
            #expect(Snap.inkFraction(rep, in: CGRect(x: 0, y: 60, width: 200, height: 700)) > 0.01)
        }
    }

    @Test func imageEditor() {
        for dark in [false, true] {
            let header = DocumentHeader(title: "IMG_4471", format: "heic", targets: ["jpg", "png", "pdf"], leadingInset: 78)
            Snap.render(ImageEditorView(image: Fixture.photo(), header: header), name: "image-editor", dark: dark, trafficLights: true)
        }
    }

    @Test func textEditor() {
        let header = DocumentHeader(title: "gift-ideas", format: "md", targets: ["txt", "html", "pdf", "docx"], leadingInset: 78)
        for dark in [false, true] {
            var text = Fixture.markdown
            let b = Binding(get: { text }, set: { text = $0 })
            Snap.render(TextEditorView(text: b, isMarkdown: true, header: header), name: "text-editor", dark: dark, trafficLights: true)
            Snap.render(TextEditorView(text: b, isMarkdown: true, header: header).startingFaded(), name: "text-editor-faded", dark: dark, trafficLights: true)
            Snap.render(TextEditorView(text: b, isMarkdown: true, header: header).startingInPreview(), name: "text-editor-preview", dark: dark, trafficLights: true)
            let txtHeader = DocumentHeader(title: "grocery-list", format: "txt", targets: ["md", "pdf"], leadingInset: 78)
            var plain = "milk\neggs\nsourdough\nlemons"
            let pb = Binding(get: { plain }, set: { plain = $0 })
            Snap.render(TextEditorView(text: pb, isMarkdown: false, header: txtHeader), name: "text-editor-txt", dark: dark, trafficLights: true)
        }
    }

    @Test func brandMark() {
        for dark in [false, true] {
            let rep = Snap.render(BrandMark(size: 128), name: "brand-mark", dark: dark, size: CGSize(width: 320, height: 240), center: true)
            #expect(Snap.inkFraction(rep) > 0.02)
            let t = BrandMark.templateImage(pointSize: 16), big = BrandMark.templateImage(pointSize: 64)
            Snap.render(HStack(spacing: 40) {
                Image(nsImage: t).foregroundStyle(Brand.Palette.ink)
                Image(nsImage: big).foregroundStyle(Brand.Palette.ink)
            }, name: "brand-mark-template", dark: dark, size: CGSize(width: 240, height: 120), center: true)
        }
    }

    @Test func richText() {
        let doc = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        doc.append(NSAttributedString(string: "Lease Summary\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]))
        let para = NSMutableAttributedString(string: "Rent is due on the first of each month. A late charge applies after the fifth, so pay ", attributes: [.font: body])
        para.append(NSAttributedString(string: "early", attributes: [.font: body, .foregroundColor: NSColor.systemRed]))
        para.append(NSAttributedString(string: ".\n\n", attributes: [.font: body]))
        doc.append(para)
        for item in ["Deposit: $2,400", "Term: 12 months", "Pets: none"] {
            doc.append(NSAttributedString(string: "\u{2022}  \(item)\n", attributes: [.font: body]))
        }
        // Round-trip through RTF so the sample is what the app would load from a real file.
        let rtf = try! doc.data(from: NSRange(location: 0, length: doc.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let loaded = try! NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        for dark in [false, true] {
            let header = DocumentHeader(title: "Lease Summary", format: "rtf", targets: ["txt", "md", "docx", "pdf"], leadingInset: 78)
            let rep = Snap.render(RichTextView(attributed: loaded, header: header), name: "rich-text", dark: dark, size: CGSize(width: 980, height: 560), trafficLights: true)
            #expect(Snap.inkFraction(rep) > 0.02)
        }
    }

    @Test func htmlView() {
        let html = "<html><body style='font-family:Georgia;margin:48px'><h1>Quarterly notes</h1><p>Rendered <b>HTML</b>, not source. <a href='https://example.com'>A link</a>.</p><ul><li>No network</li><li>No scripts</li></ul><img src='https://example.com/x.png' alt=''></body></html>"
        let header = DocumentHeader(title: "Notes", format: "html", targets: ["txt", "md", "pdf"], leadingInset: 78)
        let rep = Snap.render(HTMLView(html: html, header: header), name: "html-view", dark: false, size: CGSize(width: 980, height: 560), trafficLights: true, settle: 2.0)
        #expect(Snap.inkFraction(rep) > 0.0)
    }

    @Test func home() {
        let recents = ["/Users/me/Documents/Lease 2026.pdf", "/Users/me/Desktop/Notes.md", "/Users/me/Downloads/Receipt.png", "/Users/me/Projects/OpenText/README.txt"].map { URL(fileURLWithPath: $0) }
        for dark in [false, true] {
            var qc = QuickCreateState()
            let size = CGSize(width: 800, height: 520)
            let rep = Snap.render(HomeView(quickCreate: Binding(get: { qc }, set: { qc = $0 }), recents: recents, setupIncomplete: true), name: "home", dark: dark, size: size)
            #expect(Snap.inkFraction(rep) > 0.02)
            Snap.render(HomeView(quickCreate: Binding(get: { qc }, set: { qc = $0 })), name: "home-empty", dark: dark, size: size)
        }
    }

    @Test func popoversAndSheets() {
        for dark in [false, true] {
            var qc = QuickCreateState()
            Snap.render(QuickCreateView(state: Binding(get: { qc }, set: { qc = $0 })), name: "quick-create", dark: dark, center: true)
            var setup = SetupState(defaultAppsDone: true, finderExtensionOn: false, shortcut: "ctrl+opt+n", shortcutWarning: "Clashes with the speech-to-text shortcut.")
            Snap.render(SetupView(state: Binding(get: { setup }, set: { setup = $0 })), name: "setup", dark: dark, size: CGSize(width: 940, height: 500))
            Snap.render(LockedFileView(fileName: "Tracy Christmas.otlock", canUseTouchID: true, onUnlock: { _ in }), name: "locked-file", dark: dark)
            Snap.render(ConvertSheet(sourceFormat: "pdf", targets: ["png", "txt", "md"], onConvert: { _ in }).clipShape(RoundedRectangle(cornerRadius: Brand.Radius.card, style: .continuous)).floatingSurface(radius: Brand.Radius.card).padding(40), name: "convert-sheet", dark: dark, center: true)
            Snap.render(RecoveryKeySheet(displayString: "K7QM-2XD4-9HPR-ZT3W-B6NC-4YVE-JA8F-SGU5").clipShape(RoundedRectangle(cornerRadius: Brand.Radius.card, style: .continuous)).floatingSurface(radius: Brand.Radius.card), name: "recovery-key-sheet", dark: dark, center: true)
            Snap.render(SignaturePad().clipShape(RoundedRectangle(cornerRadius: Brand.Radius.card, style: .continuous)).floatingSurface(radius: Brand.Radius.card), name: "signature-pad", dark: dark, center: true)
        }
    }
}
