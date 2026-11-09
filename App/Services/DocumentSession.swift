import AppKit
import PDFKit
import UniformTypeIdentifiers
import OpenTextKit
import OpenTextUI
import OpenTextAppLogic

struct PinMismatch {
    var pinned: String
    var current: String
    var resume: Resume
    enum Resume { case lock, save }
}

private struct UnsafeBox<T>: @unchecked Sendable { let value: T }

/// A multi-frame GIF would be flattened to one frame by an image save.
struct AnimatedGIFError: LocalizedError {
    var errorDescription: String? { "This GIF is animated. Saving would keep only the first frame." }
}

/// State of one document window: what is on screen, dirty tracking, save, format switch, convert, lock.
/// A document opened from an .otlock lives only in memory; Save re-locks it over the same file.
@MainActor
final class DocumentSession: ObservableObject {
    enum Content: Equatable { case loading, text(markdown: Bool), richText, html, pdf, pdfPassword, image, locked, failed(String) }
    enum Sheet: Identifiable {
        case convert, lock, relock, recovery(String), result(Notice), pinMismatch(PinMismatch), changedOutside
        var id: String {
            switch self {
            case .convert: "convert"
            case .lock: "lock"
            case .relock: "relock"
            case .recovery: "recovery"
            case .result(let n): n.id.uuidString
            case .pinMismatch: "pin"
            case .changedOutside: "changed"
            }
        }
    }

    @Published private(set) var url: URL
    @Published private(set) var content: Content = .loading
    /// Not @Published: a keystroke must not re-render the window. The editor binding calls `textChanged()`;
    /// programmatic changes (`setText`) announce themselves.
    var text = ""
    @Published private(set) var isSaved = true
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var image: NSImage?
    /// Read-only content of an rtf / rtfd / docx / doc / odt file.
    @Published private(set) var rich: NSAttributedString?
    /// Decoded source of an html file, shown rendered (and locked down) by `HTMLView`.
    @Published private(set) var html: String?
    @Published var lockedMessage: String?
    @Published var sheet: Sheet?
    @Published private(set) var memoryName: String?
    /// Editor is frozen while a format switch runs.
    @Published private(set) var isFrozen = false
    /// Non-nil while PBKDF2 / re-locking runs off the main thread.
    @Published private(set) var workLabel: String?
    /// Big text files open read-only: no editing, no autosave.
    @Published private(set) var isReadOnly = false
    @Published var pdfPasswordError: String?
    private var pdfPassword: String?

    let commands = DocumentCommands()
    private var latestImage: NSImage?
    private var loadingText = false
    private var autosave: Task<Void, Never>?
    private var recordedMTime: Date?
    private var textFormat: TextFormat = .utf8
    /// Source bytes of an image unlocked from an .otlock (file-backed images read their properties from disk).
    private var imageSourceData: Data?
    private var loadToken = UUID()
    private var isSaving = false
    /// Bumped on every text edit so a finished save knows whether newer edits arrived meanwhile.
    private var revision = 0
    nonisolated private static let maxEditableText = 20_000_000
    private var sessionPassword: String?
    private var pendingNotice: Notice?
    private let engine = ConversionEngine()

    /// Every open document window's session (weak: a closed window's session drops out).
    private struct Weak { weak var session: DocumentSession? }
    private static var registry: [Weak] = []
    static var openSessions: [DocumentSession] {
        registry.removeAll { $0.session == nil }
        return registry.compactMap(\.session)
    }
    /// The window showing this session, set by the close guard.
    weak var window: NSWindow?

    init(url: URL) {
        self.url = url
        Self.registry.append(Weak(session: self))
        load()
    }

    func unregister() { Self.registry.removeAll { $0.session == nil || $0.session === self } }

