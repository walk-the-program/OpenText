import AppKit
import UniformTypeIdentifiers
import ObjectiveC
import OpenTextKit

/// Headless runtime self-test. Enabled only by `--selftest-out <path.json>`; scripts/selftest.sh drives it.
/// In this mode the app is an accessory process, every window is parked far off-screen and transparent the moment
/// it exists, nothing activates the app, and no system state (hotkey, Keychain token, recents) is touched.
enum SelfTest {
    static let enabled = arg("--selftest-out") != nil
    static let outPath = arg("--selftest-out")
    static let script = arg("--selftest-script")
    static let file = arg("--selftest-file")
    static let dir = arg("--selftest-dir")
    /// System-touching calls (default apps, Finder extension settings) are recorded here instead of made.
    nonisolated(unsafe) static var stubCalls: [String] = []
    /// Home's recent files in self-test mode (the real list is never read or written).
    nonisolated(unsafe) static var recents: [URL] = []
    static let refreshHome = Notification.Name("OpenTextSelfTestRefreshHome")
    /// What the single-file picker "chooses" in self-test mode (no panel is shown).
    nonisolated(unsafe) static var pickFileURL: URL?
    static func stub(_ name: String) { stubCalls.append(name) }
    /// What the stubbed makeDefault reports as refused; scenarios change it to test the failure note.
    nonisolated(unsafe) static var makeDefaultFailures: [UTType] = []

    static func arg(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// Called from App.init, before any window exists.
    @MainActor static func prepare() {
        guard enabled else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
        SelfTestExceptions.install()
        SelfTestKeyWindow.install()
        let nc = NotificationCenter.default
        for name in [NSWindow.didBecomeMainNotification, NSWindow.didBecomeKeyNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { n in
                guard let w = n.object as? NSWindow else { return }
                MainActor.assumeIsolated { park(w) }
            }
        }
        // AppKit pulls windows back onto a screen just before showing them. Answer "stay where you are, far
        // off-screen" instead, and park (alpha 0, no mouse) at the same moment, before the first display.
        if let m = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.constrainFrameRect(_:to:))) {
            let block: @convention(block) (NSWindow, NSRect, NSScreen?) -> NSRect = { w, rect, _ in
                MainActor.assumeIsolated {
                    park(w)
                    return NSRect(origin: NSPoint(x: parkX, y: rect.origin.y), size: rect.size)
                }
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        // Backstop for windows that exist before any notification fires.
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated {
                // `open -j` hides the app after launch; hidden apps report no visible windows.
                if let app = NSApp, app.isHidden { app.unhideWithoutActivation() }
                NSApp?.windows.forEach(park)
            }
        }
    }

    @MainActor static var parkX: CGFloat { (NSScreen.screens.map(\.frame.maxX).max() ?? 0) + 20000 }

    @MainActor static func park(_ w: NSWindow) {
        if w.frame.origin.x < parkX - 1 { w.setFrameOrigin(NSPoint(x: parkX, y: w.frame.origin.y)) }
        if w.alphaValue != 0 { w.alphaValue = 0 }
        if !w.ignoresMouseEvents { w.ignoresMouseEvents = true }
        if w.hasShadow { w.hasShadow = false }
    }

    @MainActor static func start() {
        guard enabled, let script, let out = outPath else { return }
        NSApp.unhideWithoutActivation()      // `open -j` launches hidden; hidden apps report no visible windows
        let runner = SelfTestRunner(scenario: script, out: out)
        runner.watchdog()
        Task { @MainActor in await runner.run() }
    }
}

@MainActor
final class SelfTestRunner {
    enum Kind: String { case bridge, home, quickCreate = "quick-create", setup, notice, document, other }

    let scenario: String
    let out: String
    var steps: [[String: Any]] = []
    var failures: [String] = []
    var model: AppModel { AppModel.shared }

    init(scenario: String, out: String) { self.scenario = scenario; self.out = out }

    // MARK: window inspection

    static func kind(_ w: NSWindow) -> Kind {
        let id = w.identifier?.rawValue ?? ""
        if id.contains("bridge") { return .bridge }
        if id.contains("quick-create") { return .quickCreate }
        if id.contains("home") { return .home }
        if id.contains("setup") { return .setup }
        if id.contains("notice") { return .notice }
        if w is NSPanel || w.className.contains("StatusBar") { return .other }
        return .document
    }

