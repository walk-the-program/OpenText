import CommonCrypto
import CryptoKit
import Foundation

public struct RecoveryKey: Sendable {
    let privateKeyData: Data

    public static func generate() -> (key: RecoveryKey, publicKeyBase64: String) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return (RecoveryKey(privateKeyData: priv.rawRepresentation), priv.publicKey.rawRepresentation.base64EncodedString())
    }

    init(privateKeyData: Data) { self.privateKeyData = privateKeyData }

    /// First 8 bytes of SHA-256 of the raw public key, hex, 4 groups ("3fa2-91bc-0d44-7e10"). nil if not a valid key.
    public static func fingerprint(publicKeyBase64: String) -> String? {
        guard let raw = Data(base64Encoded: publicKeyBase64), raw.count == 32 else { return nil }
        let hex = SHA256.hash(data: raw).prefix(8).map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: 16, by: 4).map { i in String(hex.dropFirst(i).prefix(4)) }.joined(separator: "-")
    }

    /// Tolerant of spaces, dashes and case.
    public init?(displayString: String) {
        let cleaned = displayString.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let data = Base32.decode(cleaned), data.count == 32 else { return nil }
        self.privateKeyData = data
    }

    /// Base32 (RFC 4648, no padding), groups of 4 separated by "-".
    public var displayString: String {
        let s = Base32.encode(privateKeyData)
        return stride(from: 0, to: s.count, by: 4).map { i in
            String(s.dropFirst(i).prefix(4))
        }.joined(separator: "-")
    }
}

enum Base32 {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var out = ""
        var buffer = 0, bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte); bits += 8
            while bits >= 5 { bits -= 5; out.append(alphabet[(buffer >> bits) & 31]) }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    static func decode(_ s: String) -> Data? {
        var out = Data()
        var buffer = 0, bits = 0
        for ch in s {
            guard let v = alphabet.firstIndex(of: ch) else { return nil }
            buffer = (buffer << 5) | v; bits += 5
            if bits >= 8 { bits -= 8; out.append(UInt8((buffer >> bits) & 0xFF)) }
            buffer &= (1 << bits) - 1
        }
        return out
    }
}

public enum Locker {
    static let magic = Data("OTLK".utf8)
    static let iterations = 600_000
    static let aadPassword = Data("OTLK1 password slot".utf8)
    static let aadRecovery = Data("OTLK1 recovery slot".utf8)
    static let hkdfInfo = "OpenText recovery v1"

    struct PasswordSlot: Codable {
        var kdf: String, iterations: Int, salt: String, nonce: String, wrappedKey: String
    }
    struct RecoverySlot: Codable {
        var kdf: String, ephemeralPublicKey: String, salt: String, info: String, nonce: String, wrappedKey: String
    }
    struct Header: Codable {
        var version: Int, cipher: String, payloadNonce: String
        var password: PasswordSlot
        var recovery: RecoverySlot?
    }

    // MARK: crypto helpers

