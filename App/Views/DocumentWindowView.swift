import SwiftUI
import PDFKit
import OpenTextDesign
import OpenTextUI
import OpenTextAppLogic

/// Menu commands reach the front document window through this focused value.
struct DocActions {
    var canSave: Bool
    var save: () -> Void
    var convert: () -> Void
    var lock: () -> Void
}
struct DocActionsKey: FocusedValueKey { typealias Value = DocActions }
extension FocusedValues {
    var docActions: DocActions? {
        get { self[DocActionsKey.self] }
        set { self[DocActionsKey.self] = newValue }
    }
}

struct DocumentWindowView: View {
    @StateObject private var session: DocumentSession
    @EnvironmentObject private var model: AppModel

    init(url: URL) { _session = StateObject(wrappedValue: DocumentSession(url: url)) }

    private var header: DocumentHeader {
        DocumentHeader(title: (session.title as NSString).deletingPathExtension, format: session.format,
                       targets: session.targets, leadingInset: 78) { session.switchFormat(to: $0) }
    }

    var body: some View {
        Group {
            switch session.content {
            case .loading:
                Color.clear
            case .failed(let message):
                Text(message).brandBody().foregroundStyle(Brand.Palette.muted)
            case .locked:
                LockedFileView(fileName: session.title, canUseTouchID: model.settings.useTouchID && BiometricKeychain.isAvailable,
                               errorMessage: session.lockedMessage) { session.unlock($0, model: model) }
            case .pdf:
                if let doc = session.pdf {
                    PDFReaderView(document: doc,
                                  actions: PDFReaderActions(onConvert: session.requestConvert,
                                                            loadSignature: SignatureStore.load,
                                                            saveSignature: SignatureStore.save,
                                                            onChange: session.pdfChanged),
                                  header: header)
                }
            case .image:
                if let img = session.image {
                    ImageEditorView(image: img,
                                    actions: ImageEditorActions(onSave: { session.imageChanged($0); session.save() },
                                                                onConvert: session.requestConvert,
                                                                onChange: session.imageChanged),
                                    header: header)
                }
            case .text(let markdown):
                TextEditorView(text: $session.text, isMarkdown: markdown, monospace: model.settings.txtMonospace,
                               isSaved: session.isSaved,
                               actions: TextEditorActions(onConvert: session.requestConvert, onLock: session.requestLock,
                                                          onToggleMonospace: { model.update { $0.txtMonospace.toggle() } }),
                               header: header)
                    .onChange(of: session.text) { _, _ in session.textChanged() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Palette.canvas)
        .frame(minWidth: 640, minHeight: 440)
        .navigationTitle(session.title)
        .focusedSceneValue(\.docActions, DocActions(canSave: session.canSave, save: session.save,
                                                    convert: session.requestConvert, lock: session.requestLock))
        .sheet(item: $session.sheet) { sheet in
            switch sheet {
            case .convert:
                ConvertSheet(sourceFormat: session.format, targets: session.targets,
                             onConvert: { session.sheet = nil; session.convert(to: $0) },
                             onCancel: { session.sheet = nil })
            case .lock:
                LockSheet(fileName: session.title,
                          onLock: { pw, confirm in try session.lock(password: pw, confirm: confirm, model: model) },
                          onCancel: { session.sheet = nil })
            case .recovery(let key):
                RecoveryKeySheet(displayString: key, onDone: { session.sheet = nil })
            case .result(let n):
                NoticeCard(notice: n) { session.sheet = nil }
            }
        }
        .onChange(of: model.lockRequest) { _, req in
            if let req, req.standardizedFileURL == session.url.standardizedFileURL {
                model.lockRequest = nil
                session.requestLock()
            }
        }
    }
}

/// The drawn signature is saved once (PNG) in Application Support and reused.
enum SignatureStore {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenText/signature.png")
    }
    static func load() -> Data? { try? Data(contentsOf: fileURL) }
    static func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
