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
    var canRevert: Bool
    var revert: () -> Void
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
                                                            saveSignature: SignatureStore.save),
                                  header: header, commands: session.commands)
                }
            case .pdfPassword:
                PDFPasswordView(fileName: session.title, errorMessage: session.pdfPasswordError) { session.unlockPDF(password: $0) }
            case .image:
                if let img = session.image {
                    ImageEditorView(image: img,
                                    actions: ImageEditorActions(onSave: { session.imageChanged($0); Task { await session.save() } },
                                                                onConvert: session.requestConvert,
                                                                onChange: session.imageChanged),
                                    header: header, commands: session.commands)
                }
            case .text(let markdown):
                TextEditorView(text: Binding(get: { session.text },
                                             set: { session.text = $0; session.textChanged() }), isMarkdown: markdown, monospace: model.settings.txtMonospace,
                               isSaved: session.isSaved,
                               actions: TextEditorActions(onConvert: session.requestConvert, onLock: session.requestLock,
                                                          onToggleMonospace: { model.update { $0.txtMonospace.toggle() } }),
                               header: header, commands: session.commands)
                    .background(ReadOnlyTextGuard(readOnly: session.isReadOnly))
            }
        }
        .disabled(session.isFrozen || session.workLabel != nil)
        .overlay {
            if let label = session.workLabel ?? (session.isFrozen ? "Changing format…" : nil) {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(label).brandBody() }
                    .padding(14).floatingSurface()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Palette.canvas)
        .frame(minWidth: 640, minHeight: 440)
        .navigationTitle(session.title)
        .background(WindowCloseGuard(session: session))
        .focusedSceneValue(\.documentCommands, session.commands)
        .focusedSceneValue(\.docActions, DocActions(canSave: session.canSave, save: { Task { await session.save() } },
                                                    convert: session.requestConvert, lock: session.requestLock,
                                                    canRevert: session.canRevert, revert: session.requestRevert))
        .sheet(item: $session.sheet) { sheet in
            switch sheet {
            case .convert:
                ConvertSheet(sourceFormat: session.format, targets: session.targets,
                             onConvert: { session.sheet = nil; session.convert(to: $0) },
                             onCancel: { session.sheet = nil })
            case .lock:
                LockSheet(title: "Lock \(session.title)",
                          explanation: "You'll need this password to open it. The original moves to the Trash.",
                          fingerprint: session.recoveryFingerprintText, confirmLabel: "Lock",
                          onSubmit: { pw, confirm in try await session.lock(password: pw, confirm: confirm, model: model) },
                          onCancel: { session.sheet = nil })
            case .relock:
                LockSheet(title: "Choose a new password",
                          explanation: "This file was opened with the recovery key. Pick a password to save your changes.",
                          fingerprint: nil, confirmLabel: "Save",
                          onSubmit: { pw, confirm in try await session.setNewPasswordAndSave(password: pw, confirm: confirm) },
                          onCancel: { session.sheet = nil })
            case .recovery(let key):
                RecoveryKeySheet(displayString: key, onDone: { session.recoveryKeyShown() })
            case .result(let n):
                NoticeCard(notice: n) { session.sheet = nil }
            case .pinMismatch(let m):
                PinMismatchSheet(info: m,
                                 onKeepOriginal: { session.resolveMismatch(m, keepOriginal: true) },
                                 onAcceptNew: { session.resolveMismatch(m, keepOriginal: false) },
                                 onCancel: { session.sheet = nil })
            case .changedOutside:
                ChangedOutsideSheet(fileName: session.title, onReload: session.reloadFromDisk, onKeepMine: session.keepMine)
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

/// Save / Don't Save / Cancel when a window with unsaved changes is closed, and the dirty dot in the close button.
struct WindowCloseGuard: NSViewRepresentable {
    let session: DocumentSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: v.window) }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        let session: DocumentSession
        weak var window: NSWindow?
        weak var original: NSWindowDelegate?
        var bypass = false
        init(session: DocumentSession) { self.session = session }

        func attach(to w: NSWindow?) {
            guard let w, w !== window else { return }
            window = w
            session.window = w
            if w.delegate !== self { original = w.delegate; w.delegate = self }
            session.commands.onDirtyChange = { [weak w] dirty in w?.isDocumentEdited = dirty }
        }

        // Forward everything else to SwiftUI's own delegate.
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            (original?.responds(to: aSelector) ?? false) ? original : super.forwardingTarget(for: aSelector)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if bypass || !session.hasUnsavedChanges { return original?.windowShouldClose?(sender) ?? true }
            Task { @MainActor in
                if await self.session.confirmClose() { self.bypass = true; sender.close() }
            }
            return false
        }

        func windowWillClose(_ notification: Notification) {
            session.unregister()
            original?.windowWillClose?(notification)
        }
    }
}

/// The text editor has no read-only switch of its own; this turns editing off in its text view for very large files.
struct ReadOnlyTextGuard: NSViewRepresentable {
    let readOnly: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        guard readOnly else { return }
        DispatchQueue.main.async {
            func walk(_ view: NSView) {
                if let tv = view as? NSTextView { tv.isEditable = false }
                view.subviews.forEach(walk)
            }
            if let root = v.window?.contentView { walk(root) }
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
