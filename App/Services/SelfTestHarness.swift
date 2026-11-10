import AppKit
import ApplicationServices
import ObjectiveC

/// Any exception AppKit catches (or that ends the process) fails the self-test run.
enum SelfTestExceptions {
    nonisolated(unsafe) private static var list: [String] = []
    private static let lock = NSLock()

    static var recorded: [String] { lock.lock(); defer { lock.unlock() }; return list }

    static func record(_ e: NSException) {
        lock.lock(); defer { lock.unlock() }
        let top = e.callStackSymbols.prefix(4).joined(separator: " | ")
        list.append("\(e.name.rawValue): \(e.reason ?? "?") [\(top)]")
    }

    static func install() {
        NSSetUncaughtExceptionHandler { e in
            SelfTestExceptions.record(e)
            // The process is about to die: leave a failing result behind.
            if let out = SelfTest.outPath {
                let result: [String: Any] = ["scenario": SelfTest.script ?? "", "pass": false, "steps": [],
                                             "failures": SelfTestExceptions.recorded.map { "uncaught exception: \($0)" }]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]) {
                    try? data.write(to: URL(fileURLWithPath: out), options: .atomic)
                }
            }
        }
        // NSApplication catches exceptions thrown while handling events and reports them here, then carries on.
        if let m = class_getInstanceMethod(NSApplication.self, NSSelectorFromString("reportException:")) {
            let block: @convention(block) (AnyObject, NSException) -> Void = { _, e in record(e) }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
    }
}

/// One accessibility element, read through the system accessibility API (AXUIElement) against our own process.
/// SwiftUI builds its accessibility tree only for such a client; plain `accessibilityChildren()` stays empty.
struct AXHit: Sendable {
    let role: String
    let label: String
    let value: String
    let frame: NSRect          // Cocoa screen coordinates (bottom-left origin)
    let window: NSRect         // frame of the AXWindow it lives in
    let inSheet: Bool
    let selected: Bool?

    var summary: String { "\(role) '\(label)'\(value.isEmpty ? "" : " =\(value)") \(NSStringFromRect(frame))\(inSheet ? " [sheet]" : "")\(selected == true ? " [selected]" : "")" }
}

enum AXReader {
    nonisolated(unsafe) static var diag = ""
    /// True when the last read found no windows at all (windows not on the active Space).
    nonisolated(unsafe) static var sawNoWindows = false
    /// Reads the whole tree. Must run on the main thread: for our own process the call evaluates SwiftUI view
    /// bodies on the calling thread, and those are main-actor isolated.
    @MainActor
    static func snapshot(primaryHeight: CGFloat) async -> [AXHit] {
        let pid = getpid()
        return await { () -> [AXHit] in
            func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
                var v: CFTypeRef?
                return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
            }
            func str(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
            func frame(_ e: AXUIElement) -> NSRect? {
                guard let p = attr(e, "AXPosition"), let s = attr(e, "AXSize") else { return nil }
                var pt = CGPoint.zero, sz = CGSize.zero
                guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
                return NSRect(x: pt.x, y: primaryHeight - pt.y - sz.height, width: sz.width, height: sz.height)
            }
            var out: [AXHit] = []
            var diagLines: [String] = []
            func walk(_ e: AXUIElement, window: NSRect, inSheet: Bool, depth: Int) {
                guard depth < 40, out.count < 2000 else { return }
                let role = str(e, "AXRole")
                var win = window, sheet = inSheet
                if role == "AXWindow" {
                    var pv: CFTypeRef?, sv: CFTypeRef?
                    let pe = AXUIElementCopyAttributeValue(e, "AXPosition" as CFString, &pv)
                    let se = AXUIElementCopyAttributeValue(e, "AXSize" as CFString, &sv)
                    diagLines.append("win '\(str(e, "AXTitle"))' pos=\(pe.rawValue) size=\(se.rawValue)")
                    if let f = frame(e) { win = f }
                }
                if role == "AXSheet" { sheet = true }
                if role != "AXApplication", role != "AXWindow", let f = frame(e) {
                    var label = str(e, "AXTitle")
                    if label.isEmpty { label = str(e, "AXDescription") }
                    let value = (attr(e, "AXValue") as? String) ?? ""
                    if label.isEmpty && role == "AXStaticText" { label = value }
                    out.append(AXHit(role: role, label: label, value: value, frame: f, window: win, inSheet: sheet,
                                     selected: attr(e, "AXSelected") as? Bool))
                }
                for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, window: win, inSheet: sheet, depth: depth + 1) }
            }
            let app = AXUIElementCreateApplication(pid)
            let kids = (attr(app, "AXChildren") as? [AXUIElement]) ?? []
            let wins = (attr(app, "AXWindows") as? [AXUIElement]) ?? []
            diagLines.append("app children \(kids.map { str($0, "AXRole") }) windows \(wins.count)")
            walk(app, window: .zero, inSheet: false, depth: 0)
            AXReader.diag = diagLines.joined(separator: "; ")
            AXReader.sawNoWindows = wins.isEmpty
            return out
        }()
    }
}

