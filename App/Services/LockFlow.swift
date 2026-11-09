import Foundation
import OpenTextKit
import OpenTextUI
import OpenTextAppLogic

/// Lock / unlock orchestration. Engine: OpenTextKit.Locker. Touch ID: BiometricKeychain keyed by Locker.lockID.
@MainActor
enum LockFlow {
    struct LockOutcome { let lockedURL: URL; let recoveryKeyToShow: String? }
    enum FlowError: LocalizedError {
        case password(PasswordRules.Problem)
        case noSavedPassword, badRecoveryKey
        var errorDescription: String? {
            switch self {
            case .password(.tooShort): return "Use at least \(PasswordRules.minimumLength) characters."
            case .password(.mismatch): return "The two passwords don't match."
            case .noSavedPassword: return "Touch ID has no saved password for this file. Enter the password."
            case .badRecoveryKey: return "That recovery key isn't valid."
            }
        }
    }

    /// First lock generates the recovery key; its display string is returned once and never stored.
    /// Only the public half is saved to settings, and only after the lock succeeded.
    /// The plaintext original is moved to the Trash.
    static func lock(_ file: URL, password: String, confirm: String, model: AppModel) throws -> LockOutcome {
        if let problem = PasswordRules.validate(password: password, confirm: confirm) { throw FlowError.password(problem) }
        var pubKey = model.settings.recoveryPublicKey
        var shown: String?
        if pubKey == nil {
            let generated = RecoveryKey.generate()
            pubKey = generated.publicKeyBase64
            shown = generated.key.displayString
        }
        let locked = try Locker.lock(file, password: password, recoveryPublicKeyBase64: pubKey, removeOriginal: true)
        if shown != nil, let pubKey { model.update { $0.recoveryPublicKey = pubKey } }
        if model.settings.useTouchID && BiometricKeychain.isAvailable, let id = try? Locker.lockID(of: locked) {
            // Best effort: password unlock still works if the Keychain write fails.
            try? BiometricKeychain.store(password: password, account: id)
        }
        return LockOutcome(lockedURL: locked, recoveryKeyToShow: shown)
    }

    /// Decrypts into memory; nothing is written to disk.
    static func decrypt(_ file: URL, method: UnlockMethod, model: AppModel) async throws -> (data: Data, originalName: String) {
        guard case .touchID = method else {
            guard case .password(let pw) = method else { preconditionFailure("recovery key unlock writes a file; see unlockRecovery") }
            let r = try Locker.decrypt(file, password: pw)
            if model.settings.useTouchID && BiometricKeychain.isAvailable, let id = try? Locker.lockID(of: file),
               !BiometricKeychain.hasItem(account: id) {
                try? BiometricKeychain.store(password: pw, account: id)
            }
            return r
        }
        let id = try Locker.lockID(of: file)
        guard BiometricKeychain.hasItem(account: id) else { throw FlowError.noSavedPassword }
        let pw = try await BiometricKeychain.read(account: id, reason: "Unlock \(file.lastPathComponent)")
        return try Locker.decrypt(file, password: pw)
    }

    /// Recovery unlock is Walker's explicit "unlock to a file": writes the original next to the .otlock.
    static func unlockRecovery(_ file: URL, key: String) throws -> URL {
        guard let k = RecoveryKey(displayString: key) else { throw FlowError.badRecoveryKey }
        return try Locker.unlock(file, recoveryKey: k)
    }
}