    func windows(_ kind: Kind? = nil, visibleOnly: Bool = true) -> [NSWindow] {
        NSApp.windows.filter { w in
            let k = Self.kind(w)
            return (kind == nil ? k != .bridge : k == kind) && (!visibleOnly || w.isVisible)
        }
    }

    func doc(named name: String) -> NSWindow? { windows(.document).first { $0.title == name } }

    func snapshot(_ step: String) {
        let list = NSApp.windows.map { w -> [String: Any] in
            ["id": w.identifier?.rawValue ?? "", "title": w.title, "visible": w.isVisible,
             "kind": Self.kind(w).rawValue, "x": Int(w.frame.origin.x), "alpha": w.alphaValue, "parkedOffScreen": !NSScreen.screens.contains { $0.frame.intersects(w.frame) }]
        }
        steps.append(["step": step, "appHidden": NSApp.isHidden, "policy": NSApp.activationPolicy().rawValue, "windows": list])
    }

    func expect(_ ok: Bool, _ message: @autoclosure () -> String) { if !ok { failures.append(message()) } }

    /// Polls the main run loop every 20 ms until the condition holds (or the timeout passes). No fixed delays.
    func waitFor(_ what: String, timeout: Double = 5, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { failures.append("timed out waiting for \(what)"); return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// Negative assertions ("no other window appeared") need the app idle first: the bridge is attached, the
    /// queued work has run, and the run loop has turned a few times.
    func settle() async {
        _ = await waitFor("bridge attached and queue drained") { model.isReady }
        for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func closeAll() async {
        windows().forEach { $0.close() }
        _ = await waitFor("all windows closed") { windows().isEmpty }
    }

    func watchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [self] in
            MainActor.assumeIsolated { failures.append("scenario watchdog (40 s)"); snapshot("watchdog"); finish() }
        }
    }

    func finish() -> Never {
        failures += SelfTestExceptions.recorded.map { "exception: \($0)" }
        if !failures.isEmpty && AXReader.sawNoWindows {
            failures.insert("AX-UNAVAILABLE: the system accessibility tree lists no OpenText windows (not on the active Space)", at: 0)
        }
        let result: [String: Any] = ["scenario": scenario, "steps": steps, "pass": failures.isEmpty, "failures": failures,
                                     "stubCalls": SelfTest.stubCalls]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: out), options: .atomic)
        }
        exit(failures.isEmpty ? 0 : 1)
    }

    // MARK: scenarios

    func run() async {
        switch scenario {
        case "launch-plain": await launchPlain()
        case "launch-with-file": await launchWithFile()
        case "create-opens": await createOpens()
        case "reopen": await reopen()
        case "warm-open": await warmOpen()
        case "open-rtf": await openRTF()
        case "open-html": await openHTML()
        case "open-rtfd": await openRTFD()
        case "first-run-setup": await setupScenario(expectSetup: true)
        case "second-run-no-setup": await setupScenario(expectSetup: false)
        case _ where Self.clickScenarios.contains(scenario): await runClickScenario(scenario)
        default: failures.append("unknown scenario \(scenario)")
        }
        finish()
    }

    private func expectHomeOnly(_ label: String) {
        expect(windows(.home).count == 1, "\(label): expected exactly one home window, got \(windows(.home).count)")
        expect(windows(.document).isEmpty, "\(label): unexpected document windows")
    }

    private func launchPlain() async {
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        snapshot("after launch")
        expectHomeOnly("launch-plain")
        expect(!NSApp.windows.filter { Self.kind($0) == .bridge }.isEmpty, "bridge window missing")
        expect(!model.launchedWithFiles, "launchedWithFiles should be false")
    }

    private func launchWithFile() async {
        guard let file = SelfTest.file else { failures.append("missing --selftest-file"); return }
        let name = URL(fileURLWithPath: file).lastPathComponent
        _ = await waitFor("document window \(name)") { doc(named: name) != nil }
        await settle()
        snapshot("after launch with file")
        expect(windows(.document).count == 1, "expected exactly one document window, got \(windows(.document).count)")
        expect(windows(.home).isEmpty, "home window must not appear")
        expect(model.launchedWithFiles, "launchedWithFiles should be true")
    }

    /// Running app gets a file from outside (Finder/`open`): exactly one window, home stays.
    private func warmOpen() async {
        guard let file = SelfTest.file else { failures.append("missing --selftest-file"); return }
        let name = URL(fileURLWithPath: file).lastPathComponent
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        FileManager.default.createFile(atPath: out + ".ready", contents: nil)
        _ = await waitFor("document window \(name)", timeout: 10) { doc(named: name) != nil }
        await settle()
        snapshot("after external open")
        expect(windows(.document).count == 1, "expected exactly one document window, got \(windows(.document).count)")
        expect(windows(.home).count == 1, "home should still be the only home window")
        expect(!model.launchedWithFiles, "launchedWithFiles should be false")
    }

    private func createdFile(in dir: URL, before: Set<String>) -> String? {
        let now = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        return now.subtracting(before).first
    }

    private func create(in dir: URL, name: String, label: String) async {
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        model.createNew(format: "txt", name: name, in: dir)
        guard let created = createdFile(in: dir, before: before) else { failures.append("\(label): no file created"); return }
        _ = await waitFor("\(label): document window \(created)") { doc(named: created) != nil }
        snapshot("\(label) created \(created)")
    }

    private func createOpens() async {
        guard let d = SelfTest.dir else { failures.append("missing --selftest-dir"); return }
        let dir = URL(fileURLWithPath: d, isDirectory: true)
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        await create(in: dir, name: "First", label: "create from launch state")
        await closeAll()
        snapshot("all closed")
        model.showQuickCreate()
        _ = await waitFor("quick-create window") { windows(.quickCreate).count == 1 }
        snapshot("quick create shown")
        windows(.quickCreate).forEach { $0.close() }       // what QuickCreateHost.dismiss() does before creating
        await create(in: dir, name: "Second", label: "create after quick create")
        await closeAll()
        model.showHome()
        _ = await waitFor("home window after showHome") { windows(.home).count == 1 }
        snapshot("home after showHome")
        expectHomeOnly("showHome with no windows")
    }

    private func reopen() async {
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        await closeAll()
        snapshot("all closed")
        guard let delegate = AppDelegate.instance else { failures.append("no AppDelegate instance"); return }
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        _ = await waitFor("home window after reopen") { windows(.home).count == 1 }
        snapshot("after reopen")
        expectHomeOnly("reopen")
    }

    /// Writes a sample file with `write`, opens it through AppModel.openFile and expects `kind` from the session.
    private func openSample(named name: String, expecting kind: String, write: (URL) throws -> Void) async {
        guard let d = SelfTest.dir else { failures.append("missing --selftest-dir"); return }
        let url = URL(fileURLWithPath: d, isDirectory: true).appendingPathComponent(name)
        do { try write(url) } catch { failures.append("could not write \(name): \(error)"); return }
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        model.openFile(url)
        _ = await waitFor("document window \(name)") { doc(named: name) != nil }
        let session = { DocumentSession.openSessions.first { $0.url.lastPathComponent == name } }
        _ = await waitFor("\(name) leaves loading") { session().map { $0.contentKindForTesting != "loading" } ?? false }
        let got = session()?.contentKindForTesting ?? "no session"
        expect(got == kind, "\(name): expected content kind \(kind), got \(got)")
        snapshot("\(name) opened (\(got))")
    }

    private func richText() -> NSAttributedString {
        NSAttributedString(string: "Hello rich text", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
    }

    private func openRTF() async {
        await openSample(named: "sample.rtf", expecting: "richText") { url in
            let t = richText()
            try t.data(from: NSRange(location: 0, length: t.length),
                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: url)
        }
    }

    private func openHTML() async {
        await openSample(named: "sample.html", expecting: "html") { url in
            try "<html><body><h1>Hello</h1></body></html>".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func openRTFD() async {
        await openSample(named: "sample.rtfd", expecting: "richText") { url in
            let t = richText()
            let wrapper = try t.fileWrapper(from: NSRange(location: 0, length: t.length),
                                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        }
    }

    private func setupScenario(expectSetup: Bool) async {
        _ = await waitFor("home window") { windows(.home).count == 1 }
        if expectSetup { _ = await waitFor("setup window") { windows(.setup).count == 1 } }
        await settle()
        snapshot("after launch")
        expect(windows(.home).count == 1, "expected one home window")
        expect(windows(.setup).count == (expectSetup ? 1 : 0), "setup windows: expected \(expectSetup ? 1 : 0), got \(windows(.setup).count)")
        expect(windows(.document).isEmpty, "unexpected document windows")
        expect(OpenTextSettings.load().setupShown, "setupShown should be saved as true")
    }
}