    var inMemory: Bool { memoryName != nil }
    private var effectiveName: URL { URL(fileURLWithPath: memoryName ?? url.lastPathComponent) }
    var title: String { effectiveName.lastPathComponent }
    /// Which viewer the session is showing, as a stable word, for self-tests: loading, text, markdown, richText,
    /// html, pdf, pdfPassword, image, locked or failed.
    var contentKindForTesting: String {
        switch content {
        case .loading: "loading"
        case .text(let markdown): markdown ? "markdown" : "text"
        case .richText: "richText"
        case .html: "html"
        case .pdf: "pdf"
        case .pdfPassword: "pdfPassword"
        case .image: "image"
        case .locked: "locked"
        case .failed: "failed"
        }
    }
    var format: String { DocFormat.canonicalExtension(effectiveName.pathExtension) }
    var canSave: Bool {
        switch content { case .text: return workLabel == nil && !isReadOnly; case .pdf, .image: return workLabel == nil; default: return false }
    }

    /// Anything the user would lose by closing now.
    var hasUnsavedChanges: Bool {
        switch content {
        case .text: return !isSaved && !isReadOnly
        case .pdf, .image: return commands.isDirty
        default: return false
        }
    }

    var targets: [String] {
        guard !inMemory, let f = DocFormat(url: url), f != .otlock else { return [] }
        return engine.targets(from: f).map(\.fileExtension)
    }

