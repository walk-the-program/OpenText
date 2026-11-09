import AppKit
import Network
import Testing
import WebKit
@testable import OpenTextUI

@MainActor
struct HTMLViewTests {
    @Test func ruleJSONBlocksEverything() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(HTMLSafety.blockAllRuleJSON.utf8)) as! [[String: Any]]
        #expect(obj.count == 1)
        #expect((obj[0]["trigger"] as! [String: String])["url-filter"] == ".*")
        #expect((obj[0]["action"] as! [String: String])["type"] == "block")
    }

    @Test func navigationPolicy() {
        let blank = URL(string: "about:blank")
        #expect(HTMLSafety.shouldAllow(url: blank, isUserClick: false) == .allow)
        #expect(HTMLSafety.shouldAllow(url: nil, isUserClick: false) == .allow)
        // After the initial load, nothing loads on its own (meta refresh, scripted redirects, form posts).
        #expect(HTMLSafety.shouldAllow(url: blank, isUserClick: false, initialLoadDone: true) == .cancel)
        #expect(HTMLSafety.shouldAllow(url: URL(string: "https://example.com/"), isUserClick: false) == .cancel)
        #expect(HTMLSafety.shouldAllow(url: URL(string: "file:///etc/hosts"), isUserClick: false) == .cancel)
        // Clicks: only web and mail links, and only to the outside browser.
        #expect(HTMLSafety.shouldAllow(url: URL(string: "https://example.com/"), isUserClick: true) == .openExternally)
        #expect(HTMLSafety.shouldAllow(url: URL(string: "HTTP://example.com/"), isUserClick: true) == .openExternally)
        #expect(HTMLSafety.shouldAllow(url: URL(string: "mailto:a@b.co"), isUserClick: true) == .openExternally)
        #expect(HTMLSafety.shouldAllow(url: URL(string: "file:///etc/hosts"), isUserClick: true) == .cancel)
        #expect(HTMLSafety.shouldAllow(url: URL(string: "javascript:alert(1)"), isUserClick: true) == .cancel)
        #expect(HTMLSafety.shouldAllow(url: URL(string: "x-apple.systempreferences:"), isUserClick: true) == .cancel)
        #expect(HTMLSafety.shouldAllow(url: blank, isUserClick: true) == .cancel)
    }

    @Test func charsetDetection() {
        let l1 = "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=ISO-8859-1\">café".data(using: .isoLatin1)!
        #expect(HTMLSafety.declaredCharset(in: l1) == "iso-8859-1")
        #expect(HTMLSafety.decode(l1).hasSuffix("café"))
        #expect(HTMLSafety.decode("<p>héllo</p>".data(using: .utf8)!) == "<p>héllo</p>")
        // No declaration, not UTF-8: Latin-1 fallback.
        #expect(HTMLSafety.decode("<p>caf\u{E9}</p>".data(using: .isoLatin1)!) == "<p>café</p>")
        // BOM wins.
        #expect(HTMLSafety.decode(Data([0xEF, 0xBB, 0xBF]) + Data("ok".utf8)) == "ok")
        // Shift-JIS declared.
        let sjis = "<meta charset=shift_jis>日本語".data(using: .shiftJIS)!
        #expect(HTMLSafety.decode(sjis).hasSuffix("日本語"))
        #expect(HTMLSafety.declaredCharset(in: Data("<p>none</p>".utf8)) == nil)
    }

    @Test func plainTextDropsScriptsAndTags() {
        let t = HTMLSafety.plainText(fromHTML: "<html><head><title>x</title></head><body><script>evil()</script><h1>Title</h1><p>One &amp; two</p><style>p{}</style></body></html>")
        #expect(t == "Title\nOne & two")
    }

    /// Loads `html` off-screen against a loopback listener; returns (connections seen, page title, nav requests).
    private func probe(protected: Bool) async throws -> (hits: Int, title: String?, nav: NavRecorder, base: String) {
        _ = NSApplication.shared
        let hits = Hits()
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { conn in hits.add(); conn.cancel() }
        let ready = AsyncStream<UInt16> { c in
            listener.stateUpdateHandler = { if case .ready = $0 { c.yield(listener.port!.rawValue); c.finish() } }
        }
        listener.start(queue: .global())
        var port: UInt16 = 0
        for await p in ready { port = p }
        defer { listener.cancel() }
        let base = "http://127.0.0.1:\(port)"
        let html = """
        <html><head><link rel="stylesheet" href="\(base)/a.css"><script src="\(base)/a.js"></script></head>
        <body><img src="\(base)/a.png"><iframe src="\(base)/frame"></iframe>
        <script>document.title='ran'; new Image().src='\(base)/js'</script><p>Hello</p></body></html>
        """
        let nav = NavRecorder()
        let web: WKWebView
        if protected {
            web = SafeWebView.make(rules: try #require(await SafeWebView.compileRules()), delegate: nav)
        } else {
            web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            web.navigationDelegate = nav
        }
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = web
        web.loadHTMLString(html, baseURL: nil)
        // Wait for the load (web content process start-up can be slow under load), then give stray fetches time to land.
        let limit = Date().addingTimeInterval(15)
        while !nav.finished && Date() < limit { try await Task.sleep(for: .milliseconds(50)) }
        let end = Date().addingTimeInterval(2)
        while Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        return (hits.count, web.title, nav, base)
    }

    /// Control: an ordinary web view does reach the listener and run the script, so the test can fail.
    @Test func controlUnprotectedViewFetches() async throws {
        let r = try await probe(protected: false)
        #expect(r.hits > 0)
        #expect(r.title == "ran")
    }

    /// The block-all rules must not stop the page itself from drawing: snapshot the locked-down view.
    @Test func rendersUnderBlockAllRules() async throws {
        _ = NSApplication.shared
        let nav = NavRecorder()
        let web = SafeWebView.make(rules: try #require(await SafeWebView.compileRules()), delegate: nav)
        web.frame = NSRect(x: 0, y: 0, width: 700, height: 360)
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 700, height: 360), styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = web
        web.loadHTMLString("<body style='font:20px Georgia;margin:40px'><h1>Quarterly notes</h1><p>Rendered <b>HTML</b>, not source.</p><img src='https://example.com/x.png' width=100 height=40 alt='blocked image'></body>", baseURL: nil)
        let limit = Date().addingTimeInterval(15)
        while !nav.finished && Date() < limit { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(500))
        let image = try await web.takeSnapshot(configuration: nil)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        var dark = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) { for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.brightnessComponent < 0.5 { dark += 1 }
        } }
        try? rep.representation(using: .png, properties: [:])?.write(to: Snap.outDir.appendingPathComponent("html-web-locked.png"))
        #expect(dark > 200)
    }

    /// Real WebKit, off-screen, against a loopback listener: nothing the page references may reach it.
    @Test func webKitFetchesNothing() async throws {
        let r = try await probe(protected: true)
        #expect(r.nav.finished)
        #expect(r.hits == 0)
        #expect(r.nav.requested.first == "about:blank")
        #expect(r.title != "ran")
    }
}

final class Hits: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@MainActor
final class NavRecorder: NSObject, WKNavigationDelegate {
    var requested = [String]()
    var finished = false
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        requested.append(navigationAction.request.url?.absoluteString ?? "nil")
        let d = HTMLSafety.shouldAllow(url: navigationAction.request.url, isUserClick: false, initialLoadDone: finished)
        decisionHandler(d == .allow ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
}
