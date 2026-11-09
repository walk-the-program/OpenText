import AppKit
import PDFKit
import UniformTypeIdentifiers
import OpenTextKit
import OpenTextUI
import OpenTextAppLogic

/// State of one document window: what is on screen, dirty tracking, save, format switch, convert, lock.
/// A document opened from an .otlock lives only in memory (`inMemory`); plaintext never touches disk.
@MainActor
final class DocumentSession: ObservableObject {
    enum Content: Equatable { case loading, text(markdown: Bool), pdf, image, locked, failed(String) }
    enum Sheet: Identifiable {
        case convert, lock, recovery(String), result(Notice)
        var id: String {
            switch self {
            case .convert: "convert"
            case .lock: "lock"
            case .recovery: "recovery"
            case .result(let n): n.id.uuidString
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
    /// Original name inside an unlocked .otlock; nil for ordinary files.
    @Published private(set) var memoryName: String?

    private var latestImage: NSImage?
    private var dirtyBinary = false
    private var loadingText = false
    private var autosave: Task<Void, Never>?
    private let engine = ConversionEngine()

    init(url: URL) {
        self.url = url
        load()
    }

    var inMemory: Bool { memoryName != nil }
    private var effectiveName: URL { URL(fileURLWithPath: memoryName ?? url.lastPathComponent) }
    var title: String { effectiveName.lastPathComponent }
    var format: String { FileRouting.canonicalExtension(effectiveName.pathExtension) }
    var canSave: Bool {
        switch content { case .text, .pdf, .image: return !inMemory; default: return false }
    }

    var targets: [String] {
        guard !inMemory, let f = DocFormat(url: url), f != .otlock else { return [] }
        return engine.targets(from: f).map(\.fileExtension)
    }

    // MARK: loading

    func load() {
        memoryName = nil
        pdf = nil; image = nil; latestImage = nil; dirtyBinary = false
        switch FileRouting.kind(for: url) {
        case .locked: content = .locked
        case .pdf:
            if let d = PDFDocument(url: url) { pdf = d; content = .pdf } else { content = .failed("This PDF can't be read.") }
        case .image:
            if let i = NSImage(contentsOf: url) { image = i; latestImage = i; content = .image } else { content = .failed("This image can't be read.") }
        case .text, .markdown:
            guard let s = Self.readText(try? Data(contentsOf: url)) else { content = .failed("This file can't be read."); return }
            setText(s)
            content = .text(markdown: FileRouting.kind(for: url) == .markdown)
        case .unsupported: content = .failed("OpenText can't open this kind of file.")
        }
    }

    private func present(data: Data, name: String) {
        memoryName = name
        pdf = nil; image = nil; latestImage = nil; dirtyBinary = false
        let u = URL(fileURLWithPath: name)
        switch FileRouting.kind(for: u) {
        case .pdf:
            if let d = PDFDocument(data: data) { pdf = d; content = .pdf } else { content = .failed("This PDF can't be read.") }
        case .image:
            if let i = NSImage(data: data) { image = i; latestImage = i; content = .image } else { content = .failed("This image can't be read.") }
        case .text, .markdown:
            guard let s = Self.readText(data) else { content = .failed("This file can't be read."); return }
            setText(s)
            content = .text(markdown: FileRouting.kind(for: u) == .markdown)
        default: content = .failed("OpenText can't open the unlocked file.")
        }
    }

    private func setText(_ s: String) {
        loadingText = true
        text = s
        isSaved = true
        DispatchQueue.main.async { self.loadingText = false }
    }

    private static func readText(_ data: Data?) -> String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: editing + saving

    func textChanged() {
        guard !loadingText else { return }
        isSaved = false
        guard !inMemory else { return }
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
    func pdfChanged() { dirtyBinary = true }
    func imageChanged(_ i: NSImage) { latestImage = i; dirtyBinary = true }

    func save() {
        autosave?.cancel()
        if inMemory {
            sheet = .result(Notice(title: "Locked file is read-only",
                                   message: "Changes to an opened locked file can't be saved back yet."))
            return
        }
        do {
            switch content {
            case .text:
                try Data(text.utf8).write(to: url, options: .atomic)
                isSaved = true
            case .pdf:
                guard let pdf else { return }
                PDFPageOps.flattenStamps(in: pdf)
                guard let data = pdf.dataRepresentation() else { throw OpenTextError.writeFailed(url) }
                try data.write(to: url, options: .atomic)
                dirtyBinary = false
            case .image:
                guard let img = latestImage else { return }
                guard let data = Self.encode(img, ext: format) else {
                    throw ToolError("OpenText can't save \(format) images. Use Convert to make a png or jpg.")
                }
                try data.write(to: url, options: .atomic)
                dirtyBinary = false
            default: break
            }
        } catch {
            sheet = .result(Notice(title: "Could not save", message: error.localizedDescription))
        }
    }

    /// Saves any pending edits before the file is converted or locked.
    private func flush() { if !inMemory && (!isSaved || dirtyBinary) { save() } }

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

    // MARK: format chip + convert

    func switchFormat(to ext: String) {
        guard let fmt = DocFormat(name: ext), !inMemory else { return }
        flush()
        let from = url, engine = self.engine
        Task {
            do {
                let new = try await Task.detached { try engine.switchFormat(from, to: fmt) }.value
                url = new
                load()
            } catch {
                sheet = .result(Notice(title: "Could not change format", message: error.localizedDescription))
            }
        }
    }

    func convert(to ext: String) {
        guard let fmt = DocFormat(name: ext) else { return }
        flush()
        let from = url, engine = self.engine
        Task {
            do {
                let out = try await Task.detached { try engine.convert(from, to: fmt) }.value
                sheet = .result(Notice(title: "Converted", message: out.map(\.lastPathComponent).joined(separator: "\n"),
                                       revealURL: out.first))
            } catch {
                sheet = .result(Notice(title: "Could not convert", message: error.localizedDescription))
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
        flush()
        sheet = .lock
    }

    func lock(password: String, confirm: String, model: AppModel) throws {
        let out = try LockFlow.lock(url, password: password, confirm: confirm, model: model)
        url = out.lockedURL
        load()
        sheet = out.recoveryKeyToShow.map { .recovery($0) }
    }

    func unlock(_ method: UnlockMethod, model: AppModel) {
        lockedMessage = nil
        if case .recoveryKey(let key) = method {
            do { url = try LockFlow.unlockRecovery(url, key: key); load() }
            catch { lockedMessage = error.localizedDescription }
            return
        }
        let file = url
        Task {
            do {
                let r = try await LockFlow.decrypt(file, method: method, model: model)
                present(data: r.data, name: r.originalName)
            } catch {
                lockedMessage = error.localizedDescription
            }
        }
    }
}
