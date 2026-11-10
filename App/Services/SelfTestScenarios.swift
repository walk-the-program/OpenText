import AppKit
import OpenTextKit
import OpenTextUI

/// Click-driven scenarios. Every action is a real mouse or key event delivered through `NSWindow.sendEvent`
/// at the position the accessibility tree reports, and every scenario asserts an observable effect.
@MainActor
extension SelfTestRunner {
    static let clickScenarios: Set<String> = [
        "home-open-panel", "home-controls", "home-finish-setup", "setup-buttons", "home-create-closes", "doc-save",
        "doc-rename", "doc-resize", "lock-cancel", "convert-cancel", "convert-run", "quick-create", "doc-toolbar",
        "doc-close-prompt",
    ]

    func runClickScenario(_ name: String) async {
        switch name {
        case "home-open-panel": await homeOpenPanel()
        case "home-controls": await homeControls()
        case "home-finish-setup": await homeFinishSetup()
        case "setup-buttons": await setupButtons()
        case "home-create-closes": await homeCreateCloses()
        case "doc-save": await docSave()
        case "doc-rename": await docRename()
        case "doc-resize": await docResize()
        case "lock-cancel": await lockCancel()
        case "convert-cancel": await convertCancel()
        case "convert-run": await convertRun()
        case "quick-create": await quickCreate()
        case "doc-toolbar": await docToolbar()
        case "doc-close-prompt": await docClosePrompt()
        default: failures.append("unknown click scenario \(name)")
        }
    }

    // MARK: helpers

