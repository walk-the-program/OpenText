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
extension DocActions {
    /// The menu's view of one document session.
    @MainActor init(session: DocumentSession, model: AppModel) {
        self.init(canSave: session.canSave, save: { Task { await session.save() } },
                  convert: session.requestConvert, lock: session.requestLock,
                  canRevert: session.canRevert, revert: session.requestRevert)
    }
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

    /// Called with the new location after a rename, so the scene's URL value follows the file.
    private let onRenamed: (URL) -> Void

    init(url: URL, onRenamed: @escaping (URL) -> Void = { _ in }) {
        _session = StateObject(wrappedValue: DocumentSession(url: url))
        self.onRenamed = onRenamed
    }

    private var header: DocumentHeader {
        var h = DocumentHeader(title: (session.title as NSString).deletingPathExtension, format: session.format,
                               targets: session.targets, leadingInset: 78) { session.switchFormat(to: $0) }
        if session.canRename {
            h.onRename = { [session, onRenamed] name in
                let problem = await session.rename(toBaseName: name)
                if problem == nil { onRenamed(session.url) }
                return problem
            }
        }
        return h
    }

    /// Read-only viewer: the chip converts next to the original instead of swapping (and trashing) the file.
    private var richHeader: DocumentHeader {
        DocumentHeader(title: (session.title as NSString).deletingPathExtension, format: session.format,
                       targets: session.targets, leadingInset: 78) { session.convert(to: $0) }
    }

    var body: some View {
        Group {
            switch session.content {
            case .loading:
                Color.clear
            case .failed(let message):
                VStack(spacing: 16) {
                    BrandMark(size: 56)
                    Text(message).brandBody().foregroundStyle(Brand.Palette.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .locked:
                LockedFileView(fileName: session.title, canUseTouchID: model.settings.useTouchID && BiometricKeychain.isAvailable,
                               errorMessage: session.lockedMessage) { session.unlock($0, model: model) }
            case .pdf:
                if let doc = session.pdf {
                    PDFReaderView(document: doc,
                                  actions: PDFReaderActions(onConvert: session.requestConvert,
                                                            loadSignature: SignatureStore.load,
                                                            saveSignature: SignatureStore.save,
                                                            clearSignature: SignatureStore.clear),
                                  header: header, commands: session.commands)
                }
            case .richText:
                if let rich = session.rich {
                    RichTextView(attributed: rich,
                                 actions: RichTextActions(onConvert: session.requestConvert, onSaveAs: { session.convert(to: $0) }),
                                 header: richHeader)
                }
            case .html:
                if let html = session.html {
                    HTMLView(html: html,
                             actions: RichTextActions(onConvert: session.requestConvert, onSaveAs: { session.convert(to: $0) }),
                             header: richHeader)
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
        .focusedSceneValue(\.docActions, DocActions(session: session, model: model))
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
    final class Coordinator {
        let session: DocumentSession
        weak var window: NSWindow?
        init(session: DocumentSession) { self.session = session }

        func attach(to w: NSWindow?) {
            guard let w, w !== window else { return }
            window = w
            session.window = w
            WindowGuardDelegate.install(on: w, session: session)
            session.commands.onDirtyChange = { [weak w] dirty in w?.isDocumentEdited = dirty }
        }
    }
}

/// The one window delegate of a document window: handles close confirmation and passes everything else to the
/// delegate SwiftUI installed. It lives as long as the window (associated object), keeps SwiftUI's delegate
/// alive (strong reference) and only forwards selectors that delegate answers, so AppKit can never send a
/// delegate message that nobody implements. If SwiftUI puts a delegate of its own back, that one becomes the
/// forwarding target and this object is installed again.
@MainActor
final class WindowGuardDelegate: NSObject, NSWindowDelegate {
    private static var associationKey = 0
    weak var session: DocumentSession?
    private(set) var original: NSWindowDelegate?
    private var observation: NSKeyValueObservation?
    private var bypass = false

    static func install(on w: NSWindow, session: DocumentSession) {
        if let existing = objc_getAssociatedObject(w, &associationKey) as? WindowGuardDelegate {
            existing.session = session
            existing.ensureInstalled(on: w)
            return
        }
        let g = WindowGuardDelegate()
        g.session = session
        objc_setAssociatedObject(w, &associationKey, g, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        g.ensureInstalled(on: w)
        g.observation = w.observe(\.delegate, options: [.new]) { [weak g] w, _ in
            MainActor.assumeIsolated { g?.ensureInstalled(on: w) }
        }
    }

    /// Puts this delegate on the window; whatever delegate was there before becomes the forwarding target.
    func ensureInstalled(on w: NSWindow) {
        guard w.delegate !== self else { return }
        if let other = w.delegate { original = other }
        w.delegate = self
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let session, !bypass, session.hasUnsavedChanges else { return original?.windowShouldClose?(sender) ?? true }
        Task { @MainActor in
            if await session.confirmClose() { self.bypass = true; sender.close() }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        session?.unregister()
        original?.windowWillClose?(notification)
        observation = nil
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
        // The self-test never touches the user's saved signature.
        if SelfTest.enabled, let dir = SelfTest.dir { return URL(fileURLWithPath: dir).appendingPathComponent(".selftest-signature.png") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenText/signature.png")
    }
    static func load() -> Data? { try? Data(contentsOf: fileURL) }
    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
    static func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
