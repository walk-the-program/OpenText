import Foundation
import Testing
@testable import OpenTextAppLogic

private func makeHome() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("otl-\(UUID().uuidString)")
    let home = root.appendingPathComponent("home")
    for d in ["Documents", "Desktop", "Library/Preferences", "outside"] {
        try FileManager.default.createDirectory(at: (d == "outside" ? root : home).appendingPathComponent(d), withIntermediateDirectories: true)
    }
    return home
}

@Suite struct TokenTests {
    @Test func rotateReadMatch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tok-\(UUID().uuidString)")
        let t = try TokenStore.rotate(in: dir)
        #expect(t.count == 64)
        #expect(TokenStore.read(in: dir) == t)
        let perms = try FileManager.default.attributesOfItem(atPath: TokenStore.tokenFile(in: dir).path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        let t2 = try TokenStore.rotate(in: dir)
        #expect(t2 != t)
        #expect(TokenStore.matches(t2, expected: TokenStore.read(in: dir)))
        #expect(!TokenStore.matches(t, expected: t2))
    }
    @Test func matchRejects() {
        #expect(!TokenStore.matches(nil, expected: "abc"))
        #expect(!TokenStore.matches("abc", expected: nil))
        #expect(!TokenStore.matches("", expected: ""))
        #expect(!TokenStore.matches("abcd", expected: "abc"))
        #expect(TokenStore.matches("abc", expected: "abc"))
    }
    @Test func tokenInURL() throws {
        let f = URL(fileURLWithPath: "/Users/x/a b.md")
        let u = URLRouter.convertURL(to: "pdf", file: f, token: "deadbeef")
        #expect(URLRouter.token(in: u) == "deadbeef")
        #expect(try URLRouter.parse(u) == .convert(to: "pdf", file: f))
        #expect(URLRouter.token(in: URLRouter.lockURL(file: f)) == nil)
        #expect(URLRouter.token(in: URLRouter.newURL(format: "md", dir: nil, token: "t")) == "t")
    }
}

@Suite struct PathPolicyTests {
    @Test func insideHome() throws {
        let home = try makeHome()
        #expect(PathPolicy.isAllowed(home.appendingPathComponent("Desktop"), home: home))
        #expect(PathPolicy.isAllowed(home.appendingPathComponent("Documents/new.md"), home: home))   // not yet existing
        #expect(PathPolicy.isAllowed(home, home: home))
    }
    @Test func outsideHomeAndLibrary() throws {
        let home = try makeHome()
        #expect(!PathPolicy.isAllowed(URL(fileURLWithPath: "/etc/hosts"), home: home))
        #expect(!PathPolicy.isAllowed(home.deletingLastPathComponent().appendingPathComponent("outside"), home: home))
        #expect(!PathPolicy.isAllowed(home.appendingPathComponent("Library"), home: home))
        #expect(!PathPolicy.isAllowed(home.appendingPathComponent("Library/Preferences/x.plist"), home: home))
        #expect(!PathPolicy.isAllowed(home.appendingPathComponent("library/Preferences"), home: home))
        #expect(!PathPolicy.isAllowed(home.appendingPathComponent("Documents/../Library/Preferences/x"), home: home))
        #expect(!PathPolicy.isAllowed(URL(fileURLWithPath: home.path + "-evil/x"), home: home))
    }
    @Test func symlinks() throws {
        let home = try makeHome()
        let root = home.deletingLastPathComponent()
        // link inside home pointing outside home
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Documents/escape"), withDestinationURL: root.appendingPathComponent("outside"))
        #expect(!PathPolicy.isAllowed(home.appendingPathComponent("Documents/escape/new.md"), home: home))
        // link inside home pointing into ~/Library
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Desktop/lib"), withDestinationURL: home.appendingPathComponent("Library/Preferences"))
        #expect(!PathPolicy.isAllowed(home.appendingPathComponent("Desktop/lib/x.plist"), home: home))
        // link outside pointing into home is fine
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside/in"), withDestinationURL: home.appendingPathComponent("Documents"))
        #expect(PathPolicy.isAllowed(root.appendingPathComponent("outside/in/f.md"), home: home))
    }
    @Test func guardResolvesRoutes() throws {
        let home = try makeHome()
        let ok = try RouteGuard.validate(.new(format: "md", dir: home.appendingPathComponent("Desktop")), home: home)
        #expect(ok == .new(format: "md", dir: PathPolicy.resolve(home.appendingPathComponent("Desktop"))))
        #expect(throws: RouteError.self) { try RouteGuard.validate(.lock(file: URL(fileURLWithPath: "/etc/hosts")), home: home) }
        #expect(throws: RouteError.self) {
            try RouteGuard.validate(.convert(to: "pdf", file: home.appendingPathComponent("Library/a.md")), home: home)
        }
    }
}