    private static func mtime(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: loading

    private enum Loaded: @unchecked Sendable {
        case text(String, TextFormat, readOnly: Bool), pdf(PDFDocument), image(NSImage), rich(NSAttributedString), html(String), failed(String)
    }

    /// Reads and decodes the file off the main thread, then shows it.
    func load() {
        autosave?.cancel()
        memoryName = nil; sessionPassword = nil; imageSourceData = nil
        pdf = nil; image = nil; rich = nil; html = nil; latestImage = nil; isReadOnly = false
        pdfPassword = nil; pdfPasswordError = nil
        recordedMTime = Self.mtime(url)
        let file = url, kind = FileRouting.kind(for: url)
        let token = UUID()
        loadToken = token
        switch kind {
        case .locked: content = .locked; settled(); return
        case .unsupported: content = .failed("OpenText can't open this kind of file."); settled(); return
        default: break
        }
        content = .loading
        workLabel = "Opening…"
        Task {
            let result = await Task.detached { Self.read(file, kind: kind) }.value
            guard token == loadToken else { return }
            workLabel = nil
            apply(result, kind: kind)
        }
    }

    nonisolated private static func read(_ file: URL, kind: FileKind) -> Loaded {
        switch kind {
        case .pdf:
            return PDFDocument(url: file).map(Loaded.pdf) ?? .failed("This PDF can't be read.")
        case .image:
            return NSImage(contentsOf: file).map(Loaded.image) ?? .failed("This image can't be read.")
        default:
            if kind == .richText, file.pathExtension.lowercased() == "rtfd" { return readRTFD(file) }
            guard let data = try? Data(contentsOf: file) else { return .failed("This file can't be read.") }
            return parse(data, kind: kind, ext: file.pathExtension)
        }
    }

    /// .rtfd is a package (a directory), or a flat file; read by URL. Off the main thread.
    nonisolated private static func readRTFD(_ file: URL) -> Loaded {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
        let a: NSAttributedString?
        if isDir.boolValue {
            a = try? NSAttributedString(url: file, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        } else {
            a = (try? Data(contentsOf: file)).flatMap {
                try? NSAttributedString(data: $0, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
            }
        }
        return a.map(Loaded.rich) ?? .failed("This document can't be read.")
    }

    /// Word-processor files, decoded off the main thread. HTML is never given to the attributed-string HTML importer
    /// (WebKit-based, main-thread only, can fetch remote content); `HTMLView` renders it in a locked-down web view.
    nonisolated private static func parseRich(_ data: Data, ext: String) -> Loaded {
        guard let f = DocFormat(fileExtension: ext) else { return .failed("This file can't be read.") }
        if f == .html { return .html(HTMLSafety.decode(data)) }
        let type: NSAttributedString.DocumentType
        switch f {
        case .docx: type = .officeOpenXML
        case .doc: type = .docFormat
        case .odt: type = .openDocument
        default: type = .rtf
        }
        guard let a = try? NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil) else {
            return .failed("This document can't be read.")
        }
        return .rich(a)
    }

    nonisolated private static func parse(_ data: Data, kind: FileKind, ext: String = "") -> Loaded {
        switch kind {
        case .pdf: return PDFDocument(data: data).map(Loaded.pdf) ?? .failed("This PDF can't be read.")
        case .image: return NSImage(data: data).map(Loaded.image) ?? .failed("This image can't be read.")
        case .text, .markdown:
            guard let (s, f) = TextCoding.decode(data) else { return .failed("This file can't be read.") }
            return .text(s, f, readOnly: data.count > maxEditableText)
        case .richText: return parseRich(data, ext: ext)
        default: return .failed("OpenText can't open this kind of file.")
        }
    }

    private func apply(_ r: Loaded, kind: FileKind) {
        switch r {
        case .failed(let m): content = .failed(m)
        case .pdf(let d): pdf = d; content = d.isLocked ? .pdfPassword : .pdf
        case .image(let i): image = i; latestImage = i; content = .image
        case .rich(let a): rich = a; content = .richText
        case .html(let h): html = h; content = .html
        case .text(let s, let f, let readOnly):
            textFormat = f
            isReadOnly = readOnly
            setText(s)
            content = .text(markdown: kind == .markdown)
            if readOnly {
                sheet = .result(Notice(title: "Opened read-only",
                                       message: "This file is larger than 20 MB, so OpenText opens it read-only. Edits are not saved."))
            }
        }
        settled()
    }

    private func present(_ u: LockFlow.Unlocked) async {
        let name = URL(fileURLWithPath: u.originalName)
        let kind = FileRouting.kind(for: name), data = u.data
        let result = await Task.detached { Self.parse(data, kind: kind, ext: name.pathExtension) }.value
        memoryName = u.originalName
        sessionPassword = u.password
        pdf = nil; image = nil; rich = nil; html = nil; latestImage = nil
        imageSourceData = kind == .image ? data : nil
        recordedMTime = Self.mtime(url)
        apply(result, kind: kind)
        if let w = u.warning { sheet = .result(Notice(title: "Touch ID", message: w)) }
    }

    private func setText(_ s: String) {
        loadingText = true
        objectWillChange.send()
        text = s
        isSaved = true
        DispatchQueue.main.async { self.loadingText = false; self.commands.markSaved() }
    }

    /// Fresh load: nothing is dirty yet.
    private func settled() {
        isSaved = true
        DispatchQueue.main.async { self.commands.markSaved() }
    }

    // MARK: editing + saving

    func textChanged() {
        guard !loadingText, !isFrozen, !isReadOnly else { return }
        revision &+= 1
        isSaved = false
        guard !inMemory else { return }
        scheduleAutosave()
    }
    func imageChanged(_ i: NSImage) { latestImage = i }

    private func scheduleAutosave() {
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            _ = await self?.save(interactive: false)
        }
    }

    private func markSavedNow() {
        isSaved = true
        commands.markSaved()
        recordedMTime = Self.mtime(url)
    }

    private func fail(_ title: String, _ error: Error) {
        sheet = .result(Notice(title: title, message: error.localizedDescription))
    }

    /// Returns true when the bytes are safely on disk. Refuses to overwrite a file that changed outside OpenText
    /// unless `force` (the "Keep Mine" choice). Autosave passes `interactive: false`: it never asks questions
    /// (a text that no longer fits its encoding just stays unsaved) and shows no progress overlay.
    @discardableResult
    func save(force: Bool = false, interactive: Bool = true) async -> Bool {
        autosave?.cancel()
        guard canSave, !isFrozen, !isSaving else { return false }
        if !force && FileChangeCheck.hasChanged(recorded: recordedMTime, current: Self.mtime(url)) {
            sheet = .changedOutside
            return false
        }
        isSaving = true
        defer { isSaving = false }
        let startRevision = revision
        do {
            if inMemory { return try await saveBack(interactive: interactive) }
            if interactive { workLabel = "Saving…" }
            defer { if interactive { workLabel = nil } }
            guard let data = try await buildData(interactive: interactive) else { return false }
            let dest = url
            try await Task.detached { try SafeWrite.write(data, to: dest) }.value
            if case .text = content, revision != startRevision {      // typed during the write: still dirty
                recordedMTime = Self.mtime(url)
                scheduleAutosave()
            } else {
                markSavedNow()
            }
            return true
        } catch let error as AnimatedGIFError {
            refuseAnimatedGIF(error)
            return false
        } catch {
            fail("Could not save", error)
            return false
        }
    }

    /// Current document bytes in the file's own format. The heavy encoding runs off the main thread.
    /// Returns nil when nothing should be written (the user declined a change of encoding, or autosave met one).
    private func buildData(interactive: Bool) async throws -> Data? {
        switch content {
        case .text:
            let t = text, f = textFormat
            if let d = await Task.detached(operation: { TextCoding.encode(t, as: f) }).value { return d }
            guard interactive, await confirmUTF8() else { return nil }
            textFormat = .utf8
            return await Task.detached { TextCoding.encode(t, as: .utf8) }.value
        case .pdf:
            guard let pdf else { throw OpenTextError.writeFailed(url) }
            PDFPageOps.flattenStamps(in: pdf)
            let box = UnsafeBox(value: pdf)
            let pw = pdfPassword
            let options: [PDFDocumentWriteOption: Any] = pw.map { [.userPasswordOption: $0, .ownerPasswordOption: $0] } ?? [:]
            let optionBox = UnsafeBox(value: options)
            guard let data = await Task.detached(operation: { box.value.dataRepresentation(options: optionBox.value) }).value else { throw OpenTextError.writeFailed(url) }
            return data
        case .image:
            guard let img = latestImage, let cg = ImageOps.cgImage(from: img) else { throw OpenTextError.writeFailed(url) }
            let ext = format, file: URL? = inMemory ? nil : url, memory = imageSourceData
            return try await Task.detached { try Self.encodeImage(cg, ext: ext, sourceURL: file, sourceData: memory) }.value
        default:
            throw ToolError("This document can't be saved in its original format.")
        }
    }

    private func saveBack(interactive: Bool) async throws -> Bool {
        guard memoryName != nil else { return false }
        let name = memoryName!
        guard let password = sessionPassword else { sheet = .relock; return false }   // unlocked by recovery key: ask for a new password
        switch try LockFlow.checkRecovery(model: .shared) {
        case .mismatch(_, _):
            presentMismatch(resume: .save)
            return false
        default: break
        }
        let startRevision = revision
        workLabel = "Locking…"
        defer { workLabel = nil }
        guard let data = try await buildData(interactive: interactive) else { return false }
        let warning = try await LockFlow.saveBack(data: data, name: name, to: url, password: password, model: .shared)
        if case .text = content, revision != startRevision { recordedMTime = Self.mtime(url) } else { markSavedNow() }
        if let warning { sheet = .result(Notice(title: "Touch ID", message: warning)) }
        return true
    }

    // MARK: alerts

    private func runAlert(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }

    /// The text can't be written in the file's original encoding any more.
    private func confirmUTF8() async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Save as UTF-8?"
        alert.informativeText = "\(title) uses an older text encoding that can't hold some of the characters you typed. Saving as UTF-8 keeps them, but other programs that expect the old encoding may show the file differently."
        alert.addButton(withTitle: "Save as UTF-8")
        alert.addButton(withTitle: "Cancel")
        return await runAlert(alert) == .alertFirstButtonReturn
    }

