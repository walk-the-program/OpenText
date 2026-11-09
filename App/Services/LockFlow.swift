import Foundation
import OpenTextAppLogic

/// Lock / unlock orchestration. Engine calls go through EngineAdapter (stand-ins until T3b);
/// Touch ID goes through BiometricKeychain (real).
@MainActor
enum LockFlow {
    struct LockOutcome { let lockedURL: URL; let recoveryKeyToShow: String? }
    enum FlowError: LocalizedError {
        case password(PasswordRules.Problem)
        var errorDescription: String? {
            switch self {
            case .password(.tooShort): return "Use at least \(PasswordRules.minimumLength) characters."
            case .password(.mismatch): return "The two passwords don't match."
            }
        }
    }

    /// First lock generates the recovery key; its display string is returned once and never stored.
    /// Only the public half is saved to settings, and only after the lock succeeded.
    static func lock(_ file: URL, password: String, confirm: String, model: AppModel) throws -> LockOutcome {
        if let problem = PasswordRules.validate(password: password, confirm: confirm) { throw FlowError.password(problem) }
        var pubKey = model.settings.recoveryPublicKey
        var shown: String?
        if pubKey == nil {
            let k = EngineAdapter.generateRecoveryKey()
            pubKey = k.publicKeyBase64
            shown = k.display
        }
        let locked = try EngineAdapter.lock(file, password: password, recoveryPublicKey: pubKey)
        if let pubKey, shown != nil { model.update { $0.recoveryPublicKey = pubKey } }
        if model.settings.useTouchID && BiometricKeychain.isAvailable {
            // Best effort: password unlock still works if the Keychain write fails.
            try? BiometricKeychain.store(password: password, account: EngineAdapter.lockID(for: locked))
        }
        return LockOutcome(lockedURL: locked, recoveryKeyToShow: shown)
    }

    static func unlock(_ file: URL, password: String) throws -> URL {
        try EngineAdapter.unlock(file, password: password)
    }
    static func unlock(_ file: URL, recoveryKey: String) throws -> URL {
        try EngineAdapter.unlock(file, recoveryKey: recoveryKey)
    }
    static func unlockWithTouchID(_ file: URL) async throws -> URL {
        let pw = try await BiometricKeychain.read(account: EngineAdapter.lockID(for: file),
                                                  reason: "Unlock \(file.lastPathComponent)")
        return try EngineAdapter.unlock(file, password: pw)
    }
}
