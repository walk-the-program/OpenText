import CryptoKit
import Foundation
import XCTest
@testable import OpenTextKit

final class LockerTests: TempTestCase {
    func testRoundTripAndName() throws {
        let src = try write("secret é.txt", "top secret ✓")
        let locked = try Locker.lock(src, password: "pw", recoveryPublicKeyBase64: nil)
        XCTAssertEqual(locked.lastPathComponent, "secret é.txt.otlock")
        XCTAssertTrue(Locker.isLocked(locked)); XCTAssertFalse(Locker.isLocked(src))
        XCTAssertFalse(try Data(contentsOf: locked).range(of: Data("top secret".utf8)) != nil)
        try FileManager.default.removeItem(at: src)
        let out = try Locker.unlock(locked, password: "pw")
        XCTAssertEqual(out.lastPathComponent, "secret é.txt")
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "top secret ✓")
        let d = try Locker.decrypt(locked, password: "pw")
        XCTAssertEqual(d.originalName, "secret é.txt"); XCTAssertEqual(String(decoding: d.data, as: UTF8.self), "top secret ✓")
    }

    func testBinaryAndEmptyFiles() throws {
        let bin = file("b.bin"); let bytes = Data((0..<5000).map { UInt8($0 % 251) }); try bytes.write(to: bin)
        XCTAssertEqual(try Locker.decrypt(try Locker.lock(bin, password: "p", recoveryPublicKeyBase64: nil), password: "p").data, bytes)
        let empty = try write("e.txt", "")
        XCTAssertEqual(try Locker.decrypt(try Locker.lock(empty, password: "p", recoveryPublicKeyBase64: nil), password: "p").data.count, 0)
    }

    func testWrongPassword() throws {
        let locked = try Locker.lock(try write("a.txt", "x"), password: "right", recoveryPublicKeyBase64: nil)
        XCTAssertThrowsError(try Locker.unlock(locked, password: "wrong")) { XCTAssertEqual($0 as? OpenTextError, .wrongPassword) }
    }

    func testRecoveryKeyUnlock() throws {
        let (key, pub) = RecoveryKey.generate()
        let locked = try Locker.lock(try write("a.txt", "recover me"), password: "forgotten", recoveryPublicKeyBase64: pub)
        let typed = RecoveryKey(displayString: key.displayString.lowercased().replacingOccurrences(of: "-", with: " "))!
        let out = try Locker.unlock(locked, recoveryKey: typed)
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "recover me")
        let other = RecoveryKey.generate().key
        XCTAssertThrowsError(try Locker.unlock(locked, recoveryKey: other)) { XCTAssertEqual($0 as? OpenTextError, .invalidRecoveryKey) }
        let noSlot = try Locker.lock(try write("b.txt", "x"), password: "p", recoveryPublicKeyBase64: nil)
        XCTAssertThrowsError(try Locker.unlock(noSlot, recoveryKey: key)) { XCTAssertEqual($0 as? OpenTextError, .noRecoveryKeyConfigured) }
        XCTAssertThrowsError(try Locker.lock(try write("c.txt", "x"), password: "p", recoveryPublicKeyBase64: "not-a-key")) {
            XCTAssertEqual($0 as? OpenTextError, .invalidRecoveryKey)
        }
    }

    func testTamperedAndNotLocked() throws {
        let locked = try Locker.lock(try write("a.txt", "payload data"), password: "p", recoveryPublicKeyBase64: nil)
        var data = try Data(contentsOf: locked)
        data[data.count - 20] ^= 0xFF // ciphertext
        let t1 = file("t1.otlock"); try data.write(to: t1)
        XCTAssertThrowsError(try Locker.unlock(t1, password: "p")) { XCTAssertEqual($0 as? OpenTextError, .corruptLockedFile) }
        var data2 = try Data(contentsOf: locked)
        data2[data2.count - 1] ^= 0x01 // tag
        let t2 = file("t2.otlock"); try data2.write(to: t2)
        XCTAssertThrowsError(try Locker.unlock(t2, password: "p")) { XCTAssertEqual($0 as? OpenTextError, .corruptLockedFile) }
        let truncated = file("t3.otlock"); try Data(try Data(contentsOf: locked).prefix(12)).write(to: truncated)
        XCTAssertThrowsError(try Locker.unlock(truncated, password: "p")) { XCTAssertEqual($0 as? OpenTextError, .corruptLockedFile) }
        let plain = try write("plain.txt", "hello")
        XCTAssertThrowsError(try Locker.unlock(plain, password: "p")) { XCTAssertEqual($0 as? OpenTextError, .notLocked) }
    }

    func testRemoveOriginalMovesToTrash() throws {
        let src = try write("rm-\(UUID().uuidString).txt", "x")
        let locked = try Locker.lock(src, password: "p", recoveryPublicKeyBase64: nil, removeOriginal: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locked.path))
        try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(src.lastPathComponent)"))
    }

    func testRecoveryKeyDisplayString() {
        let (key, pub) = RecoveryKey.generate()
        let s = key.displayString
        XCTAssertEqual(s.components(separatedBy: "-").count, 13)
        XCTAssertTrue(s.components(separatedBy: "-").dropLast().allSatisfy { $0.count == 4 })
        XCTAssertEqual(RecoveryKey(displayString: s)?.displayString, s)
        XCTAssertEqual(RecoveryKey(displayString: s.lowercased())?.displayString, s)
        XCTAssertEqual(RecoveryKey(displayString: s.replacingOccurrences(of: "-", with: " "))?.displayString, s)
        let priv = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: key.privateKeyData)
        XCTAssertEqual(priv.publicKey.rawRepresentation.base64EncodedString(), pub)
        XCTAssertNil(RecoveryKey(displayString: "ABCD-EFGH")); XCTAssertNil(RecoveryKey(displayString: "!!!!"))
    }

    /// Independent re-implementation of the documented recipe (docs/build/otlock-format.md), password slot only.
    func testDocumentedRecipeDecrypts() throws {
        let locked = try Locker.lock(try write("doc.txt", "spec check"), password: "pw", recoveryPublicKeyBase64: nil)
        let f = try Data(contentsOf: locked)
        XCTAssertEqual(String(decoding: f.prefix(4), as: UTF8.self), "OTLK"); XCTAssertEqual(f[4], 1)
        let n = Int(f[5]) << 24 | Int(f[6]) << 16 | Int(f[7]) << 8 | Int(f[8])
        let header = try JSONSerialization.jsonObject(with: f[9..<(9 + n)]) as! [String: Any]
        let slot = header["password"] as! [String: Any]
        XCTAssertEqual(slot["iterations"] as? Int, 600_000)
        let kek = Locker.pbkdf2("pw", salt: Data(base64Encoded: slot["salt"] as! String)!, iterations: 600_000)!
        let w = Data(base64Encoded: slot["wrappedKey"] as! String)!
        let box = try AES.GCM.SealedBox(nonce: .init(data: Data(base64Encoded: slot["nonce"] as! String)!), ciphertext: w.dropLast(16), tag: w.suffix(16))
        let fileKey = try AES.GCM.open(box, using: kek, authenticating: Data("OTLK1 password slot".utf8))
        let body = f[(9 + n)...]
        let pbox = try AES.GCM.SealedBox(nonce: .init(data: Data(base64Encoded: header["payloadNonce"] as! String)!), ciphertext: body.dropLast(16), tag: body.suffix(16))
        let plain = try AES.GCM.open(pbox, using: SymmetricKey(data: fileKey), authenticating: f[0..<(9 + n)])
        let nameLen = Int(plain[0]) << 24 | Int(plain[1]) << 16 | Int(plain[2]) << 8 | Int(plain[3])
        XCTAssertEqual(String(decoding: plain[4..<(4 + nameLen)], as: UTF8.self), "doc.txt")
        XCTAssertEqual(String(decoding: plain[(4 + nameLen)...], as: UTF8.self), "spec check")
    }
}

