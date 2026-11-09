import Foundation
import LocalAuthentication
import Security

/// The recovery PUBLIC key, pinned in the data-protection Keychain so an edit to settings.json
/// can't silently add someone else's recovery slot to new locks.
enum RecoveryPin {
    private static let service = "com.walkertracy.opentext.recovery-pin"
    private static let account = "public-key"

    private static func base() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: BiometricKeychain.accessGroup,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func read() -> String? {
        var q = base()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func save(_ publicKeyBase64: String) throws {
        var q = base()
        q[kSecValueData as String] = Data(publicKeyBase64.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(base() as CFDictionary, [kSecValueData as String: Data(publicKeyBase64.utf8)] as CFDictionary)
        }
        guard status == errSecSuccess else { throw BiometricKeychain.KeychainError.status(status) }
    }

    /// Touch ID or the Mac password. Used before accepting a changed recovery key.
    static func confirmOwner(reason: String) async -> Bool {
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
