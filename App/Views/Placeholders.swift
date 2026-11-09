import SwiftUI
import KeyboardShortcuts
import OpenTextAppLogic

// STAND-IN views. T3b replaces these bodies with OpenTextUI views (PDFReaderView, ImageEditorView,
// TextEditorView, QuickCreateView, SetupView, LockedFileView, ConvertSheet, RecoveryKeySheet).
// Their inputs/closures already mirror the PLAN.md view contracts (plain values, extension strings).

struct DocumentWindowView: View {
    let url: URL
    @EnvironmentObject var model: AppModel
    @State private var showConvert = false
    @State private var showLock = false
    @State private var recoveryKey: String?

    var body: some View {
        VStack(spacing: 12) {
            switch FileRouting.kind(for: url) {
            case .locked: LockedStandIn(url: url)
            case .pdf: Text("PDF reader (stand-in)")
            case .image: Text("Image editor (stand-in)")
            case .text, .markdown: Text("Text editor (stand-in)")
            case .unsupported: Text("OpenText can't open this file.")
            }
            Text(url.lastPathComponent).font(.headline)
            if FileRouting.kind(for: url) != .locked {
                HStack {
                    Button("Convert…") { showConvert = true }
                    Button("Lock…") { showLock = true }
                }
            }
        }
        .padding(24).frame(minWidth: 420, minHeight: 280)
        .navigationTitle(url.lastPathComponent)
        .sheet(isPresented: $showConvert) {
            ConvertStandIn(url: url) { showConvert = false }
        }
        .sheet(isPresented: $showLock) {
            LockSheetStandIn(url: url) { key in showLock = false; recoveryKey = key }
        }
        .sheet(item: Binding(get: { recoveryKey.map(Identified.init) }, set: { _ in recoveryKey = nil })) { k in
            RecoveryKeyStandIn(displayString: k.value) { recoveryKey = nil }
        }
        .onChange(of: model.lockRequest) { _, req in
            if req == url { showLock = true; model.lockRequest = nil }
        }
    }
}

struct Identified: Identifiable { let value: String; var id: String { value } }

struct ConvertStandIn: View {
    let url: URL
    let done: () -> Void
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Convert \(url.lastPathComponent) to").font(.headline)
            ForEach(EngineAdapter.convertTargets(from: url.pathExtension), id: \.self) { fmt in
                Button(fmt) { model.convert(url, to: fmt); done() }
            }
            Button("Cancel", action: done).keyboardShortcut(.cancelAction)
        }.padding(20).frame(minWidth: 260)
    }
}

struct LockSheetStandIn: View {
    let url: URL
    let done: (String?) -> Void
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lock \(url.lastPathComponent)").font(.headline)
            SecureField("Password", text: $password)
            SecureField("Confirm password", text: $confirm)
            Toggle("Unlock with Touch ID", isOn: Binding(
                get: { model.settings.useTouchID }, set: { v in model.update { $0.useTouchID = v } }))
                .disabled(!BiometricKeychain.isAvailable)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Lock") {
                    do {
                        let out = try LockFlow.lock(url, password: password, confirm: confirm, model: model)
                        done(out.recoveryKeyToShow)
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 320)
    }
}

struct RecoveryKeyStandIn: View {
    let displayString: String
    let onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your recovery key").font(.headline)
            Text("Shown once. Print it or save it offline. It unlocks your files if you forget the password.")
            Text(displayString).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
            Button("Done", action: onDone).keyboardShortcut(.defaultAction)
        }.padding(20).frame(width: 380)
    }
}

struct LockedStandIn: View {
    let url: URL
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @State private var recovery = ""
    @State private var useRecovery = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 8) {
            Text("This file is locked").font(.title3)
            if useRecovery {
                TextField("Recovery key", text: $recovery)
                Button("Unlock with recovery key") { run { try LockFlow.unlock(url, recoveryKey: recovery) } }
            } else {
                SecureField("Password", text: $password).onSubmit { run { try LockFlow.unlock(url, password: password) } }
                HStack {
                    Button("Unlock") { run { try LockFlow.unlock(url, password: password) } }
                    if model.settings.useTouchID && BiometricKeychain.isAvailable {
                        Button("Use Touch ID") { Task { await touchID() } }
                    }
                }
            }
            Button(useRecovery ? "Use password" : "Use recovery key") { useRecovery.toggle(); error = nil }
                .buttonStyle(.link)
            if let error { Text(error).foregroundStyle(.red) }
        }.frame(width: 280)
    }

    private func run(_ work: () throws -> URL) {
        do { model.openFile(try work()) } catch { self.error = error.localizedDescription }
    }
    private func touchID() async {
        do { model.openFile(try await LockFlow.unlockWithTouchID(url)) } catch { self.error = error.localizedDescription }
    }
}

struct QuickCreateStandIn: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New file in \(model.settings.defaultFolder)").font(.caption).foregroundStyle(.secondary)
            ForEach([("md", "Markdown"), ("txt", "Plain text")], id: \.0) { fmt, label in
                Button(label) { model.createNew(format: fmt) }
            }
            Divider()
            Button("Setup…") { model.showSetup() }
            Button("Quit OpenText") { NSApp.terminate(nil) }
            if let e = model.lastError { Text(e).font(.caption).foregroundStyle(.red) }
        }.padding(12)
    }
}

struct SetupStandIn: View {
    @EnvironmentObject var model: AppModel
    @State private var defaultsResult: String?
    @State private var extensionOn = SetupActions.finderExtensionEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tile("Make OpenText your default", "Images, PDF, .txt and .md.") {
                Button("Set as default") { Task {
                    let failed = await SetupActions.makeDefault()
                    defaultsResult = failed.isEmpty ? "Done" : "\(failed.count) type(s) unchanged"
                } }
                if let defaultsResult { Text(defaultsResult).font(.caption) }
            }
            tile("Turn on Finder right-click", extensionOn ? "On" : "Off. Switch it on in System Settings.") {
                Button("Open System Settings") { SetupActions.openExtensionSettings() }
                Button("Check again") { extensionOn = SetupActions.finderExtensionEnabled }
            }
            tile("Your new-file shortcut", hotkeyHelp) {
                KeyboardShortcuts.Recorder(for: .quickCreate) { _ in model.shortcutRecorded() }
            }
            Button("Done") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
        }
        .padding(24).frame(width: 440)
    }

    private var hotkeyHelp: String {
        model.hotkeyValid ? "Active: \(model.settings.hotkey). Click the box to change it."
                          : "settings.json has an invalid hotkey. Pick one here."
    }

    private func tile<C: View>(_ title: String, _ detail: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
            HStack { content() }
        }
    }
}