final class SettingsAndToolsTests: TempTestCase {
    func testSettingsDefaultsSaveLoadAndTempPath() throws {
        XCTAssertEqual(OpenTextSettings.fileURL.path, file("settings.json").path)
        var s = OpenTextSettings.load()
        XCTAssertEqual(s.defaultFolder, "~/Desktop"); XCTAssertEqual(s.hotkey, "ctrl+opt+n"); XCTAssertTrue(s.useTouchID)
        XCTAssertEqual(s.lastNewFileFormat, "md"); XCTAssertNil(s.recoveryPublicKey)
        s.hotkey = "cmd+k"; s.recoveryPublicKey = "abc"
        try s.save()
        XCTAssertEqual(OpenTextSettings.load().hotkey, "cmd+k"); XCTAssertEqual(OpenTextSettings.load().recoveryPublicKey, "abc")
        try #"{"hotkey":"x"}"#.write(to: OpenTextSettings.fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(OpenTextSettings.load().hotkey, "x"); XCTAssertEqual(OpenTextSettings.load().defaultFolder, "~/Desktop")
        try "garbage".write(to: OpenTextSettings.fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(OpenTextSettings.load().hotkey, "ctrl+opt+n")
    }

    func testToolsLayer() throws {
        let md = try write("t.md", "# Hi\n")
        let r = try OpenTextTools.call("convert", ["files": [md.path], "to": "html"])
        XCTAssertEqual((r["outputs"] as? [String])?.count, 1)
        let created = try OpenTextTools.call("create_file", ["format": "txt", "folder": dir.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: created["path"] as! String))
        XCTAssertEqual(try OpenTextTools.call("extract_text", ["file": md.path])["text"] as? String, "# Hi\n")
        let lf = try OpenTextTools.call("lock_file", ["file": md.path, "password": "pw"])
        let uf = try OpenTextTools.call("unlock_file", ["file": lf["path"] as! String, "password": "pw", "out": file("back.md").path])
        XCTAssertEqual(try String(contentsOfFile: uf["path"] as! String, encoding: .utf8), "# Hi\n")
        XCTAssertEqual((try OpenTextTools.call("list_formats", ["format": "pdf"])["targets"] as? [String])?.sorted(), ["jpg", "md", "png", "txt"])
        XCTAssertThrowsError(try OpenTextTools.call("convert", ["files": [md.path]]))
        XCTAssertEqual(OpenTextTools.toolDefinitions().compactMap { $0["name"] as? String }, OpenTextTools.toolNames)
    }
}
