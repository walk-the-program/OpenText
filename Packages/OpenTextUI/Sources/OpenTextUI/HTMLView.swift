import SwiftUI
import AppKit
import WebKit
import OpenTextDesign

// MARK: - Pure safety helpers (testable without WebKit)

/// What an HTML file is allowed to do while it is shown. The file is untrusted: it must not reach the network,
/// the disk, or other windows. Three independent layers: a content rule list that blocks every subresource load,
/// no JavaScript, and a navigation delegate that cancels everything but our own initial load.
public enum HTMLSafety {
    public enum Decision: Equatable, Sendable {
        case allow, cancel
        /// A link the user clicked: hand to the default browser (never loaded in the view).
        case openExternally
    }

    /// Blocks every load, any resource type, any URL.
    public static let blockAllRuleJSON = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#

    /// Only our own initial `loadHTMLString` (about:blank, no click, before it has finished) is allowed.
    /// Clicked http / https / mailto links open in the default browser; everything else is cancelled.
    public static func shouldAllow(url: URL?, isUserClick: Bool, initialLoadDone: Bool = false) -> Decision {
        if isUserClick {
            if let url, let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) { return .openExternally }
            return .cancel
        }
        if !initialLoadDone, url == nil || url?.absoluteString == "about:blank" { return .allow }
        return .cancel
    }

    // MARK: decoding

    /// Declared charset (BOM first, then `<meta charset>` / `Content-Type` meta in the first 4 KB), else UTF-8,
    /// else Latin-1 (which accepts every byte).
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) { return s }
        if let enc = declaredEncoding(in: data), let s = String(data: data, encoding: enc) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Charset name from a meta tag in the head of the document, as a String.Encoding.
    public static func declaredEncoding(in data: Data) -> String.Encoding? {
        guard let name = declaredCharset(in: data) else { return nil }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    public static func declaredCharset(in data: Data) -> String? {
        let head = String(decoding: data.prefix(4096).map { $0 < 0x80 ? $0 : 0x3F }, as: UTF8.self).lowercased()
        guard let r = head.range(of: "charset") else { return nil }
        var rest = head[r.upperBound...].drop(while: { $0 == " " })
        guard rest.first == "=" else { return nil }
        rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\"" || $0 == "'" })
        let name = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":" || $0 == "." })
        return name.isEmpty ? nil : String(name)
    }

    /// Visible words only (scripts, styles and tags dropped): fallback for Copy Text and the word count.
    public static func plainText(fromHTML html: String) -> String {
        var s = html
        for tag in ["script", "style", "head"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "</(p|div|h[1-6]|li|tr|br)\\s*>|<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (k, v) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Locked-down web view

/// The one place a WKWebView for untrusted HTML is built. Settings, all deliberate:
/// - non-persistent data store (no cookies, cache or storage on disk)
/// - `allowsContentJavaScript = false`; windows cannot be opened by script
/// - a compiled block-everything content rule list installed before anything loads
/// - media never autoplays; no inline-media
/// - loaded with `baseURL: nil`, so relative file references cannot resolve
@MainActor
enum SafeWebView {
    static let ruleIdentifier = "com.walkertracy.opentext.block-all"

    static func compileRules() async -> WKContentRuleList? {
        try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: ruleIdentifier, encodedContentRuleList: HTMLSafety.blockAllRuleJSON)
    }

    static func make(rules: WKContentRuleList, delegate: WKNavigationDelegate) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isFraudulentWebsiteWarningEnabled = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(rules)
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = delegate
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        // Pinned to Aqua: the page stays white like a printed page in dark mode.
        web.appearance = NSAppearance(named: .aqua)
        return web
    }
}

private struct HTMLBody: NSViewRepresentable {
    let html: String
    let rules: WKContentRuleList

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = SafeWebView.make(rules: rules, delegate: context.coordinator)
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var initialLoadDone = false

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let click = navigationAction.navigationType == .linkActivated
            let url = navigationAction.request.url
            switch HTMLSafety.shouldAllow(url: url, isUserClick: click, initialLoadDone: initialLoadDone) {
            case .allow: decisionHandler(.allow)
            case .cancel: decisionHandler(.cancel)
            case .openExternally:
                if let url { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { initialLoadDone = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { initialLoadDone = true }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - View

/// Read-only viewer for HTML files, rendered (not source) with no way to fetch anything: no network, no disk,
/// no JavaScript, no navigation. If the block-everything rule list can't be compiled, shows the source as text.
public struct HTMLView: View {
    let html: String
    let actions: RichTextActions
    let header: DocumentHeader?
    @State private var rules: WKContentRuleList?
    @State private var compiled = false
    private let plain: String

    public init(html: String, actions: RichTextActions = .init(), header: DocumentHeader? = nil) {
        self.html = html
        self.actions = actions
        self.header = header
        self.plain = HTMLSafety.plainText(fromHTML: html)
    }

    private var headerWithStatus: DocumentHeader? {
        guard var h = header else { return nil }
        h.status = "\(WordCounter.label(plain)) · Read-only"
        return h
    }

    public var body: some View {
        if compiled && rules == nil {
            // Safe fallback: the source as plain text, same as before the web view existed.
            RichTextView(attributed: NSAttributedString(string: html, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.black]),
                         actions: actions, header: header)
        } else {
            VStack(spacing: 0) {
                ToolbarRow(header: headerWithStatus) {
                    ToolButton(title: "Copy Text") { copyText() }
                    ToolButton(title: "Save as .txt") { actions.onSaveAs("txt") }
                    ToolButton(title: "Save as .md") { actions.onSaveAs("md") }
                } trailing: {
                    Button("Convert", action: actions.onConvert)
                        .buttonStyle(.primaryAction).keyboardShortcut("e", modifiers: [.command, .shift])
                }
                ZStack {
                    Brand.Palette.canvas
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Group {
                            if let rules { HTMLBody(html: html, rules: rules) } else { Color.white }
                        }
                        .frame(maxWidth: 860, maxHeight: .infinity)
                        .background(Color.white)
                        .overlay(alignment: .leading) { Rectangle().fill(Brand.Palette.line).frame(width: 1) }
                        .overlay(alignment: .trailing) { Rectangle().fill(Brand.Palette.line).frame(width: 1) }
                        Spacer(minLength: 0)
                    }
                }
            }
            .task {
                guard !compiled else { return }
                rules = await SafeWebView.compileRules()
                compiled = true
            }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
    }
}
