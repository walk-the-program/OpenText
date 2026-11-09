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

/// State of one document window: what is on screen, dirty tracking, save, format switch, convert, lock.
/// A document opened from an .otlock lives only in memory; Save re-locks it over the same file.
@MainActor
final class DocumentSession: ObservableObject {
    enum Content: Equatable { case loading, text(markdown: Bool), pdf, image, locked, failed(String) }
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
    @Published var text = ""
    @Published private(set) var isSaved = true
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var image: NSImage?
    @Published var lockedMessage: String?
    @Published var sheet: Sheet?
    @Published private(set) var memoryName: String?
    /// Editor is frozen while a format switch runs.
    @Published private(set) var isFrozen = false
    /// Non-nil while PBKDF2 / re-locking runs off the main thread.
    @Published private(set) var workLabel: String?

    let commands = DocumentCommands()
    private var latestImage: NSImage?
    private var loadingText = false
    private var autosave: Task<Void, Never>?
    private var recordedMTime: Date?
    private var textEncoding: String.Encoding = .utf8
    private var sessionPassword: String?
    private var pendingNotice: Notice?
    private let engine = ConversionEngine()

    init(url: URL) {
        self.url = url
        load()
    }

    var inMemory: Bool { memoryName != nil }
    private var effectiveName: URL { URL(fileURLWithPath: memoryName ?? url.lastPathComponent) }
    var title: String { effectiveName.lastPathComponent }
    var format: String { DocFormat.canonicalExtension(effectiveName.pathExtension) }
    var canSave: Bool {
        switch content { case .text, .pdf, .image: return workLabel == nil; default: return false }
    }

    /// Anything the user would lose by closing now.
    var hasUnsavedChanges: Bool {
        switch content {
        case .text: return !isSaved
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

    func load() {
        autosave?.cancel()
        memoryName = nil; sessionPassword = nil
        pdf = nil; image = nil; latestImage = nil
        recordedMTime = Self.mtime(url)
        switch FileRouting.kind(for: url) {
        case .locked: content = .locked
        case .pdf:
            if let d = PDFDocument(url: url) { pdf = d; content = .pdf } else { content = .failed("This PDF can't be read.") }
        case .image:
            if let i = NSImage(contentsOf: url) { image = i; latestImage = i; content = .image } else { content = .failed("This image can't be read.") }
        case .text, .markdown:
            guard let data = try? Data(contentsOf: url), let (s, enc) = TextCoding.decode(data) else {
                content = .failed("This file can't be read."); return
            }
            textEncoding = enc
            setText(s)
            content = .text(markdown: FileRouting.kind(for: url) == .markdown)
        case .unsupported: content = .failed("OpenText can't open this kind of file.")
        }
        settled()
    }

    private func present(_ u: LockFlow.Unlocked) {
        memoryName = u.originalName
        sessionPassword = u.password
        pdf = nil; image = nil; latestImage = nil
        recordedMTime = Self.mtime(url)
        let name = URL(fileURLWithPath: u.originalName)
        switch FileRouting.kind(for: name) {
        case .pdf:
            if let d = PDFDocument(data: u.data) { pdf = d; content = .pdf } else { content = .failed("This PDF can't be read.") }
        case .image:
            if let i = NSImage(data: u.data) { image = i; latestImage = i; content = .image } else { content = .failed("This image can't be read.") }
        case .text, .markdown:
            guard let (s, enc) = TextCoding.decode(u.data) else { content = .failed("This file can't be read."); return }
            textEncoding = enc
            setText(s)
            content = .text(markdown: FileRouting.kind(for: name) == .markdown)
        default: content = .failed("OpenText can't open the unlocked file.")
        }
        settled()
        if let w = u.warning { sheet = .result(Notice(title: "Touch ID", message: w)) }
    }

    private func setText(_ s: String) {
        loadingText = true
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
        guard !loadingText, !isFrozen else { return }
        isSaved = false
        guard !inMemory else { return }
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            _ = await self?.save()
        }
    }
    func imageChanged(_ i: NSImage) { latestImage = i }

    private func markSavedNow() {
        isSaved = true
        commands.markSaved()
        recordedMTime = Self.mtime(url)
    }

    private func fail(_ title: String, _ error: Error) {
        sheet = .result(Notice(title: title, message: error.localizedDescription))
    }

    /// Returns true when the bytes are safely on disk. Refuses to overwrite a file that changed outside OpenText
    /// unless `force` (the "Keep Mine" choice).
    @discardableResult
    func save(force: Bool = false) async -> Bool {
        autosave?.cancel()
        guard canSave, !isFrozen else { return false }
        if !force && FileChangeCheck.hasChanged(recorded: recordedMTime, current: Self.mtime(url)) {
            sheet = .changedOutside
            return false
        }
        do {
            if inMemory { return try await saveBack() }
            switch content {
            case .text:
                let (data, enc) = TextCoding.encode(text, as: textEncoding)
                textEncoding = enc
                try data.write(to: url, options: .atomic)
            case .pdf:
                guard let pdf else { return false }
                PDFPageOps.flattenStamps(in: pdf)
                guard let data = pdf.dataRepresentation() else { throw OpenTextError.writeFailed(url) }
                try data.write(to: url, options: .atomic)
            case .image:
                guard let img = latestImage else { return false }
                guard let data = Self.encode(img, ext: format) else {
                    throw ToolError("OpenText can't save \(format) images. Use Convert to make a png or jpg.")
                }
                try data.write(to: url, options: .atomic)
            default: return false
            }
            markSavedNow()
            return true
        } catch {
            fail("Could not save", error)
            return false
        }
    }

    /// Current document bytes for re-locking.
    private func currentData() -> Data? {
        switch content {
        case .text:
            let (d, enc) = TextCoding.encode(text, as: textEncoding)
            textEncoding = enc
            return d
        case .pdf:
            guard let pdf else { return nil }
            PDFPageOps.flattenStamps(in: pdf)
            return pdf.dataRepresentation()
        case .image:
            guard let img = latestImage else { return nil }
            return Self.encode(img, ext: format)
        default: return nil
        }
    }

    private func saveBack() async throws -> Bool {
        guard let name = memoryName else { return false }
        guard let password = sessionPassword else { sheet = .relock; return false }   // unlocked by recovery key: ask for a new password
        switch try LockFlow.checkRecovery(model: .shared) {
        case .mismatch(_, _):
            presentMismatch(resume: .save)
            return false
        default: break
        }
        guard let data = currentData() else { throw ToolError("This document can't be saved in its original format.") }
        workLabel = "Locking…"
        defer { workLabel = nil }
        let warning = try await LockFlow.saveBack(data: data, name: name, to: url, password: password, model: .shared)
        markSavedNow()
        if let warning { sheet = .result(Notice(title: "Touch ID", message: warning)) }
        return true
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

    // MARK: window close

    func saveBeforeClosing() async -> Bool { await save() }

    static func encode(_ image: NSImage, ext: String) -> Data? {
        let type: UTType
        switch ext {
        case "png": type = .png
        case "jpg": type = .jpeg
        case "tiff": type = .tiff
        case "gif": type = .gif
        case "heic": type = .heic
        default: return nil   // webp: ImageIO cannot write it
        }
        guard let cg = ImageOps.cgImage(from: image) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = type == .jpeg || type == .heic ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
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
            do { present(try await LockFlow.decrypt(file, method: method, model: model)) }
            catch { lockedMessage = error.localizedDescription }
        }
    }
}
