import SwiftUI
import OpenTextDesign

public enum UnlockMethod: Equatable, Sendable {
    case password(String)
    case touchID
    case recoveryKey(String)
}

/// A single tile reading "Locked": password field, Use Touch ID as the one primary (Unlock is primary without Touch ID).
public struct LockedFileView: View {
    let fileName: String
    let canUseTouchID: Bool
    let errorMessage: String?
    let onUnlock: (UnlockMethod) -> Void
    @State private var password = ""
    @State private var recoveryKey = ""
    @State private var usingRecoveryKey = false
    @FocusState private var focused: Bool

    public init(fileName: String, canUseTouchID: Bool, errorMessage: String? = nil, onUnlock: @escaping (UnlockMethod) -> Void) {
        self.fileName = fileName
        self.canUseTouchID = canUseTouchID
        self.errorMessage = errorMessage
        self.onUnlock = onUnlock
    }

    private var submit: UnlockMethod { usingRecoveryKey ? .recoveryKey(recoveryKey) : .password(password) }
    private var canSubmit: Bool { usingRecoveryKey ? !recoveryKey.isEmpty : !password.isEmpty }

    public var body: some View {
        ZStack {
            Brand.Palette.canvas
            VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "lock").font(.system(size: 20, weight: .regular)).foregroundStyle(Brand.Palette.ink)
                        .padding(.bottom, 6)
                    Text("Locked").brandHeading(26)
                    Text(fileName).brandBody().foregroundStyle(Brand.Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(usingRecoveryKey ? "Recovery key" : "Password").brandLabel()
                    Group {
                        if usingRecoveryKey {
                            TextField("XXXX-XXXX-XXXX-…", text: $recoveryKey)
                        } else {
                            SecureField("", text: $password)
                        }
                    }
                    .brandField().focused($focused).onSubmit { if canSubmit { onUnlock(submit) } }
                    if let errorMessage {
                        Text(errorMessage).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                    }
                }
                HStack(spacing: Brand.Spacing.sm) {
                    if canUseTouchID && !usingRecoveryKey {
                        Button("Use Touch ID") { onUnlock(.touchID) }.buttonStyle(.primaryAction(showsArrow: false)).keyboardShortcut(.defaultAction)
                        Button("Unlock") { onUnlock(submit) }.buttonStyle(.secondaryAction).disabled(!canSubmit)
                    } else {
                        Button("Unlock") { onUnlock(submit) }.buttonStyle(.primaryAction(showsArrow: false))
                            .keyboardShortcut(.defaultAction).disabled(!canSubmit)
                    }
                }
                Button(usingRecoveryKey ? "Use password instead" : "Use recovery key") { usingRecoveryKey.toggle(); focused = true }
                    .buttonStyle(.plain).font(Brand.Fonts.body(13, weight: .semibold)).underline().foregroundStyle(Brand.Palette.ink)
            }
            .padding(28).frame(width: 360)
            .raisedSurface(radius: Brand.Radius.card, fill: Brand.Palette.surface)
        }
        .onAppear { focused = true }
    }
}