@MainActor
extension SelfTestRunner {
    // MARK: accessibility tree

    /// Every accessibility element in the window (including a sheet attached to it).
    func axElements(in window: NSWindow) async -> [AXHit] {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let wf = window.frame
        return await AXReader.snapshot(primaryHeight: primary).filter { hit in
            // Occasionally the system cannot report an AXWindow's own frame; then fall back to where the element is.
            if hit.window == .zero { return wf.insetBy(dx: -2, dy: -2).contains(hit.frame) }
            return abs(hit.window.minX - wf.minX) < 2 && abs(hit.window.maxY - wf.maxY) < 2 && abs(hit.window.width - wf.width) < 2
        }
    }

    func axFind(in window: NSWindow, label: String, role: NSAccessibility.Role? = nil) async -> AXHit? {
        await axElements(in: window).first { $0.label == label && (role == nil || $0.role == role!.rawValue) }
    }

    /// True when a static text or field value in the window contains `text`.
    func axHasText(in window: NSWindow, containing text: String) async -> Bool {
        await axElements(in: window).contains { $0.label.contains(text) || $0.value.contains(text) }
    }

    func dumpAX(_ window: NSWindow, _ step: String) async {
        steps.append(["step": "ax \(step)", "elements": await axElements(in: window).map(\.summary)])
    }

    // MARK: running risky AppKit calls

