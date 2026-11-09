import SwiftUI
import OpenTextDesign
import OpenTextAppLogic

/// Password + confirm + Touch ID toggle. OpenTextUI has no lock-creation sheet, so this is app-side.
struct LockSheet: View {
    let fileName: String
    let onLock: (String, String) throws -> Void
    let onCancel: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text("Lock \(fileName)").brandHeading(20)
            Text("You'll need this password to open it. The original moves to the Trash.")
                .brandBody().foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            SecureField("Password", text: $password).textFieldStyle(.plain).brandField()
            SecureField("Confirm password", text: $confirm).textFieldStyle(.plain).brandField()
                .onSubmit(submit)
            if BiometricKeychain.isAvailable {
                Toggle("Unlock with Touch ID", isOn: Binding(
                    get: { model.settings.useTouchID }, set: { v in model.update { $0.useTouchID = v } }))
                    .brandBody()
            }
            if let error { Text(error).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink) }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.secondaryAction).keyboardShortcut(.cancelAction)
                Button("Lock", action: submit).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 380)
        .background(Brand.Palette.canvas)
    }

    private func submit() {
        do { try onLock(password, confirm) } catch { self.error = error.localizedDescription }
    }
}

/// Result / error card. Reveal-in-Finder only on click; nothing opens by itself.
struct NoticeCard: View {
    let notice: Notice
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text(notice.title).brandHeading(20)
            Text(notice.message).brandBody().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if let url = notice.revealURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.secondaryAction)
                }
                Button("Done", action: onDone).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 380)
        .background(Brand.Palette.canvas)
    }
}

struct NoticeWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        Group {
            if let n = model.notice {
                NoticeCard(notice: n) { model.notice = nil; dismissWindow(id: "notice") }
            }
        }
    }
}
