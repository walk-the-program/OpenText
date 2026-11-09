import Foundation
import Network
import XCTest
@testable import OpenTextKit

final class NoLoadTests: TempTestCase {
    final class Hits: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func add() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func testHTMLConversionsFetchNothing() throws {
        let hits = Hits()
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { c in hits.add(); c.cancel() }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: .global())
        XCTAssertEqual(ready.wait(timeout: .now() + 5), .success)
        defer { listener.cancel() }
        let base = "http://127.0.0.1:\(listener.port!.rawValue)"
        let page = "<html><head><link rel=\"stylesheet\" href=\"\(base)/a.css\"></head><body><p>Visible words.</p><img src=\"\(base)/x.png\"></body></html>"
        let html = try write("page.html", page)
        for target in [DocFormat.txt, .md, .rtf, .docx, .pdf] {
            let out = try engine.convert(html, to: target)[0]
            if target == .txt { XCTAssertTrue(try String(contentsOf: out, encoding: .utf8).contains("Visible words.")) }
        }
        // md -> docx goes through generated HTML.
        let md = try write("note.md", "# Hi\n\n![x](\(base)/m.png)\n\nBody text.\n")
        _ = try engine.convert(md, to: .docx)
        _ = try engine.convert(md, to: .pdf)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(hits.count, 0)
    }
}
