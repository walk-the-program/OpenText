import Foundation
import LocalAuthentication
import Security

/// Touch ID unlock: the file password lives in a Keychain item protected by
/// SecAccessControl .biometryCurrentSet (invalidated if fingerprints change).
/// One item per locked file; account = the file's lock id.
/// Real implementation (not a stand-in). Never called at launch or from tests.
enum BiometricKeychain {
    static let service = "com.walkertracy.opentext.lock"
    /// Matches the keychain-access-groups entitlement ($(AppIdentifierPrefix)com.walkertracy.opentext).
    static let accessGroup = "7ZT7J8C9QP.com.walkertracy.opentext"

    enum KeychainError: LocalizedError {
        case unavailable, status(OSStatus), badData
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Touch ID is not available on this Mac."
            case .status(let s): return (SecCopyErrorMessageString(s, nil) as String?) ?? "Keychain error \(s)."
            case .badData: return "The saved password could not be read."
            }
        }
    }

    /// Asked once per launch, on first use. SwiftUI reads this on every body evaluation; a fresh LAContext each
    /// time created one every ~12 ms while a sheet was up.
    static let isAvailable: Bool = {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }()

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: accessGroup,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func store(password: String, account: String) throws {
        var cfErr: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &cfErr) else {
            throw KeychainError.unavailable
        }
        var q = baseQuery(account: account)
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccessControl as String] = access
        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let changes: [String: Any] = [kSecValueData as String: Data(password.utf8),
                                          kSecAttrAccessControl as String: access]
            status = SecItemUpdate(baseQuery(account: account) as CFDictionary, changes as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// Prompts for Touch ID with `reason`, then returns the stored password.
    static func read(account: String, reason: String) async throws -> String {
        let ctx = LAContext()
        ctx.localizedReason = reason
        var q = baseQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationContext as String] = ctx
        let query = q
        return try await Task.detached {
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess else { throw KeychainError.status(status) }
            guard let data = item as? Data, let s = String(data: data, encoding: .utf8) else { throw KeychainError.badData }
            return s
        }.value
    }

    static func hasItem(account: String) -> Bool {
        var q = baseQuery(account: account)
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = ctx
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
