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

    func testLockID() throws {
        let src = try write("id.txt", "x")
        let a = try Locker.lock(src, password: "p", recoveryPublicKeyBase64: nil)
        let b = try Locker.lock(src, password: "p", recoveryPublicKeyBase64: nil)
        let idA = try Locker.lockID(of: a)
        XCTAssertEqual(idA.count, 64)
        XCTAssertEqual(idA, try Locker.lockID(of: a))
        XCTAssertNotEqual(idA, try Locker.lockID(of: b))
        let moved = file("moved.otlock"); try FileManager.default.moveItem(at: a, to: moved)
        XCTAssertEqual(idA, try Locker.lockID(of: moved))
        XCTAssertThrowsError(try Locker.lockID(of: src)) { XCTAssertEqual($0 as? OpenTextError, .notLocked) }
    }

    func testDataLockRoundTripEmptyAndNonASCII() throws {
        let out = file("é ✓.txt.otlock")
        let r = try Locker.lock(data: Data("héllo ✓".utf8), originalName: "é ✓.txt", password: "pw", recoveryPublicKeyBase64: nil, output: out)
        XCTAssertEqual(r, out); XCTAssertTrue(Locker.isLocked(out))
        let d = try Locker.decrypt(out, password: "pw")
        XCTAssertEqual(d.originalName, "é ✓.txt"); XCTAssertEqual(String(decoding: d.data, as: UTF8.self), "héllo ✓")
        let e = file("e.otlock")
        try Locker.lock(data: Data(), originalName: "empty.txt", password: "pw", recoveryPublicKeyBase64: nil, output: e)
        XCTAssertEqual(try Locker.decrypt(e, password: "pw").data.count, 0)
        XCTAssertThrowsError(try Locker.decrypt(e, password: "bad")) { XCTAssertEqual($0 as? OpenTextError, .wrongPassword) }
    }

    func testSaveBackOverwritesAtomicallyAndLockIDChanges() throws {
        let out = file("doc.txt.otlock")
        try Locker.lock(data: Data("v1".utf8), originalName: "doc.txt", password: "pw", recoveryPublicKeyBase64: nil, output: out)
        let id1 = try Locker.lockID(of: out)
        try Locker.lock(data: Data("v2".utf8), originalName: "doc.txt", password: "pw", recoveryPublicKeyBase64: nil, output: out)
        XCTAssertEqual(String(decoding: try Locker.decrypt(out, password: "pw").data, as: UTF8.self), "v2")
        XCTAssertNotEqual(id1, try Locker.lockID(of: out))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("otlock") }
        XCTAssertEqual(names, ["doc.txt.otlock"])
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.contains("doc.txt 2") })
    }

    func testInMemoryRecoveryDecrypt() throws {
        let (key, pub) = RecoveryKey.generate()
        let out = file("r.otlock")
        try Locker.lock(data: Data("rec ✓".utf8), originalName: "r.txt", password: "forgotten", recoveryPublicKeyBase64: pub, output: out)
        let d = try Locker.decrypt(out, recoveryKey: key)
        XCTAssertEqual(d.originalName, "r.txt"); XCTAssertEqual(String(decoding: d.data, as: UTF8.self), "rec ✓")
        XCTAssertThrowsError(try Locker.decrypt(out, recoveryKey: RecoveryKey.generate().key)) { XCTAssertEqual($0 as? OpenTextError, .invalidRecoveryKey) }
        let noSlot = file("n.otlock")
        try Locker.lock(data: Data("x".utf8), originalName: "n.txt", password: "p", recoveryPublicKeyBase64: nil, output: noSlot)
        XCTAssertThrowsError(try Locker.decrypt(noSlot, recoveryKey: key)) { XCTAssertEqual($0 as? OpenTextError, .noRecoveryKeyConfigured) }
    }

    func testPreviouslyLockedFixtureStillDecrypts() throws {
        let f = file("old.otlock")
        try Data(base64Encoded: LegacyFixture.base64)!.write(to: f)
        let d = try Locker.decrypt(f, password: "legacy-pw")
        XCTAssertEqual(d.originalName, "legacy ✓.txt"); XCTAssertEqual(String(decoding: d.data, as: UTF8.self), "legacy body")
        XCTAssertEqual(try Locker.lockID(of: f).count, 64)
        XCTAssertEqual(try Locker.decrypt(f, recoveryKey: RecoveryKey(displayString: LegacyFixture.recovery)!).originalName, "legacy ✓.txt")
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

    func testSetupShownAndBackwardCompat() throws {
        XCTAssertFalse(OpenTextSettings.load().setupShown)
        try #"{"hotkey":"x","useTouchID":false}"#.write(to: OpenTextSettings.fileURL, atomically: true, encoding: .utf8)
        var s = OpenTextSettings.load()
        XCTAssertEqual(s.hotkey, "x"); XCTAssertFalse(s.useTouchID); XCTAssertFalse(s.setupShown)
        XCTAssertEqual(s.lastNewFileFormat, "md")
        s.setupShown = true; try s.save()
        XCTAssertTrue(OpenTextSettings.load().setupShown)
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

enum LegacyFixture {
    static let base64 = "T1RMSwEAAAImeyJjaXBoZXIiOiJBRVMtMjU2LUdDTSIsInBhc3N3b3JkIjp7Iml0ZXJhdGlvbnMiOjYwMDAwMCwia2RmIjoiUEJLREYyLUhNQUMtU0hBMjU2Iiwibm9uY2UiOiJiR2UzK2QxalBSWWRDTFBBIiwic2FsdCI6ImZXWU5uT2JTZGRNMm9Sa3lwRGNkc3c9PSIsIndyYXBwZWRLZXkiOiJFY1VpR0pUaEZWTWlGQ2puNGpqNUdHV3BkSHRaT1dIV1RoL3ZpREIxcUd4R1BsR2tzenlSNEFKZDl2NGVzSWJBIn0sInBheWxvYWROb25jZSI6ImdrUmpvVzE0L05MZUpQRWIiLCJyZWNvdmVyeSI6eyJlcGhlbWVyYWxQdWJsaWNLZXkiOiJ4dUpiMXFrRmlGaTlyZ1dxanN0NEc4eEc4ekQ1V2NwVnJ3Y0drekpHVjI4PSIsImluZm8iOiJPcGVuVGV4dCByZWNvdmVyeSB2MSIsImtkZiI6IlgyNTUxOS1IS0RGLVNIQTI1NiIsIm5vbmNlIjoiMzZtNkU4Um1UUnY3L2hpRSIsInNhbHQiOiJmamJFUWpKeTIrcFBWZGsrUHM1M3d3PT0iLCJ3cmFwcGVkS2V5IjoiSTdDbXNpRVloN3dGaEtlZVhRVUpUOG1TRkZZM29oRWFmdllEOC9BeExDcmJYMC9MNDZSNVZSZUdnUldEWDNJdiJ9LCJ2ZXJzaW9uIjoxfVWeM9BzLJLnuN816/LAag1M3oSTCBMSkH0ESSq7hkeIZUI0OQPOXY2URl7paw=="
    static let recovery = "YDXO-DI7R-NQ2L-U6AI-PL54-FH4Y-PFFV-CEJK-QL44-QN5T-ULD4-X6YN-INXQ"
}

final class SecurityFixTests: TempTestCase {
    func testConvertRefusesDirectoryAndWrongExtension() throws {
        let src = try write("a.txt", "hi")
        let folder = file("Docs"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for ow in [false, true] {
            var o = ConversionOptions(); o.overwrite = ow
            XCTAssertThrowsError(try engine.convert(src, to: .md, output: folder, options: o))
            let rc = try write(".zshrc", "precious")
            XCTAssertThrowsError(try engine.convert(src, to: .md, output: rc, options: o))
            XCTAssertEqual(try String(contentsOf: rc, encoding: .utf8), "precious")
        }
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertThrowsError(try engine.combinePDFs([src], output: folder))
    }

    func testOverwriteReplacesFileAndLeavesNoTemp() throws {
        let src = try write("a.txt", "new")
        let dest = try write("a.md", "old")
        var o = ConversionOptions(); o.overwrite = true
        _ = try engine.convert(src, to: .md, output: dest, options: o)
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "new")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasSuffix(".tmp") })
    }

    func testToolsPathRules() throws {
        let src = try write("a.txt", "hi")
        XCTAssertThrowsError(try OpenTextTools.call("convert", ["files": ["a.txt"], "to": "md"]))
        XCTAssertThrowsError(try OpenTextTools.call("convert", ["files": [src.path], "to": "md", "out": "rel.md"]))
        XCTAssertThrowsError(try OpenTextTools.call("convert", ["files": [src.path], "to": "md", "out": dir.path, "overwrite": true]))
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertNoThrow(try OpenTextTools.call("convert", ["files": [src.path], "to": "md"]))
        XCTAssertThrowsError(try OpenTextTools.call("convert", ["files": ["~/definitely-not-there.txt"], "to": "md"])) {
            XCTAssertTrue(($0 as? OpenTextError).map { if case .unreadable(let u) = $0 { return u.path.hasPrefix("/") && !u.path.contains("~") } else { return false } } ?? false)
        }
    }

    func testMCPLockIgnoresRecoveryKeyAndRemoveOriginal() throws {
        let defs = OpenTextTools.toolDefinitions()
        let lock = defs.first { $0["name"] as? String == "lock_file" }!
        let props = ((lock["inputSchema"] as! [String: Any])["properties"] as! [String: Any])
        XCTAssertNil(props["recovery_public_key"]); XCTAssertNil(props["remove_original"])
        let src = try write("k.txt", "x")
        let (_, pub) = RecoveryKey.generate()
        let r = try OpenTextTools.call("lock_file", ["file": src.path, "password": "pw", "recovery_public_key": pub, "remove_original": true])
        XCTAssertEqual(r["recovery"] as? Bool, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }

    func testMCPConvertIgnoresOverwrite() throws {
        let conv = OpenTextTools.toolDefinitions().first { $0["name"] as? String == "convert" }!
        XCTAssertNil(((conv["inputSchema"] as! [String: Any])["properties"] as! [String: Any])["overwrite"])
        let src = try write("o.txt", "new")
        let existing = try write("o.md", "keep me")
        let r = try OpenTextTools.call("convert", ["files": [src.path], "to": "md", "overwrite": true])
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep me")
        XCTAssertEqual((r["outputs"] as? [String])?.first, file("o 2.md").path)
        // The trusted CLI still honours it.
        _ = try OpenTextTools.call("convert", ["files": [src.path], "to": "md", "overwrite": true], trusted: true)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "new")
    }

    func testRemoveOriginalVerifiesAndTrashes() throws {
        let src = try write("t.txt", "trash me")
        let out = try Locker.lock(src, password: "pw", recoveryPublicKeyBase64: nil, removeOriginal: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertEqual(String(decoding: try Locker.decrypt(out, password: "pw").data, as: UTF8.self), "trash me")
        XCTAssertEqual(OpenTextError.originalNotRemoved(src), OpenTextError.originalNotRemoved(src))
        XCTAssertNotNil(OpenTextError.originalNotRemoved(src).errorDescription)
    }

    func testIterationBounds() throws {
        let out = file("i.otlock")
        try Locker.lock(data: Data("x".utf8), originalName: "i.txt", password: "pw", recoveryPublicKeyBase64: nil, output: out)
        let good = try Data(contentsOf: out)
        for (from, to) in [("600000", "599999"), ("600000", "10000001")] {
            var d = good
            let r = d.range(of: Data(from.utf8))!
            d.replaceSubrange(r, with: Data(to.utf8))
            if to.count != from.count { // header length field must match
                let len = d[5..<9].reduce(0) { ($0 << 8) | Int($1) } + (to.count - from.count)
                d.replaceSubrange(5..<9, with: [UInt8(len >> 24 & 255), UInt8(len >> 16 & 255), UInt8(len >> 8 & 255), UInt8(len & 255)])
            }
            let bad = file("bad.otlock"); try d.write(to: bad)
            XCTAssertThrowsError(try Locker.decrypt(bad, password: "pw")) { XCTAssertEqual($0 as? OpenTextError, .corruptLockedFile) }
        }
    }

    func testFingerprint() {
        let (_, pub) = RecoveryKey.generate()
        let f = RecoveryKey.fingerprint(publicKeyBase64: pub)!
        XCTAssertEqual(f.count, 19); XCTAssertEqual(f.filter { $0 == "-" }.count, 3)
        XCTAssertEqual(f, RecoveryKey.fingerprint(publicKeyBase64: pub))
        let zero = Data(count: 32).base64EncodedString()
        let h = SHA256.hash(data: Data(count: 32)).prefix(8).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(RecoveryKey.fingerprint(publicKeyBase64: zero)!.replacingOccurrences(of: "-", with: ""), h)
        XCTAssertNil(RecoveryKey.fingerprint(publicKeyBase64: "nope"))
    }

    func testMarkdownEscapesHTMLAndImages() {
        let html = MD.toHTML("<script>alert(1)</script>\n\nhello <b>x</b> ![the alt](https://evil.example/p.png) ![](file:///etc/passwd)")
        XCTAssertFalse(html.contains("<script")); XCTAssertFalse(html.contains("<b>")); XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("&lt;script&gt;")); XCTAssertTrue(html.contains("the alt"))
    }
}
