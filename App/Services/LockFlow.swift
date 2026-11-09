import Foundation
import OpenTextKit
import OpenTextUI
import OpenTextAppLogic

/// Lock / unlock orchestration. Engine: OpenTextKit.Locker. Touch ID: BiometricKeychain keyed by Locker.lockID.
/// PBKDF2 (600k iterations) always runs off the main thread.
@MainActor
enum LockFlow {
    struct LockOutcome {
        var lockedURL: URL?
        var recoveryKeyToShow: String?
        var warnings: [String] = []
        var originalStillThere = false
    }
    enum FlowError: LocalizedError {
        case password(PasswordRules.Problem)
        case noSavedPassword, badRecoveryKey, recoveryChanged
        var errorDescription: String? {
            switch self {
            case .password(.tooShort): return "Use at least \(PasswordRules.minimumLength) characters."
            case .password(.mismatch): return "The two passwords don't match."
            case .noSavedPassword: return "Touch ID has no saved password for this file. Enter the password."
            case .badRecoveryKey: return "That recovery key isn't valid."
            case .recoveryChanged: return "Your recovery key changed outside OpenText."
            }
        }
    }

    enum RecoveryCheck: Equatable {
        case willCreate
        case ok(fingerprint: String)
        case mismatch(pinnedFingerprint: String, currentFingerprint: String)
    }

    static func fingerprint(_ key: String) -> String { RecoveryKey.fingerprint(publicKeyBase64: key) ?? "invalid key" }

    /// Run before every lock and every save-back. Pins/restores as needed; `.mismatch` blocks until Walker chooses.
    static func checkRecovery(model: AppModel) throws -> RecoveryCheck {
        switch PinPolicy.evaluate(pinned: RecoveryPin.read(), current: model.settings.recoveryPublicKey) {
        case .createNew: return .willCreate
        case .adopt(let key):
            try RecoveryPin.save(key)
            return .ok(fingerprint: fingerprint(key))
        case .restore(let key):
            model.update { $0.recoveryPublicKey = key }
            return .ok(fingerprint: fingerprint(key))
        case .ok(let key): return .ok(fingerprint: fingerprint(key))
        case .mismatch(let pinned, let current):
            return .mismatch(pinnedFingerprint: fingerprint(pinned), currentFingerprint: fingerprint(current))
        }
    }

    static func keepOriginalKey(model: AppModel) {
        if let pinned = RecoveryPin.read() { model.update { $0.recoveryPublicKey = pinned } }
    }
    /// Re-pins the key now in settings after Touch ID / password confirmation.
    static func acceptNewKey(model: AppModel) async throws -> Bool {
        guard let current = model.settings.recoveryPublicKey else { return false }
        guard await RecoveryPin.confirmOwner(reason: "Accept the new recovery key") else { return false }
        try RecoveryPin.save(current)
        return true
    }

    /// First lock generates the recovery key; its display string is returned once and never stored.
    /// Only the public half goes to settings and the Keychain pin, after the lock succeeded.
    /// The plaintext original is verified, then moved to the Trash.
    static func lock(_ file: URL, password: String, confirm: String, model: AppModel) async throws -> LockOutcome {
        if let problem = PasswordRules.validate(password: password, confirm: confirm) { throw FlowError.password(problem) }
        if case .mismatch = try checkRecovery(model: model) { throw FlowError.recoveryChanged }
        var pubKey = model.settings.recoveryPublicKey
        var outcome = LockOutcome()
        var created = false
        if pubKey == nil {
            let generated = RecoveryKey.generate()
            pubKey = generated.publicKeyBase64
            outcome.recoveryKeyToShow = generated.key.displayString
            created = true
        }
        let key = pubKey
        let result: Result<(URL?, Bool), Error> = await Task.detached {
            do { return .success((try Locker.lock(file, password: password, recoveryPublicKeyBase64: key, removeOriginal: true), false)) }
            catch OpenTextError.originalNotRemoved { return .success((findLockedSibling(of: file), true)) }
            catch { return .failure(error) }
        }.value
        let (locked, stillThere) = try result.get()
        outcome.lockedURL = locked
        outcome.originalStillThere = stillThere
        if created, let key {
            model.update { $0.recoveryPublicKey = key }
            do { try RecoveryPin.save(key) } catch {
                outcome.warnings.append("The recovery key couldn't be pinned in the Keychain: \(error.localizedDescription)")
            }
        }
        if let locked, let w = storeTouchID(password: password, for: locked, model: model) { outcome.warnings.append(w) }
        return outcome
    }

    /// Stores (or updates) the Touch ID item for a locked file. Returns a user-facing warning on failure.
    static func storeTouchID(password: String, for lockedFile: URL, model: AppModel) -> String? {
        guard model.settings.useTouchID && BiometricKeychain.isAvailable else { return nil }
        do {
            try BiometricKeychain.store(password: password, account: try Locker.lockID(of: lockedFile))
            return nil
        } catch {
            return "Touch ID couldn't be set up for this file: \(error.localizedDescription)"
        }
    }

    nonisolated private static func findLockedSibling(of file: URL) -> URL? {
        let dir = file.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter { $0.pathExtension == "otlock" && $0.lastPathComponent.hasPrefix(file.lastPathComponent) }
            .max { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                 < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
    }

    struct Unlocked { var data: Data; var originalName: String; var password: String?; var warning: String? }

    /// Decrypts into memory; nothing is written to disk.
    static func decrypt(_ file: URL, method: UnlockMethod, model: AppModel) async throws -> Unlocked {
        switch method {
        case .password(let pw):
            let r = try await Task.detached { try Locker.decrypt(file, password: pw) }.value
            var warning: String?
            if model.settings.useTouchID && BiometricKeychain.isAvailable, let id = try? Locker.lockID(of: file),
               !BiometricKeychain.hasItem(account: id) {
                warning = storeTouchID(password: pw, for: file, model: model)
            }
            return Unlocked(data: r.data, originalName: r.originalName, password: pw, warning: warning)
        case .touchID:
            let id = try Locker.lockID(of: file)
            guard BiometricKeychain.hasItem(account: id) else { throw FlowError.noSavedPassword }
            let pw = try await BiometricKeychain.read(account: id, reason: "Unlock \(file.lastPathComponent)")
            let r = try await Task.detached { try Locker.decrypt(file, password: pw) }.value
            return Unlocked(data: r.data, originalName: r.originalName, password: pw, warning: nil)
        case .recoveryKey(let text):
            guard let k = RecoveryKey(displayString: text) else { throw FlowError.badRecoveryKey }
            let r = try await Task.detached { try Locker.decrypt(file, recoveryKey: k) }.value
            return Unlocked(data: r.data, originalName: r.originalName, password: nil, warning: nil)
        }
    }

    /// Save-back for an unlocked document: re-lock with the session password over the same file, then re-key Touch ID.
    static func saveBack(data: Data, name: String, to file: URL, password: String, model: AppModel) async throws -> String? {
        let oldID = try? Locker.lockID(of: file)
        let key = model.settings.recoveryPublicKey
        _ = try await Task.detached {
            try Locker.lock(data: data, originalName: name, password: password, recoveryPublicKeyBase64: key, output: file)
        }.value
        var warning: String?
        if model.settings.useTouchID && BiometricKeychain.isAvailable {
            warning = storeTouchID(password: password, for: file, model: model)
            if warning == nil, let oldID, let newID = try? Locker.lockID(of: file), newID != oldID {
                BiometricKeychain.delete(account: oldID)
            }
        }
        return warning
    }
}
