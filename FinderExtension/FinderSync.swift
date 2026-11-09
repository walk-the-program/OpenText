import Cocoa
import FinderSync
import OpenTextAppLogic
import OpenTextKit

/// Sandboxed: never writes files. Every action opens an opentext:// URL and the app does the work.
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // "/" covers every folder, including the Desktop.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "")
        switch menuKind {
        case .contextualMenuForContainer:
            menu.addItem(item("New Text File", #selector(newTxt(_:))))
            menu.addItem(item("New Markdown File", #selector(newMd(_:))))
        case .contextualMenuForItems:
            let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
            guard let first = urls.first else { return nil }
            let engine = ConversionEngine()
            let targets = DocFormat(url: first).map { FileRouting.finderFilter(engine.targets(from: $0).map(\.fileExtension)) } ?? []
            if !targets.isEmpty {
                let convert = NSMenuItem(title: "Convert to", action: nil, keyEquivalent: "")
                let sub = NSMenu(title: "Convert to")
                for t in targets {
                    let i = item(t, #selector(convertTo(_:)))
                    i.representedObject = t
                    sub.addItem(i)
                }
                convert.submenu = sub
                menu.addItem(convert)
            }
            if first.pathExtension.lowercased() != "otlock" {
                menu.addItem(item("Lock", #selector(lock(_:))))
            }
        default:
            return nil
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func newTxt(_ sender: Any?) { create("txt") }
    @objc private func newMd(_ sender: Any?) { create("md") }

    private func create(_ format: String) {
        let dir = FIFinderSyncController.default().targetedURL()
        NSWorkspace.shared.open(URLRouter.newURL(format: format, dir: dir))
    }

    @objc private func convertTo(_ sender: NSMenuItem) {
        guard let fmt = sender.representedObject as? String else { return }
        for file in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            NSWorkspace.shared.open(URLRouter.convertURL(to: fmt, file: file))
        }
    }

    @objc private func lock(_ sender: Any?) {
        for file in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            NSWorkspace.shared.open(URLRouter.lockURL(file: file))
        }
    }
}
