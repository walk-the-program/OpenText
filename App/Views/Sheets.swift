import SwiftUI
import OpenTextDesign
import OpenTextAppLogic

/// Password + confirm. OpenTextUI has no lock-creation sheet, so this is app-side.
/// Shows the recovery key fingerprint so Walker can spot a swapped key.
struct LockSheet: View {
    let title: String
    let explanation: String
    let fingerprint: String?
    let confirmLabel: String
    let onSubmit: (String, String) async throws -> Void
    let onCancel: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text(title).brandHeading(20)
            Text(explanation)
                .brandBody().foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            SecureField("Password", text: $password).textFieldStyle(.plain).brandField()
            SecureField("Confirm password", text: $confirm).textFieldStyle(.plain).brandField()
                .onSubmit(submit)
            if BiometricKeychain.isAvailable {
                Toggle("Unlock with Touch ID", isOn: Binding(
                    get: { model.settings.useTouchID }, set: { v in model.update { $0.useTouchID = v } }))
                    .brandBody()
            }
            if let fingerprint {
                Text(fingerprint).font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.secondaryAction).keyboardShortcut(.cancelAction)
                Button(confirmLabel, action: submit).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
            }
            .disabled(busy)
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 400)
        .background(Brand.Palette.canvas)
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do { try await onSubmit(password, confirm) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct PinMismatchSheet: View {
    let info: PinMismatch
    let onKeepOriginal: () -> Void
    let onAcceptNew: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text("Your recovery key changed outside OpenText").brandHeading(20)
            Text("The recovery key in settings.json is not the one OpenText saved when you first locked a file. Someone or something edited the file. Locking is paused.")
                .brandBody().fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Original key: \(info.pinned)")
                Text("Key now in settings: \(info.current)")
            }
            .font(Brand.Fonts.body(12, weight: .semibold)).textSelection(.enabled)
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.toolbarItem)
                Spacer()
                Button("Accept the new key", action: onAcceptNew).buttonStyle(.secondaryAction)
                Button("Keep using the original key", action: onKeepOriginal).buttonStyle(.primaryAction)
            }
            Text("Accepting the new key asks for Touch ID or your Mac password.")
                .font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted)
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 460)
        .background(Brand.Palette.canvas)
    }
}

struct ChangedOutsideSheet: View {
    let fileName: String
    let onReload: () -> Void
    let onKeepMine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text("Changed outside OpenText").brandHeading(20)
            Text("\(fileName) was modified by something else since you opened it. Reload to see that version and drop your edits, or keep yours and overwrite it.")
                .brandBody().fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Keep Mine", action: onKeepMine).buttonStyle(.secondaryAction)
                Button("Reload", action: onReload).buttonStyle(.primaryAction).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 420)
        .background(Brand.Palette.canvas)
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
        .frame(width: 400)
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