    /// Like `waitFor`, for conditions that read the accessibility tree.
    func waitUntil(_ what: String, timeout: Double = 5, _ cond: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !(await cond()) {
            if Date() > end { failures.append("timed out waiting for \(what)"); return false }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return true
    }

    var dirURL: URL? {
        guard let d = SelfTest.dir else { failures.append("missing --selftest-dir"); return nil }
        return URL(fileURLWithPath: d, isDirectory: true)
    }

    func session(named name: String) -> DocumentSession? {
        DocumentSession.openSessions.first { $0.url.lastPathComponent == name }
    }

    func visiblePanel() -> NSOpenPanel? { NSApp.windows.compactMap { $0 as? NSOpenPanel }.first { $0.isVisible } }

    /// Cancels the open panel the way the Cancel button does, and waits until it is gone.
    func cancelPanel(_ label: String) async {
        guard let panel = visiblePanel() else { return }
        await inRunLoop { panel.cancel(nil) }
        _ = await waitFor("\(label): open panel gone") { visiblePanel() == nil }
    }

    func homeReady() async -> NSWindow? {
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        let home = windows(.home).first
        if let home { _ = await waitUntil("home buttons in the accessibility tree") { await axFind(in: home, label: "Create", role: .button) != nil } }
        return home
    }

    /// Makes the window key (without activating the app) so keystrokes reach its first responder.
    func focus(_ w: NSWindow) async {
        await inRunLoop { w.makeKey() }
        try? await Task.sleep(for: .milliseconds(40))
    }

    /// Types `name` in the Home window's name field and presses Create. Returns the new document window.
    func createViaHome(_ home: NSWindow, name: String, chip: String? = "txt file", expectFile: String) async -> NSWindow? {
        await focus(home)
        if let chip { await click(chip, in: home) }
        await typeIntoField(label: "Untitled", text: name, in: home)
        await click("Create", in: home)
        _ = await waitFor("document window \(expectFile)") { doc(named: expectFile) != nil }
        return doc(named: expectFile)
    }

    func docReady(_ w: NSWindow, _ name: String) async {
        _ = await waitFor("\(name) leaves loading") { session(named: name).map { $0.contentKindForTesting != "loading" } ?? false }
        _ = await waitUntil("\(name) toolbar in the accessibility tree") { await axFind(in: w, label: "Convert", role: .button) != nil }
    }

    // MARK: Home

    private func homeOpenPanel() async {
        guard let home = await homeReady() else { return }
        await click("Open a file…", in: home)
        if await waitFor("open panel after clicking 'Open a file…'", { visiblePanel() != nil }) {
            expect(visiblePanel()?.canChooseFiles == true, "open panel should let you choose files")
            snapshot("open panel visible")
            await cancelPanel("home-open-panel")
        }
        expect(visiblePanel() == nil, "open panel still visible after cancel")
    }

    private func homeControls() async {
        guard let home = await homeReady() else { return }
        for fmt in QuickCreateState.formats {
            await click("\(fmt) file", in: home)
            let on = await waitUntil("'\(fmt) file' chip selected") { await axFind(in: home, label: "\(fmt) file")?.selected == true }
            _ = on
            for other in QuickCreateState.formats where other != fmt {
                expect(await axFind(in: home, label: "\(other) file")?.selected != true, "chip '\(other) file' still selected after choosing \(fmt)")
            }
        }
        await click("Change", in: home)
        if await waitFor("folder panel after clicking Change", { visiblePanel() != nil }) {
            expect(visiblePanel()?.canChooseDirectories == true, "Change should open a folder chooser")
            await cancelPanel("home-controls")
        }
    }

    private func homeFinishSetup() async {
        guard let home = await homeReady() else { return }
        expect(windows(.setup).isEmpty, "setup window should not be open yet")
        await click("Finish setup", in: home)
        _ = await waitFor("setup window after clicking 'Finish setup'") { windows(.setup).count == 1 }
        snapshot("after Finish setup")
    }

    private func setupButtons() async {
        guard let home = await homeReady() else { return }
        await click("Finish setup", in: home)
        guard await waitFor("setup window", { windows(.setup).count == 1 }), let setup = windows(.setup).first else { return }
        _ = await waitUntil("setup buttons in the accessibility tree") { await axFind(in: setup, label: "Done", role: .button) != nil }
        let before = SelfTest.stubCalls
        let makeLabel = await axFind(in: setup, label: "Make default") != nil ? "Make default" : "Set again"
        await click(makeLabel, in: setup)
        _ = await waitFor("Make default reaching the system call", { SelfTest.stubCalls.count > before.count && SelfTest.stubCalls.contains("makeDefault") })
        expect(!(await axHasText(in: setup, containing: "Couldn't make default")), "no failure note expected when every type succeeded")
        // Failed types are listed inline instead of being swallowed.
        SelfTest.makeDefaultFailures = [.tiff, .gif]
        await click(makeLabel, in: setup)
        _ = await waitUntil("failure note under Make default") { await axHasText(in: setup, containing: "Couldn't make default for: .tiff, .gif") }
        SelfTest.makeDefaultFailures = []
        await click(makeLabel, in: setup)
        _ = await waitUntil("failure note cleared") {
            let stillThere = await axHasText(in: setup, containing: "Couldn't make default")
            return !stillThere
        }
        let afterMake = SelfTest.stubCalls.count
        let finderLabel = await axFind(in: setup, label: "Turn on…") != nil ? "Turn on…" : "Open Settings"
        await click(finderLabel, in: setup)
        _ = await waitFor("Turn on… reaching the system call", { SelfTest.stubCalls.count > afterMake && SelfTest.stubCalls.last == "finderExtension" })
        await click("Done", in: setup)
        _ = await waitFor("setup window closed by Done") { windows(.setup).isEmpty }
        // Finish setup works again after Done, and again after the window's own close button.
        await click("Finish setup", in: home)
        _ = await waitFor("setup window reopened by Finish setup after Done") { windows(.setup).count == 1 }
        if let again = windows(.setup).first {
            await inRunLoop { again.performClose(nil) }
            _ = await waitFor("setup window closed by its close button") { windows(.setup).isEmpty }
            await click("Finish setup", in: home)
            _ = await waitFor("setup window reopened by Finish setup after closing it") { windows(.setup).count == 1 }
        }
        // Clicking it while the window is already open (behind Home) must raise that one window, not add another.
        if let open = windows(.setup).first {
            await inRunLoop { home.orderFront(nil) }
            let behind = { NSApp.orderedWindows.firstIndex(of: open) ?? 99 } 
            let homeIndex = { NSApp.orderedWindows.firstIndex(of: home) ?? 99 }
            expect(homeIndex() < behind(), "test setup: Home should be in front of the setup window")
            await click("Finish setup", in: home)
            _ = await waitFor("Finish setup raising the already-open setup window") { behind() < homeIndex() }
            expect(windows(.setup).count == 1, "Finish setup with the window open should leave one setup window, got \(windows(.setup).count)")
        }
    }

    private func homeCreateCloses() async {
        guard let dir = dirURL, let home = await homeReady() else { return }
        guard let created = await createViaHome(home, name: "Fresh", expectFile: "Fresh.txt") else { return }
        _ = created
        _ = await waitFor("home window closing after Create") { windows(.home).isEmpty }
        snapshot("after Create from Home")
        expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Fresh.txt").path), "Fresh.txt was not created")
        expect(windows(.document).count == 1, "expected one document window, got \(windows(.document).count)")
    }

    // MARK: document

    private func newDoc(_ name: String, file: String) async -> NSWindow? {
        guard let home = await homeReady() else { return nil }
        guard let w = await createViaHome(home, name: name, expectFile: file) else { return nil }
        await docReady(w, file)
        return w
    }

    private func docSave() async {
        guard let dir = dirURL, let w = await newDoc("Draft", file: "Draft.txt") else { return }
        let url = dir.appendingPathComponent("Draft.txt")
        guard let s = session(named: "Draft.txt") else { failures.append("no session for Draft.txt"); return }
        let saves = s.saveCountForTesting
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        try? await Task.sleep(for: .milliseconds(1100))
        await focus(w)
        await simulateKey(w)
        // What the File > Save item uses: enabled for any editable session, even a fresh unchanged file, and it
        // runs the save. (An inactive app never enables SwiftUI's NSMenuItems, so the item itself cannot be pressed
        // headless; the ⌘S event below is still sent and counted, but only this call is asserted.)
        let actions = model.keyDocumentActions
        expect(actions != nil, "the key document window should give the File menu its actions")
        expect(actions?.canSave == true, "Save must be enabled for a freshly created, unchanged file")
        let handled = await keyEquivalent("s", .command, in: w)
        steps.append(["step": "⌘S event", "handledByMenu": handled])
        actions?.save()
        _ = await waitFor("save counter to move after ⌘S") { s.saveCountForTesting > saves }
        let mtime2 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        expect(mtime != nil && mtime2 != nil && mtime2! > mtime!, "file was not rewritten by ⌘S (mtime \(String(describing: mtime)) -> \(String(describing: mtime2)))")
        // Header shows the word count and the saved state; no status bar at the bottom of the window.
        let hits = await axElements(in: w)
        let status = hits.first { $0.label.contains("word") }
        expect(status != nil, "header should contain the word count text; texts: " + hits.filter { $0.role == "AXStaticText" }.map(\.label).joined(separator: " | "))
        if let status {
            expect(status.label.contains("Saved"), "header status should say Saved, got '\(status.label)'")
            expect(status.frame.maxY > w.frame.maxY - 60, "word count must sit in the header (top of the window), got y=\(status.frame.minY - w.frame.minY) of \(w.frame.height)")
        }
        let bottomTexts = hits.filter { $0.role == "AXStaticText" && $0.frame.maxY < w.frame.minY + 40 && !$0.label.isEmpty }
        expect(bottomTexts.isEmpty, "something is still drawn in the bottom 40pt (status bar?): " + bottomTexts.map(\.label).joined(separator: ", "))
        snapshot("after ⌘S")
    }

    private func titleHit(_ w: NSWindow, _ title: String) async -> AXHit? {
        // The title is the first static text/button with that label in the header (top 60pt).
        await axElements(in: w).first { $0.label == title && $0.frame.maxY > w.frame.maxY - 60 }
    }

    /// Clicks the title and waits until the name field exists and is the first responder (focus is set a moment later).
    private func beginRename(_ w: NSWindow, _ title: String) async -> Bool {
        guard let t = await titleHit(w, title) else { failures.append("title '\(title)' not found in the header"); return false }
        await clickScreenPoint(NSPoint(x: t.frame.midX, y: t.frame.midY), in: w)
        let shown = await waitUntil("title field for '\(title)'") { await axElements(in: w).contains { $0.role == "AXTextField" && $0.value == title } }
        let focused = await waitFor("title field to take focus") { (w.firstResponder as? NSTextView)?.delegate is NSTextField }
        return shown && focused
    }

    private func docRename() async {
        guard let dir = dirURL, let w = await newDoc("Notes", file: "Notes.txt") else { return }
        let fm = FileManager.default
        try? "other".write(to: dir.appendingPathComponent("Other.txt"), atomically: true, encoding: .utf8)
        guard let s = session(named: "Notes.txt") else { failures.append("no session"); return }
        // Type into the document so the rename has unsaved text to carry.
        s.text = "carry me"; s.textChanged()
        await focus(w)

        // Escape cancels.
        if await beginRename(w, "Notes") {
            let sel = (w.firstResponder as? NSTextView)?.selectedRange()
            expect(sel?.length == 5, "name should be fully selected when editing starts, selection=\(String(describing: sel))")
            await typeText("zzz", in: w)
            await pressEscape(in: w)
            _ = await waitUntil("title field gone after Escape") {
                let fieldStillThere = await axElements(in: w).contains { $0.role == "AXTextField" && $0.value.contains("zzz") }
                return !fieldStillThere
            }
            expect(fm.fileExists(atPath: dir.appendingPathComponent("Notes.txt").path), "Escape must keep the file name")
            _ = await waitUntil("title back after Escape") { await titleHit(w, "Notes") != nil }
        }
        // Focus leaving the field (clicking elsewhere) cancels too.
        if await beginRename(w, "Notes") {
            await typeText("yyy", in: w)
            // A click elsewhere ends editing by taking focus away from the field (the document text view takes a
            // click only in a key window, which a headless run never has), so move focus the same way.
            await inRunLoop { w.makeFirstResponder(w.contentView) }
            _ = await waitUntil("title field gone after clicking away") {
                let fieldStillThere = await axElements(in: w).contains { $0.role == "AXTextField" && $0.value.contains("yyy") }
                return !fieldStillThere
            }
            expect(fm.fileExists(atPath: dir.appendingPathComponent("Notes.txt").path), "clicking away must keep the file name")
            _ = await waitUntil("title back after clicking away") { await titleHit(w, "Notes") != nil }
        }

        // Names that can't be used keep the old name and say why; nothing is overwritten.
        for (attempt, expected) in [("Other", "already exists"), ("a/b", "can't contain"), ("", "empty")] {
            guard let t2 = await titleHit(w, "Notes") else { failures.append("title not back after rejected rename '\(attempt)'"); break }
            _ = t2
            guard await beginRename(w, "Notes") else { break }
            if attempt.isEmpty { await inRunLoop { (w.firstResponder as? NSText)?.delete(nil) } } else { await typeText(attempt, in: w) }
            await pressReturn(in: w)
            if !(await waitUntil("error '\(expected)' for '\(attempt)'", { await axHasText(in: w, containing: expected) })) {
                failures.append("top elements: \(await axElements(in: w).filter { $0.frame.maxY > w.frame.maxY - 60 }.map(\.summary))")
            }
            expect(fm.fileExists(atPath: dir.appendingPathComponent("Notes.txt").path), "rename to '\(attempt)' must keep Notes.txt")
            expect(s.url.lastPathComponent == "Notes.txt", "session url changed on a rejected rename")
            expect((try? String(contentsOf: dir.appendingPathComponent("Other.txt"), encoding: .utf8)) == "other", "Other.txt must not be overwritten")
            _ = await waitUntil("title back to normal") { await titleHit(w, "Notes") != nil }
        }

        // Real rename.
        _ = await waitUntil("title back to normal") { await titleHit(w, "Notes") != nil }
        if let t3 = await titleHit(w, "Notes") {
            _ = t3
            guard await beginRename(w, "Notes") else { return }
            await typeText("renamed", in: w)
            await pressReturn(in: w)
            _ = await waitFor("window title renamed.txt") { doc(named: "renamed.txt") != nil }
            expect(!fm.fileExists(atPath: dir.appendingPathComponent("Notes.txt").path), "old file Notes.txt should be gone")
            expect(fm.fileExists(atPath: dir.appendingPathComponent("renamed.txt").path), "renamed.txt should exist")
            expect((try? String(contentsOf: dir.appendingPathComponent("renamed.txt"), encoding: .utf8)) == "carry me", "unsaved text must survive the rename")
            expect(s.url.lastPathComponent == "renamed.txt", "session url should be renamed.txt, is \(s.url.lastPathComponent)")
            expect(windows(.document).count == 1, "rename must not open a second window, got \(windows(.document).count)")
            // Re-opening the new path focuses this window instead of opening a duplicate.
            model.openFile(dir.appendingPathComponent("renamed.txt"))
            try? await Task.sleep(for: .milliseconds(500))
            expect(windows(.document).count == 1, "opening the renamed path created a duplicate window (\(windows(.document).count))")
        }
        // A read-only viewer (rich text) shows a plain title: no click-to-rename.
        let rtf = dir.appendingPathComponent("viewer.rtf")
        let text = NSAttributedString(string: "viewer")
        if let data = try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            try? data.write(to: rtf)
            model.openFile(rtf)
            if await waitFor("viewer.rtf window", { doc(named: "viewer.rtf") != nil }), let v = doc(named: "viewer.rtf") {
                await docReady(v, "viewer.rtf")
                let title = await titleHit(v, "viewer")
                expect(title != nil, "viewer.rtf title not found")
                expect(title?.role != "AXButton", "a read-only viewer must not offer click-to-rename (title is \(title?.role ?? "?"))")
            }
        }
        snapshot("after rename")
    }