    /// Offers Convert instead of flattening an animated GIF.
    private func refuseAnimatedGIF(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "OpenText can't save an animated GIF"
        alert.informativeText = "\(error.localizedDescription) Use Convert to make a copy in another format; the original stays as it is."
        alert.addButton(withTitle: "Convert…")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn { requestConvert() }
    }

    nonisolated static func encodeImage(_ cg: CGImage, ext: String, sourceURL: URL?, sourceData: Data?) throws -> Data {
        guard let type = DocFormat(fileExtension: ext)?.imageUTType else {
            throw ToolError("OpenText can't save \(ext) images. Use Convert to make a png or jpg.")   // webp: ImageIO cannot write it
        }
        var source: CGImageSource?
        if let u = sourceURL { source = CGImageSourceCreateWithURL(u as CFURL, nil) }
        else if let d = sourceData { source = CGImageSourceCreateWithData(d as CFData, nil) }
        if type == .gif, let source, CGImageSourceGetCount(source) > 1 { throw AnimatedGIFError() }
        // Carry the source's EXIF / GPS / TIFF / colour metadata over; the pixels are already upright.
        var props: [CFString: Any] = [:]
        if let source, let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] { props = p }
        for k in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth, kCGImagePropertyColorModel,
                  kCGImagePropertyHasAlpha, kCGImagePropertyIsIndexed, kCGImagePropertyIsFloat, kCGImagePropertyFileSize] {
            props[k] = nil
        }
        if props[kCGImagePropertyOrientation] != nil { props[kCGImagePropertyOrientation] = 1 }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any], tiff[kCGImagePropertyTIFFOrientation] != nil {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if exif[kCGImagePropertyExifPixelXDimension] != nil { exif[kCGImagePropertyExifPixelXDimension] = cg.width }
            if exif[kCGImagePropertyExifPixelYDimension] != nil { exif[kCGImagePropertyExifPixelYDimension] = cg.height }
            props[kCGImagePropertyExifDictionary] = exif
        }
        if type == .jpeg || type == .heic { props[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else {
            throw ToolError("This image can't be saved.")
        }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ToolError("This image can't be saved.") }
        return out as Data
    }

    /// Sets a new password for a document that was unlocked with the recovery key, then saves.
    func setNewPasswordAndSave(password: String, confirm: String) async throws {
        if let p = PasswordRules.validate(password: password, confirm: confirm) { throw LockFlow.FlowError.password(p) }
        sessionPassword = password
        sheet = nil
        await save(force: true)
    }

    private func presentMismatch(resume: PinMismatch.Resume) {
        let pinned = RecoveryPin.read().map(LockFlow.fingerprint) ?? "unknown"
        let current = AppModel.shared.settings.recoveryPublicKey.map(LockFlow.fingerprint) ?? "unknown"
        sheet = .pinMismatch(PinMismatch(pinned: pinned, current: current, resume: resume))
    }

    func resolveMismatch(_ m: PinMismatch, keepOriginal: Bool) {
        Task {
            do {
                if keepOriginal {
                    LockFlow.keepOriginalKey(model: .shared)
                } else {
                    guard try await LockFlow.acceptNewKey(model: .shared) else { return }
                }
                sheet = nil
                switch m.resume {
                case .lock: sheet = .lock
                case .save: await save()
                }
            } catch { fail("Recovery key", error) }
        }
    }

    // MARK: password-protected PDF

    func unlockPDF(password: String) {
        guard let pdf, pdf.isLocked else { return }
        if pdf.unlock(withPassword: password) {
            pdfPassword = password          // saving keeps the PDF protected with the same password
            pdfPasswordError = nil
            content = .pdf
            settled()
        } else {
            pdfPasswordError = "That password isn't right."
        }
    }

    // MARK: revert

    var canRevert: Bool { hasUnsavedChanges && workLabel == nil }

    /// File ▸ Revert to Saved: confirm, then reload from disk (an unlocked document asks for its password again).
    func requestRevert() {
        guard canRevert else { return }
        let alert = NSAlert()
        alert.messageText = "Revert to the saved version of \(title)?"
        alert.informativeText = "Your changes since the last save will be lost."
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            if r == .alertFirstButtonReturn { self?.reloadFromDisk() }
        }
        if let window, window.isVisible { alert.beginSheetModal(for: window, completionHandler: done) } else { done(alert.runModal()) }
    }

    // MARK: window close and quit

    /// Saves pending text edits now (used on quit, before deciding whether anything is still unsaved).
    func flushAutosave() async {
        guard !inMemory, !isReadOnly, case .text = content, !isSaved else { return }
        await save(interactive: false)
    }

    /// Save / Don't Save / Cancel for a document with unsaved changes. True when it is fine to close or quit.
    func confirmClose() async -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(title)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        let response: NSApplication.ModalResponse
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            response = await withCheckedContinuation { c in alert.beginSheetModal(for: window) { c.resume(returning: $0) } }
        } else {
            response = await runAlert(alert)
        }
        switch response {
        case .alertFirstButtonReturn: return await save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // MARK: changed outside

    func reloadFromDisk() { sheet = nil; if inMemory { lockedAgain() } else { load() } }
    func keepMine() { sheet = nil; Task { await save(force: true) } }
    private func lockedAgain() { memoryName = nil; sessionPassword = nil; content = .locked }

    // MARK: format chip + convert

    func switchFormat(to ext: String) {
        guard let fmt = DocFormat(name: ext), !inMemory, !isFrozen else { return }
        autosave?.cancel()
        let from = url, engine = self.engine
        Task {
            if hasUnsavedChanges, !(await save()) { return }   // a conflict or error stops the switch
            isFrozen = true                                     // no typing or autosave while the file is swapped
            defer { isFrozen = false }
            do {
                let new = try await Task.detached { try engine.switchFormat(from, to: fmt) }.value
                url = new
                load()
            } catch {
                fail("Could not change format", error)
            }
        }
    }

    func convert(to ext: String) {
        guard let fmt = DocFormat(name: ext) else { return }
        let from = url, engine = self.engine
        Task {
            if !inMemory && (hasUnsavedChanges), !(await save()) { return }
            do {
                let out = try await Task.detached { try engine.convert(from, to: fmt) }.value
                sheet = .result(Notice(title: "Converted", message: out.map(\.lastPathComponent).joined(separator: "\n"),
                                       revealURL: out.first))
            } catch {
                fail("Could not convert", error)
            }
        }
    }

    func requestConvert() {
        if inMemory {
            sheet = .result(Notice(title: "Convert needs a file", message: "Unlock this file to a normal file first."))
        } else if !targets.isEmpty {
            sheet = .convert
        } else {
            sheet = .result(Notice(title: "Nothing to convert to", message: "OpenText has no conversions for .\(format) files."))
        }
    }

    // MARK: lock

    func requestLock() {
        guard !inMemory, content != .locked, content != .loading else { return }
        Task {
            if hasUnsavedChanges, !(await save()) { return }
            do {
                if case .mismatch = try LockFlow.checkRecovery(model: .shared) { presentMismatch(resume: .lock); return }
                sheet = .lock
            } catch { fail("Recovery key", error) }
        }
    }

    /// Fingerprint line for the lock sheet.
    var recoveryFingerprintText: String {
        guard let k = AppModel.shared.settings.recoveryPublicKey else {
            return "A new recovery key will be created and shown once."
        }
        return "Recovery key fingerprint: \(LockFlow.fingerprint(k))"
    }

    func lock(password: String, confirm: String, model: AppModel) async throws {
        workLabel = "Locking…"
        defer { workLabel = nil }
        let out = try await LockFlow.lock(url, password: password, confirm: confirm, model: model)
        var lines: [String] = []
        if out.originalStillThere {
            lines.append("The locked file was created, but the original is still at \(url.path). Move it to the Trash yourself.")
        } else {
            lines.append("The original is in the Trash. Empty the Trash to remove it completely.")
        }
        lines += out.warnings
        let title = out.originalStillThere ? "Locked, original not removed" : "Locked"
        pendingNotice = Notice(title: title, message: lines.joined(separator: "\n\n"))
        if let locked = out.lockedURL { url = locked; load() }
        if let key = out.recoveryKeyToShow {
            sheet = .recovery(key)
        } else {
            sheet = .result(pendingNotice!)
            pendingNotice = nil
        }
    }

    func recoveryKeyShown() {
        sheet = pendingNotice.map { .result($0) }
        pendingNotice = nil
    }

    func unlock(_ method: UnlockMethod, model: AppModel) {
        lockedMessage = nil
        guard workLabel == nil else { return }
        workLabel = "Unlocking…"
        let file = url
        Task {
            defer { workLabel = nil }
            do { await present(try await LockFlow.decrypt(file, method: method, model: model)) }
            catch { lockedMessage = error.localizedDescription }
        }
    }
}