    static func pbkdf2(_ password: String, salt: Data, iterations: Int) -> SymmetricKey? {
        var key = [UInt8](repeating: 0, count: 32)
        let pw = Array(password.utf8)
        let status = pw.withUnsafeBufferPointer { pwp in
            salt.withUnsafeBytes { sp in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     UnsafeRawPointer(pwp.baseAddress ?? UnsafePointer(bitPattern: 1)!).assumingMemoryBound(to: CChar.self), pw.count,
                                     sp.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &key, 32)
            }
        }
        return status == kCCSuccess ? SymmetricKey(data: key) : nil
    }

    static func seal(_ plain: Data, key: SymmetricKey, nonce: AES.GCM.Nonce, aad: Data) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key, nonce: nonce, authenticating: aad)
        return box.ciphertext + box.tag
    }

    static func open(_ body: Data, key: SymmetricKey, nonce: Data, aad: Data) -> Data? {
        guard body.count >= 16, let n = try? AES.GCM.Nonce(data: nonce) else { return nil }
        let ct = body.prefix(body.count - 16), tag = body.suffix(16)
        guard let box = try? AES.GCM.SealedBox(nonce: n, ciphertext: ct, tag: tag) else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: aad)
    }

    static func random(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }

    static func uint32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).bigEndian) { Data($0) } }

    /// Largest file (and largest locked file) Locker will handle; the whole payload is processed in memory.
    static let maxFileSize = 2 * 1024 * 1024 * 1024

    static func checkSize(_ url: URL) throws {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        if size > maxFileSize { throw OpenTextError.fileTooLarge(url) }
    }

    // MARK: lock

    public static func lock(_ input: URL, password: String, recoveryPublicKeyBase64: String?, output: URL? = nil, removeOriginal: Bool = false) throws -> URL {
        try checkSize(input)
        guard let content = try? Data(contentsOf: input, options: .mappedIfSafe) else { throw OpenTextError.unreadable(input) }
        let dest = Files.unique(output ?? input.appendingPathExtension("otlock"))
        try lock(data: content, originalName: input.lastPathComponent, password: password, recoveryPublicKeyBase64: recoveryPublicKeyBase64, output: dest)
        if removeOriginal {
            // Verify the locked file decrypts to the same bytes before the original goes away.
            guard let check = try? decrypt(dest, password: password), check.data == content else {
                try? FileManager.default.removeItem(at: dest)
                throw OpenTextError.writeFailed(dest)
            }
            do { try FileManager.default.trashItem(at: input, resultingItemURL: nil) } catch { throw OpenTextError.originalNotRemoved(original: input, locked: dest) }
        }
        return dest
    }

    /// Encrypts in-memory data to `output` (atomic temp file + replace; overwrites an existing file, so it is the save-back path).
    /// A fresh file key and salts are generated each call, so `lockID(of:)` changes on every save.
    @discardableResult
    public static func lock(data content: Data, originalName: String, password: String, recoveryPublicKeyBase64: String?, output: URL) throws -> URL {
        guard content.count <= maxFileSize else { throw OpenTextError.fileTooLarge(output) }
        let fileKey = SymmetricKey(size: .bits256)
        let fileKeyData = fileKey.withUnsafeBytes { Data($0) }

        let pwSalt = random(16)
        guard let pwKek = pbkdf2(password, salt: pwSalt, iterations: iterations) else { throw OpenTextError.writeFailed(output) }
        let pwNonce = AES.GCM.Nonce()
        let pwWrapped = try seal(fileKeyData, key: pwKek, nonce: pwNonce, aad: aadPassword)
        let passwordSlot = PasswordSlot(kdf: "PBKDF2-HMAC-SHA256", iterations: iterations, salt: pwSalt.base64EncodedString(),
                                        nonce: Data(pwNonce).base64EncodedString(), wrappedKey: pwWrapped.base64EncodedString())

        var recoverySlot: RecoverySlot?
        if let pubB64 = recoveryPublicKeyBase64 {
            guard let raw = Data(base64Encoded: pubB64), let pub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else {
                throw OpenTextError.invalidRecoveryKey
            }
            let eph = Curve25519.KeyAgreement.PrivateKey()
            let salt = random(16)
            let shared = try eph.sharedSecretFromKeyAgreement(with: pub)
            let kek = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data(hkdfInfo.utf8), outputByteCount: 32)
            let nonce = AES.GCM.Nonce()
            let wrapped = try seal(fileKeyData, key: kek, nonce: nonce, aad: aadRecovery)
            recoverySlot = RecoverySlot(kdf: "X25519-HKDF-SHA256", ephemeralPublicKey: eph.publicKey.rawRepresentation.base64EncodedString(),
                                        salt: salt.base64EncodedString(), info: hkdfInfo, nonce: Data(nonce).base64EncodedString(),
                                        wrappedKey: wrapped.base64EncodedString())
        }

        let payloadNonce = AES.GCM.Nonce()
        let header = Header(version: 1, cipher: "AES-256-GCM", payloadNonce: Data(payloadNonce).base64EncodedString(),
                            password: passwordSlot, recovery: recoverySlot)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let headerJSON = try enc.encode(header)
        var prefix = magic
        prefix.append(1)
        prefix.append(uint32(headerJSON.count))
        prefix.append(headerJSON)

        let name = Data(originalName.utf8)
        var plain = Data()
        plain.reserveCapacity(4 + name.count + content.count)
        plain.append(uint32(name.count))
        plain.append(name)
        plain.append(content)
        let box = try AES.GCM.seal(plain, using: fileKey, nonce: payloadNonce, authenticating: prefix)
        plain = Data()

        // Stream prefix + ciphertext + tag straight to a temp file, then place it atomically.
        do {
            try Files.withTempDir { dir in
                let tmp = dir.appendingPathComponent("out.otlock")
                guard FileManager.default.createFile(atPath: tmp.path, contents: nil) else { throw OpenTextError.writeFailed(output) }
                let h = try FileHandle(forWritingTo: tmp)
                defer { try? h.close() }
                try h.write(contentsOf: prefix)
                try h.write(contentsOf: box.ciphertext)
                try h.write(contentsOf: box.tag)
                try h.close()
                try Files.place(tmp, output)
            }
        } catch { throw OpenTextError.writeFailed(output) }
        return output
    }

    // MARK: unlock

    struct Parsed { var header: Header; var prefix: Data; var body: Data }

    static func parse(_ input: URL) throws -> Parsed {
        try checkSize(input)
        guard let data = try? Data(contentsOf: input, options: .mappedIfSafe) else { throw OpenTextError.unreadable(input) }
        guard data.count >= 5, data.prefix(4) == magic else { throw OpenTextError.notLocked }
        guard data[4] == 1, data.count >= 9 else { throw OpenTextError.corruptLockedFile }
        let len = data[5..<9].reduce(0) { ($0 << 8) | Int($1) }
        guard data.count >= 9 + len + 16 else { throw OpenTextError.corruptLockedFile }
        let headerJSON = data[9..<(9 + len)]
        guard let header = try? JSONDecoder().decode(Header.self, from: headerJSON), header.version == 1,
              (600_000...10_000_000).contains(header.password.iterations) else { throw OpenTextError.corruptLockedFile }
        return Parsed(header: header, prefix: data[0..<(9 + len)], body: data[(9 + len)...])
    }

    static func decryptPayload(_ p: Parsed, fileKey: SymmetricKey) throws -> (data: Data, originalName: String) {
        guard let nonce = Data(base64Encoded: p.header.payloadNonce),
              let plain = open(p.body, key: fileKey, nonce: nonce, aad: p.prefix), plain.count >= 4 else {
            throw OpenTextError.corruptLockedFile
        }
        let n = plain[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        guard plain.count >= 4 + n, let name = String(data: plain[4..<(4 + n)], encoding: .utf8) else { throw OpenTextError.corruptLockedFile }
        return (Data(plain[(4 + n)...]), name)
    }

    static func fileKey(_ p: Parsed, password: String) throws -> SymmetricKey {
        let s = p.header.password
        guard let salt = Data(base64Encoded: s.salt), let nonce = Data(base64Encoded: s.nonce),
              let wrapped = Data(base64Encoded: s.wrappedKey) else { throw OpenTextError.corruptLockedFile }
        guard let kek = pbkdf2(password, salt: salt, iterations: s.iterations),
              let k = open(wrapped, key: kek, nonce: nonce, aad: aadPassword) else { throw OpenTextError.wrongPassword }
        return SymmetricKey(data: k)
    }

    static func fileKey(_ p: Parsed, recovery: RecoveryKey) throws -> SymmetricKey {
        guard let s = p.header.recovery else { throw OpenTextError.noRecoveryKeyConfigured }
        guard let ephRaw = Data(base64Encoded: s.ephemeralPublicKey), let salt = Data(base64Encoded: s.salt),
              let nonce = Data(base64Encoded: s.nonce), let wrapped = Data(base64Encoded: s.wrappedKey),
              let eph = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephRaw) else { throw OpenTextError.corruptLockedFile }
        guard let priv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: recovery.privateKeyData),
              let shared = try? priv.sharedSecretFromKeyAgreement(with: eph) else { throw OpenTextError.invalidRecoveryKey }
        let kek = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data(s.info.utf8), outputByteCount: 32)
        guard let k = open(wrapped, key: kek, nonce: nonce, aad: aadRecovery) else { throw OpenTextError.invalidRecoveryKey }
        return SymmetricKey(data: k)
    }

    static func write(_ r: (data: Data, originalName: String), input: URL, output: URL?) throws -> URL {
        let safe = (r.originalName as NSString).lastPathComponent
        let name = safe.isEmpty ? "Unlocked" : safe
        let dest = Files.unique(output ?? input.deletingLastPathComponent().appendingPathComponent(name))
        do { try r.data.write(to: dest, options: .atomic) } catch { throw OpenTextError.writeFailed(dest) }
        return dest
    }

    public static func unlock(_ input: URL, password: String, output: URL? = nil) throws -> URL {
        let p = try parse(input)
        return try write(try decryptPayload(p, fileKey: try fileKey(p, password: password)), input: input, output: output)
    }

    public static func unlock(_ input: URL, recoveryKey: RecoveryKey, output: URL? = nil) throws -> URL {
        let p = try parse(input)
        return try write(try decryptPayload(p, fileKey: try fileKey(p, recovery: recoveryKey)), input: input, output: output)
    }

    public static func decrypt(_ input: URL, password: String) throws -> (data: Data, originalName: String) {
        let p = try parse(input)
        return try decryptPayload(p, fileKey: try fileKey(p, password: password))
    }

    public static func decrypt(_ input: URL, recoveryKey: RecoveryKey) throws -> (data: Data, originalName: String) {
        let p = try parse(input)
        return try decryptPayload(p, fileKey: try fileKey(p, recovery: recoveryKey))
    }

    /// Stable id for one locked file: SHA-256 (hex) of the password-slot salt in its header.
    /// Used as the Keychain account for Touch ID. Different per lock operation (including every save-back via lock(data:)), unchanged by renaming or moving.
    public static func lockID(of url: URL) throws -> String {
        let p = try parse(url)
        guard let salt = Data(base64Encoded: p.header.password.salt), !salt.isEmpty else { throw OpenTextError.corruptLockedFile }
        return SHA256.hash(data: salt).map { String(format: "%02x", $0) }.joined()
    }

    public static func isLocked(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let d = (try? h.read(upToCount: 5)) ?? Data()
        return d.count == 5 && d.prefix(4) == magic && d[4] == 1
    }
}