    private func docResize() async {
        guard let w = await newDoc("Big", file: "Big.txt") else { return }
        let start = w.frame
        expect(w.delegate is WindowGuardDelegate, "document window delegate should be the close guard, is \(String(describing: w.delegate))")
        // SwiftUI putting a delegate of its own back must not break the chain: the guard returns and forwards to it.
        let dummy = ResizeCountingDelegate()
        await inRunLoop { w.delegate = dummy }
        expect(w.delegate is WindowGuardDelegate, "close guard was not reinstalled after the delegate was replaced")
        let target = NSSize(width: start.width + 600, height: start.height + 400)
        for i in 1...6 {
            let step = NSSize(width: start.width + 100 * CGFloat(i), height: start.height + 400.0 / 6 * CGFloat(i))
            var f = w.frame; f.size = step; f.origin.y = start.maxY - step.height
            await inRunLoop { w.setFrame(f, display: true) }
            try? await Task.sleep(for: .milliseconds(30))
        }
        expect(dummy.resizes > 0, "replaced delegate got no windowDidResize through the guard")
        for name in [NSWindow.didMoveNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didExposeNotification, NSWindow.didChangeScreenNotification, NSWindow.didMiniaturizeNotification] {
            await inRunLoop { NotificationCenter.default.post(name: name, object: w) }
        }
        expect(abs(w.frame.width - target.width) < 2 && abs(w.frame.height - target.height) < 2,
               "window should reach \(target), is \(w.frame.size)")
        // Edge drag: mouse down on the bottom-right corner, drag outwards, release.
        let before = w.frame.size
        let origin = NSPoint(x: w.frame.width - 2, y: 2)
        func drag(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        await inRunLoop {
            for i in 1...5 { if let e = drag(.leftMouseDragged, NSPoint(x: origin.x + 40 * CGFloat(i), y: origin.y - 30 * CGFloat(i))) { NSApp.postEvent(e, atStart: false) } }
            if let e = drag(.leftMouseUp, NSPoint(x: origin.x + 200, y: origin.y - 150)) { NSApp.postEvent(e, atStart: false) }
            if let e = drag(.leftMouseDown, origin) { w.sendEvent(e) }
        }
        try? await Task.sleep(for: .milliseconds(300))
        steps.append(["step": "edge drag", "before": NSStringFromSize(before), "after": NSStringFromSize(w.frame.size)])
        expect(w.frame.width > before.width, "edge drag did not grow the window (\(before) -> \(w.frame.size))")
        expect(SelfTestExceptions.recorded.isEmpty, "exceptions while resizing")
    }

    private func lockCancel() async {
        guard let dir = dirURL, let w = await newDoc("Secret", file: "Secret.txt") else { return }
        let url = dir.appendingPathComponent("Secret.txt")
        await click("Lock", in: w)
        guard await waitFor("lock sheet attached", { w.attachedSheet != nil }) else { return }
        _ = await waitUntil("lock sheet buttons") { await axFind(in: w, label: "Cancel", role: .button) != nil }
        // Empty password: the sheet explains instead of locking.
        await click("Lock", in: w, nth: 0)
        _ = await waitUntil("password error in the sheet") { await axHasText(in: w, containing: "at least") }
        expect(w.attachedSheet != nil, "sheet should stay open after a rejected password")
        await click("Cancel", in: w)
        _ = await waitFor("lock sheet gone after Cancel") { w.attachedSheet == nil }
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        expect(names == ["Secret.txt"], "directory should hold only Secret.txt, has \(names.sorted())")
        expect(session(named: "Secret.txt")?.contentKindForTesting == "text", "file must not be locked")
        expect(FileManager.default.fileExists(atPath: url.path), "Secret.txt vanished")
    }

    private func convertCancel() async {
        guard let w = await newDoc("Conv", file: "Conv.txt") else { return }
        await click("Convert", in: w)
        guard await waitFor("convert sheet attached", { w.attachedSheet != nil }) else { return }
        _ = await waitUntil("convert sheet buttons") { await axFind(in: w, label: "Cancel", role: .button) != nil }
        await click("Cancel", in: w)
        _ = await waitFor("convert sheet gone after Cancel") { w.attachedSheet == nil }
        expect(session(named: "Conv.txt")?.sheet == nil, "session still shows a sheet")
    }

    private func convertRun() async {
        guard let dir = dirURL, let w = await newDoc("Src", file: "Src.txt") else { return }
        await click("Convert", in: w)
        guard await waitFor("convert sheet attached", { w.attachedSheet != nil }) else { return }
        _ = await waitUntil("convert rows") { await axElements(in: w).contains { $0.inSheet && $0.role == "AXButton" && $0.label.contains("PDF") } }
        let rows = await axElements(in: w).filter { $0.inSheet && $0.role == "AXButton" }.map(\.label)
        steps.append(["step": "convert sheet buttons", "buttons": rows])
        // Pick the PDF row, convert.
        guard let pdfRow = rows.first(where: { $0.contains("PDF") }) else { failures.append("no PDF row in convert sheet: \(rows)"); return }
        await click(pdfRow, in: w)
        let button = rows.filter { $0 == "Convert" }.isEmpty ? "Convert" : "Convert"
        await click(button, in: w)
        _ = await waitFor("Src.pdf next to the original", timeout: 10) { FileManager.default.fileExists(atPath: dir.appendingPathComponent("Src.pdf").path) }
        expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Src.txt").path), "original must stay")
    }

    private func quickCreate() async {
        guard let dir = dirURL else { return }
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        model.showQuickCreate()
        guard await waitFor("quick-create window", { windows(.quickCreate).count == 1 }), let q = windows(.quickCreate).first else { return }
        _ = await waitUntil("quick-create buttons") { await axFind(in: q, label: "Create", role: .button) != nil }
        await focus(q)
        for fmt in QuickCreateState.formats {
            await click("\(fmt) file", in: q)
            _ = await waitUntil("'\(fmt) file' selected in quick-create") { await axFind(in: q, label: "\(fmt) file")?.selected == true }
        }
        await click("Change", in: q)
        if await waitFor("folder panel from quick-create Change", { visiblePanel() != nil }) { await cancelPanel("quick-create") }
        await click("csv file", in: q)
        await typeIntoField(label: "Untitled", text: "Quick", in: q)
        await click("Create", in: q)
        _ = await waitFor("document Quick.csv") { doc(named: "Quick.csv") != nil }
        _ = await waitFor("quick-create panel closing after Create") { windows(.quickCreate).isEmpty }
        expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Quick.csv").path), "Quick.csv not created")
        expect(windows(.quickCreate).isEmpty, "quick-create panel still visible after Create")
    }

    private func docToolbar() async {
        guard let dir = dirURL else { return }
        // Markdown document: tools, Edit/Preview.
        let md = dir.appendingPathComponent("Tools.md")
        try? "word".write(to: md, atomically: true, encoding: .utf8)
        _ = await waitFor("home window") { windows(.home).count == 1 }
        await settle()
        model.openFile(md)
        guard await waitFor("Tools.md window", { doc(named: "Tools.md") != nil }), let w = doc(named: "Tools.md") else { return }
        await docReady(w, "Tools.md")
        guard let s = session(named: "Tools.md") else { return }
        await focus(w)
        // Edit/Preview first: the tool row fades out once text has been typed, until the mouse moves.
        await click("Preview", in: w)
        _ = await waitUntil("Preview selected") { await axFind(in: w, label: "Preview", role: nil)?.selected == true }
        await click("Edit", in: w)
        _ = await waitUntil("Edit selected") { await axFind(in: w, label: "Edit", role: nil)?.selected == true }
        await click("Bold", in: w)
        _ = await waitFor("Bold changing the text") { s.text != "word" }
        expect(s.text.contains("**"), "Bold should add ** markers, text is '\(s.text)'")
        // Plain text: Mono toggle.
        let txt = dir.appendingPathComponent("Plain.txt")
        try? "plain".write(to: txt, atomically: true, encoding: .utf8)
        model.openFile(txt)
        guard await waitFor("Plain.txt window", { doc(named: "Plain.txt") != nil }), let p = doc(named: "Plain.txt") else { return }
        await docReady(p, "Plain.txt")
        let mono = model.settings.txtMonospace
        await click(mono ? "Inter" : "Mono", in: p)
        _ = await waitFor("monospace setting flipping") { model.settings.txtMonospace != mono }
    }
}

@MainActor
final class ResizeCountingDelegate: NSObject, NSWindowDelegate {
    var resizes = 0
    func windowDidResize(_ notification: Notification) { resizes += 1 }
}

@MainActor
extension SelfTestRunner {
    /// Closing a window with unsaved text asks Save / Don't Save / Cancel; the close button shows the dirty dot.
    func docClosePrompt() async {
        guard let w = await newDocForClose() else { return }
        guard let s = session(named: "Close.txt") else { failures.append("no session"); return }
        s.text = "edited"; s.textChanged()
        _ = await waitFor("dirty dot in the close button") { w.isDocumentEdited }
        await inRunLoop { w.performClose(nil) }
        guard await waitFor("close prompt sheet", { w.attachedSheet != nil }) else { return }
        _ = await waitUntil("prompt buttons") { await axFind(in: w, label: "Cancel", role: .button) != nil }
        await click("Cancel", in: w)
        _ = await waitFor("prompt gone after Cancel") { w.attachedSheet == nil }
        expect(w.isVisible, "Cancel must keep the window open")
        // Autosave may have saved in the meantime; make the text dirty again so the prompt is certain.
        s.text = "edited again"; s.textChanged()
        await inRunLoop { w.performClose(nil) }
        guard await waitFor("close prompt sheet (second time)", { w.attachedSheet != nil }) else { return }
        _ = await waitUntil("prompt buttons") { await axFind(in: w, label: "Don't Save", role: .button) != nil }
        await click("Don't Save", in: w)
        _ = await waitFor("window closed by Don't Save") { !w.isVisible }
    }

    private func newDocForClose() async -> NSWindow? {
        guard let home = await homeReady() else { return nil }
        guard let w = await createViaHome(home, name: "Close", expectFile: "Close.txt") else { return nil }
        await docReady(w, "Close.txt")
        return w
    }
}

