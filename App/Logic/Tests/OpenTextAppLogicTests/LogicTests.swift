import Foundation
import Testing
@testable import OpenTextAppLogic

@Suite struct HotkeyTests {
    @Test func defaultParses() throws {
        let s = try HotkeyParser.parse("ctrl+opt+n")
        #expect(s.keyCode == 45)
        #expect(s.modifiers == HotkeyParser.control | HotkeyParser.option)
    }
    @Test func aliasesCaseAndSpaces() throws {
        let s = try HotkeyParser.parse(" Control + ALT + Shift + Space ")
        #expect(s.keyCode == 49)
        #expect(s.modifiers == HotkeyParser.control | HotkeyParser.option | HotkeyParser.shift)
        #expect(try HotkeyParser.parse("cmd+f12").keyCode == 111)
    }
    @Test func formatRoundTrips() throws {
        for t in ["ctrl+opt+n", "shift+cmd+space", "ctrl+f5", "opt+1"] {
            #expect(HotkeyParser.format(try HotkeyParser.parse(t)) == t)
        }
        #expect(HotkeyParser.format(HotkeySpec(keyCode: 200, modifiers: 0x100)) == nil)
    }
    @Test func errors() {
        #expect(throws: HotkeyParseError.empty) { try HotkeyParser.parse("") }
        #expect(throws: HotkeyParseError.noModifier) { try HotkeyParser.parse("n") }
        #expect(throws: HotkeyParseError.noKey) { try HotkeyParser.parse("ctrl+opt") }
        #expect(throws: HotkeyParseError.multipleKeys) { try HotkeyParser.parse("ctrl+a+b") }
        #expect(throws: HotkeyParseError.unknownToken("banana")) { try HotkeyParser.parse("ctrl+banana") }
        #expect(throws: HotkeyParseError.self) { try HotkeyParser.parse("ctrl++n") }
    }
}

@Suite struct RouteTests {
    @Test func newRoute() throws {
        let r = try URLRouter.parse(URL(string: "opentext://new?format=md&dir=/Users/x/Desktop")!)
        #expect(r == .new(format: "md", dir: URL(fileURLWithPath: "/Users/x/Desktop")))
    }
    @Test func newDefaultsToMarkdownAndNoDir() throws {
        #expect(try URLRouter.parse(URL(string: "opentext://new")!) == .new(format: "md", dir: nil))
    }
    @Test func convertRoute() throws {
        let r = try URLRouter.parse(URL(string: "opentext://convert?to=pdf&file=/tmp/a%20b.md")!)
        #expect(r == .convert(to: "pdf", file: URL(fileURLWithPath: "/tmp/a b.md")))
    }
    @Test func roundTripAwkwardPaths() throws {
        let f = URL(fileURLWithPath: "/tmp/a & b+c=d #1?.md")
        #expect(try URLRouter.parse(URLRouter.convertURL(to: "jpeg", file: f)) == .convert(to: "jpg", file: f))
        #expect(try URLRouter.parse(URLRouter.lockURL(file: f)) == .lock(file: f))
        #expect(try URLRouter.parse(URLRouter.newURL(format: "txt", dir: f)) == .new(format: "txt", dir: f))
    }
    @Test func rejects() {
        #expect(throws: RouteError.notOurScheme) { try URLRouter.parse(URL(string: "https://x")!) }
        #expect(throws: RouteError.unknownAction("rm")) { try URLRouter.parse(URL(string: "opentext://rm")!) }
        #expect(throws: RouteError.badFormat("exe")) { try URLRouter.parse(URL(string: "opentext://new?format=exe")!) }
        #expect(throws: RouteError.badFormat("otlock")) { try URLRouter.parse(URL(string: "opentext://convert?to=otlock&file=/a")!) }
        #expect(throws: RouteError.missingParameter("file")) { try URLRouter.parse(URL(string: "opentext://convert?to=pdf")!) }
        #expect(throws: RouteError.badPath("relative/x.md")) { try URLRouter.parse(URL(string: "opentext://lock?file=relative/x.md")!) }
    }
    @Test func dotDotResolved() throws {
        let r = try URLRouter.parse(URL(string: "opentext://lock?file=/a/b/../c.md")!)
        #expect(r == .lock(file: URL(fileURLWithPath: "/a/c.md")))
    }
}

@Suite struct RoutingTests {
    @Test func kinds() {
        func k(_ n: String) -> FileKind { FileRouting.kind(for: URL(fileURLWithPath: "/x/\(n)")) }
        #expect(k("a.TXT") == .text)
        #expect(k("a.md") == .markdown)
        #expect(k("a.Markdown") == .markdown)
        #expect(k("a.pdf") == .pdf)
        #expect(k("a.JPEG") == .image)
        #expect(k("a.webp") == .image)
        #expect(k("a.otlock") == .locked)
        #expect(k("a.zip") == .unsupported)
        #expect(k("noext") == .unsupported)
    }
    @Test func finderTargets() {
        #expect(FileRouting.finderConvertTargets(fromExtension: "png") == ["jpg", "pdf"])
        #expect(FileRouting.finderConvertTargets(fromExtension: "md") == ["txt", "pdf"])
        #expect(FileRouting.finderConvertTargets(fromExtension: "zip").isEmpty)
    }
    @Test func passwordRules() {
        #expect(PasswordRules.validate(password: "short", confirm: "short") == .tooShort)
        #expect(PasswordRules.validate(password: "longenough", confirm: "different1") == .mismatch)
        #expect(PasswordRules.validate(password: "longenough", confirm: "longenough") == nil)
    }
}
