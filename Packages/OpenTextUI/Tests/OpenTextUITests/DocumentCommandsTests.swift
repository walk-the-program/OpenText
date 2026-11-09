import Foundation
import Testing
@testable import OpenTextUI

@Suite @MainActor struct DocumentCommandsTests {
    @Test func performInvokesHandler() {
        let c = DocumentCommands()
        var hits: [DocumentCommands.Command] = []
        c.register(kind: .text, handlers: [.bold: { hits.append(.bold) }, .heading(2): { hits.append(.heading(2)) }])
        #expect(c.kind == .text)
        #expect(c.isAvailable(.bold))
        #expect(c.perform(.bold))
        #expect(c.perform(.heading(2)))
        #expect(hits == [.bold, .heading(2)])
    }

    @Test func unavailableCommandIsNoOp() {
        let c = DocumentCommands()
        #expect(!c.isAvailable(.zoomIn))
        #expect(!c.perform(.zoomIn))
        c.register(kind: .pdf, handlers: [.zoomIn: {}])
        c.unregister()
        #expect(c.kind == nil)
        #expect(!c.perform(.zoomIn))
    }

    @Test func registerReplacesHandlers() {
        let c = DocumentCommands()
        c.register(kind: .text, handlers: [.bold: {}, .togglePreview: {}])
        c.register(kind: .text, handlers: [.togglePreview: {}])
        #expect(!c.isAvailable(.bold))
        #expect(c.isAvailable(.togglePreview))
    }

    @Test func dirtyTransitions() {
        let c = DocumentCommands()
        var events: [Bool] = []
        c.onDirtyChange = { events.append($0) }
        #expect(!c.isDirty)
        c.markDirty(); c.markDirty()
        #expect(c.isDirty)
        c.markSaved(); c.markSaved()
        #expect(!c.isDirty)
        c.markDirty()
        #expect(events == [true, false, true])
    }

    @Test func markSavedNotifiesView() {
        let c = DocumentCommands()
        var saved = 0
        c.register(kind: .image, handlers: [:], onSaved: { saved += 1 })
        c.markDirty(); c.markSaved()
        #expect(saved == 1)
    }
}

@Suite struct MarkdownCommandHooksTests {
    @Test func italicWrapsAndToggles() {
        let e = MarkdownFormatting.edit(.italic, in: "a word b", selection: NSRange(location: 2, length: 4))
        #expect(e.replacement == "*word*")
        let off = MarkdownFormatting.edit(.italic, in: "a *word* b", selection: NSRange(location: 3, length: 4))
        #expect(off.replacement == "word")
    }

    @Test func headingLevelSetsAndRemoves() {
        #expect(MarkdownFormatting.edit(.headingLevel(2), in: "Title", selection: NSRange(location: 0, length: 0)).replacement == "## Title")
        #expect(MarkdownFormatting.edit(.headingLevel(3), in: "# Title", selection: NSRange(location: 0, length: 0)).replacement == "### Title")
        #expect(MarkdownFormatting.edit(.headingLevel(1), in: "# Title", selection: NSRange(location: 0, length: 0)).replacement == "Title")
    }
}