@Suite struct ConfirmationTests {
    let folder = URL(fileURLWithPath: "/Users/x/Desktop")
    @Test func signedRunsDirectly() {
        #expect(ConfirmationPolicy.decide(.new(format: "md", dir: nil), tokenValid: true, defaultFolder: folder) == .run)
        #expect(ConfirmationPolicy.decide(.lock(file: URL(fileURLWithPath: "/Users/x/a.md")), tokenValid: true, defaultFolder: folder) == .run)
    }
    @Test func unsignedAsksNamingActionFileAndFolder() {
        guard case .confirm(let t, let d) = ConfirmationPolicy.decide(.new(format: "md", dir: nil), tokenValid: false, defaultFolder: folder) else { Issue.record("no confirm"); return }
        #expect(t == "Create Untitled.md in Desktop?")
        #expect(d.contains("/Users/x/Desktop"))
        guard case .confirm(let t2, _) = ConfirmationPolicy.decide(.convert(to: "pdf", file: URL(fileURLWithPath: "/Users/x/Documents/r.md")), tokenValid: false, defaultFolder: folder) else { Issue.record("no confirm"); return }
        #expect(t2 == "Convert r.md to pdf in Documents?")
        guard case .confirm(let t3, _) = ConfirmationPolicy.decide(.lock(file: URL(fileURLWithPath: "/Users/x/Documents/r.md")), tokenValid: false, defaultFolder: folder) else { Issue.record("no confirm"); return }
        #expect(t3 == "Lock r.md in Documents?")
    }
    @Test func oneDialogAtATime() {
        var g = OneAtATime()
        let first = g.begin(), second = g.begin()
        g.end()
        let third = g.begin()
        #expect(first && !second && third)
    }
}

@Suite struct SaveSafetyTests {
    @Test func changeCheck() {
        let d = Date()
        #expect(!FileChangeCheck.hasChanged(recorded: d, current: d))
        #expect(FileChangeCheck.hasChanged(recorded: d, current: d.addingTimeInterval(0.001)))
        #expect(FileChangeCheck.hasChanged(recorded: d, current: nil))
        #expect(!FileChangeCheck.hasChanged(recorded: nil, current: d))
    }
    @Test func encodingRoundTrip() throws {
        let latin = Data([0x63, 0x61, 0x66, 0xE9])          // "café" in Latin-1, invalid UTF-8
        let (s, enc) = try #require(TextCoding.decode(latin))
        #expect(s == "café" && enc == .isoLatin1)
        #expect(TextCoding.encode(s + "!", as: enc).0 == Data([0x63, 0x61, 0x66, 0xE9, 0x21]))
        let (d2, e2) = TextCoding.encode("snow ☃", as: .isoLatin1)
        #expect(e2 == .utf8 && String(data: d2, encoding: .utf8) == "snow ☃")
        let u16 = "hi".data(using: .utf16)!
        #expect(TextCoding.decode(u16)?.1 == .utf16)
        #expect(TextCoding.decode(Data("plain".utf8))?.1 == .utf8)
    }
    @Test func pinPolicy() {
        #expect(PinPolicy.evaluate(pinned: nil, current: nil) == .createNew)
        #expect(PinPolicy.evaluate(pinned: nil, current: "K") == .adopt("K"))
        #expect(PinPolicy.evaluate(pinned: "K", current: nil) == .restore("K"))
        #expect(PinPolicy.evaluate(pinned: "K", current: "K") == .ok("K"))
        #expect(PinPolicy.evaluate(pinned: "K", current: "X") == .mismatch(pinned: "K", current: "X"))
    }
}