    /// Runs `work` as its own run-loop callout, so an exception thrown inside is caught by AppKit (and recorded)
    /// instead of tearing down this task. Returns once it ran or an exception was recorded.
    @discardableResult
    func inRunLoop(_ work: @escaping @MainActor () -> Void) async -> Bool {
        var done = false
        let before = SelfTestExceptions.recorded.count
        DispatchQueue.main.async { MainActor.assumeIsolated { work(); done = true } }
        let end = Date().addingTimeInterval(3)
        while !done && SelfTestExceptions.recorded.count == before && Date() < end {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return done
    }

    // MARK: mouse

    private func mouseEvent(_ type: NSEvent.EventType, at p: NSPoint, in w: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
    }

    /// Real left mouse down + up at a screen point, delivered through the window's own `sendEvent`
    /// (AppKit/SwiftUI hit-testing, button tracking), the same path a user's click takes.
    func clickScreenPoint(_ screenPoint: NSPoint, in w: NSWindow) async {
        await clickAtWindowPoint(w.convertPoint(fromScreen: screenPoint), in: w)
    }

    func clickAtWindowPoint(_ p: NSPoint, in w: NSWindow) async {
        guard let down = mouseEvent(.leftMouseDown, at: p, in: w), let up = mouseEvent(.leftMouseUp, at: p, in: w) else { return }
        await inRunLoop { w.sendEvent(down) }
        try? await Task.sleep(for: .milliseconds(60))      // a real click holds the button for a moment
        await inRunLoop { w.sendEvent(up) }
        try? await Task.sleep(for: .milliseconds(80))
    }

    /// Clicks the centre of the element with this accessibility label. Records a failure when it cannot be found.
    /// Matches buttons by default; pass `role: nil` for any element.
    @discardableResult
    func click(_ label: String, role: NSAccessibility.Role? = .button, in w: NSWindow?, nth: Int = 0) async -> Bool {
        guard let w else { failures.append("click '\(label)': no window"); return false }
        let all = await axElements(in: w)
        let hits = all.filter { $0.label == label && (role == nil || $0.role == role!.rawValue) && $0.frame.width > 0 }
            .sorted { $0.inSheet && !$1.inSheet }
        guard hits.indices.contains(nth) else {
            let everything = await AXReader.snapshot(primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            failures.append("click '\(label)': not found in \(w.identifier?.rawValue ?? w.title) frame \(NSStringFromRect(w.frame)); "
                            + "tree has \(everything.count) elements in windows \(Set(everything.map { NSStringFromRect($0.window) })); AX windows: \(AXReader.diag); buttons: "
                            + all.filter { $0.role == "AXButton" }.map(\.label).joined(separator: ", "))
            return false
        }
        let f = hits[nth].frame
        let point = NSPoint(x: f.midX, y: f.midY)
        // A sheet is its own window above the parent: deliver to it when the point falls inside it.
        let target = [w.attachedSheet, w].compactMap { $0 }.first { $0.frame.contains(point) } ?? w
        await clickScreenPoint(point, in: target)
        return true
    }

    // MARK: keyboard

    private func keyEvent(_ type: NSEvent.EventType, chars: String, code: UInt16, flags: NSEvent.ModifierFlags, in w: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars.lowercased(),
                         isARepeat: false, keyCode: code)
    }

    /// Key equivalent (e.g. "s" + [.command]) through the main menu, as a keypress no view claims is handled.
    @discardableResult
    func keyEquivalent(_ key: String, _ flags: NSEvent.ModifierFlags = .command, in w: NSWindow) async -> Bool {
        guard let e = keyEvent(.keyDown, chars: key, code: 0, flags: flags, in: w) else { return false }
        var handled = false
        await inRunLoop {
            handled = NSApp.mainMenu?.performKeyEquivalent(with: e) ?? false
            if !handled { handled = w.performKeyEquivalent(with: e) }
        }
        try? await Task.sleep(for: .milliseconds(100))
        return handled
    }

    /// Types characters into whatever is first responder in the window, as key events ("\r" is Return).
    func typeText(_ text: String, in w: NSWindow) async {
        for ch in text {
            let s = String(ch)
            let code: UInt16 = ch == "\r" ? 36 : 0
            if let d = keyEvent(.keyDown, chars: s, code: code, flags: [], in: w),
               let u = keyEvent(.keyUp, chars: s, code: code, flags: [], in: w) {
                await inRunLoop { w.sendEvent(d) }
                await inRunLoop { w.sendEvent(u) }
            }
        }
        try? await Task.sleep(for: .milliseconds(80))
    }

    func pressReturn(in w: NSWindow) async { await typeText("\r", in: w) }

    func pressEscape(in w: NSWindow) async {
        if let d = keyEvent(.keyDown, chars: "\u{1b}", code: 53, flags: [], in: w),
           let u = keyEvent(.keyUp, chars: "\u{1b}", code: 53, flags: [], in: w) {
            await inRunLoop { w.sendEvent(d) }
            await inRunLoop { w.sendEvent(u) }
        }
        try? await Task.sleep(for: .milliseconds(80))
    }

    /// Replaces the text of the focused text field: select all, then type.
    func replaceText(with text: String, in w: NSWindow) async {
        await inRunLoop { (w.firstResponder as? NSText)?.selectAll(nil) }
        await typeText(text, in: w)
    }

    /// Clicks a text field (found by accessibility label or current value), then replaces its content by typing.
    func typeIntoField(label: String, text: String, in w: NSWindow) async {
        let hits = await axElements(in: w)
        guard let hit = hits.first(where: { ($0.role == "AXTextField" || $0.role == "AXTextArea") && ($0.label == label || $0.value == label) }) else {
            failures.append("text field '\(label)' not found; fields: " + hits.filter { $0.role == "AXTextField" }.map(\.summary).joined(separator: "; "))
            return
        }
        await clickScreenPoint(NSPoint(x: hit.frame.midX, y: hit.frame.midY), in: w)
        await replaceText(with: text, in: w)
    }
}
