# OpenTextDesign + OpenTextUI public API (contract rev 2)

Two local SwiftPM packages, macOS 26, Swift 6, zero external dependencies:
- `Packages/OpenTextDesign` (library `OpenTextDesign`): tokens, fonts, surfaces, button styles, `FormatChip`.
- `Packages/OpenTextUI` (library `OpenTextUI`, depends on `../OpenTextDesign`): views and pure logic. It imports no OpenTextKit types. Formats cross as lowercase extension strings ("pdf", "md").

Call `Brand.registerFonts()` once at launch (fonts also register lazily the first time a Brand font is used).
Fonts: Inter 18pt Regular/Medium/SemiBold for body, Inter Tight variable (weight axis 600) for headings (D-020).

## OpenTextDesign
- `Brand.Palette.*` (SwiftUI `Color`) and `Brand.NSPalette.*` (`NSColor`), dynamic light/dark: canvas, surface, ink, muted, line, primary, onPrimary, accent, onAccent, primaryPressed, secTint, divider, abMuted, tileLine, shade, glow, scrim.
- `Brand.Radius` (sm 6, md 8, field 8, chip 9, button 10, lg 12, popover 14, card 16), `Brand.Spacing`, `Brand.Size` (control 28, toolbarHeight 48, statusBarHeight 28), `Brand.Motion` (quick .12, standard .18, slow .28).
- `Brand.Fonts.body(size, weight:)`, `.heading(size)`, `.nsBody`, `.nsHeading`, `Brand.Fonts.PostScript.*`.
- View modifiers: `.raisedSurface()`, `.recessedSurface()`, `.floatingSurface()`, `.paperSurface()`, `.brandField()`, `.brandHeading(size)`, `.brandLabel()`, `.brandBody()`.
- Button styles: `.primaryAction` (one per window), `.primaryAction(showsArrow:)`, `.secondaryAction`, `.toolbarItem`, `.toolbarItem(isActive:)`.
- `FormatChip(format:targets:onSelect:)`.

## OpenTextUI views
All views fill the space given. Optional `header: DocumentHeader?` draws the title + `.ext` chip at the left of the view's own toolbar row (use with a hidden title bar; `leadingInset` ~78 leaves room for the traffic lights). Leave nil to use the native title.

```swift
public struct DocumentHeader {
    init(title: String, format: String, targets: [String] = [], leadingInset: CGFloat = 0, onSwitchFormat: @escaping (String) -> Void = { _ in })
}

PDFReaderView(document: PDFDocument, actions: PDFReaderActions = .init(), header: DocumentHeader? = nil, commands: DocumentCommands? = nil)
public struct PDFReaderActions { init(onConvert: () -> Void = {}, loadSignature: () -> Data? = { nil },
                                       saveSignature: (Data) -> Void = { _ in }, onChange: () -> Void = {}) }
```
- The view mutates the passed `PDFDocument` in place (reorder, delete, insert dropped PDFs, rotate, highlight, signature stamp) and calls `onChange`. Autosave/dirty tracking is the app's job.
- Sign: if `loadSignature()` returns PNG data it is placed on the current page; otherwise the `SignaturePad` sheet opens and its PNG goes to `saveSignature` and is placed.
- Before writing the document to disk call `PDFPageOps.flattenStamps(in: document)` (PDFKit does not persist the custom signature annotation; this bakes it into the page and keeps text vectors). Highlights are standard annotations and need nothing.
- Delete key (sidebar focused) removes the current page (never the last one). Thumbnails drag to reorder; dropping .pdf files on the sidebar inserts them (on a thumbnail: after it; on the well: at the end).

```swift
ImageEditorView(image: NSImage, actions: ImageEditorActions = .init(), header: DocumentHeader? = nil, commands: DocumentCommands? = nil)
ImageEditorActions(onSave: (NSImage) -> Void = { _ in }, onConvert: () -> Void = {}, onChange: (NSImage) -> Void = { _ in })
```
Crop (drag rectangle, corners resize, Return applies), Resize sheet (W x H, keep aspect), Rotate 90, Flip menu, Zoom menu. `onSave` hands over the edited image (encode in the original format); Save is enabled once edited.

```swift
TextEditorView(text: Binding<String>, isMarkdown: Bool, monospace: Bool = false, isSaved: Bool = true,
               actions: TextEditorActions = .init(), header: DocumentHeader? = nil, commands: DocumentCommands? = nil)
TextEditorActions(onConvert: () -> Void = {}, onLock: () -> Void = {}, onToggleMonospace: () -> Void = {})
```
Plain text only (`isRichText = false`). Markdown (`isMarkdown`): syntax characters muted, Heading/Bold/List/Link tools, Edit/Preview segmented, headings scaled. For .txt the tool slot shows "Mono"/"Inter" (calls `onToggleMonospace`; you own the setting and pass `monospace` back). Tool row (not the title/chip) fades ~0.4 s after typing starts and returns on mouse move; instant (no animation) with Reduce Motion. Footer "N words · Saved" (`isSaved == false` shows "Edited").

```swift
public struct QuickCreateState: Equatable { var name = "Untitled"; var format = "md"; var folderPath = "~/Desktop"; var folderName: String { get }; static let formats }
QuickCreateView(state: Binding<QuickCreateState>, onCreate: () -> Void = {}, onChangeFolder: () -> Void = {}, onCancel: () -> Void = {})
```
Fixed 420 x 260. Return = Create, Esc = onCancel (`onExitCommand`), name field focused on appear. Folder picking is yours (`onChangeFolder`).

```swift
public struct SetupState: Equatable { var defaultAppsDone = false; var finderExtensionOn = false; var shortcut = "ctrl+opt+n"; var shortcutWarning: String? = nil }
public struct SetupActions { init(onMakeDefault:, onOpenFinderSettings:, onShortcutChanged: (String) -> Void, onDone:) }  // all defaulted
SetupView(state: Binding<SetupState>, actions: SetupActions = .init(), shortcutRecorder: AnyView? = nil)
```
`shortcutRecorder`: when non-nil it replaces the built-in single-key recorder (pass `AnyView(KeyboardShortcuts.Recorder(...))`); the app then owns recording and the view never calls `onShortcutChanged`. The shortcut warning still shows under it.
Note: `state` is a `Binding` (the built-in shortcut field edits it). Shortcut strings use the settings.json spelling ("ctrl+opt+shift+cmd+<key>").

```swift
RichTextActions(onConvert: () -> Void = {}, onSaveAs: (String) -> Void = { _ in })   // onSaveAs gets "txt" or "md"
RichTextView(attributed: NSAttributedString, actions: RichTextActions = .init(), header: DocumentHeader? = nil)
```
Read-only, selectable viewer for rtf / docx / doc / odt content; same toolbar, paper column and status bar as `TextEditorView`. Tools: Copy Text (plain string to the pasteboard), Save as .txt, Save as .md; Convert is the one primary. Status "N words · Read-only". The document keeps its own fonts and colours, so the page is always white (Aqua-pinned text view), also in dark mode. Never edits or saves.

```swift
public enum UnlockMethod { case password(String), touchID, recoveryKey(String) }
LockedFileView(fileName: String, canUseTouchID: Bool, errorMessage: String? = nil, onUnlock: (UnlockMethod) -> Void)
ConvertSheet(sourceFormat: String, targets: [String], onConvert: (String) -> Void, onCancel: () -> Void = {})
RecoveryKeySheet(displayString: String, onDone: () -> Void = {}, onCopy: ((String) -> Void)? = nil, onSaveAsText: ((String) -> Void)? = nil)
SignaturePad(onDone: (Data) -> Void, onCancel: () -> Void)   // transparent PNG
```
`ConvertSheet` and `RecoveryKeySheet` are sized for `.sheet`. `RecoveryKeySheet` copies / opens an NSSavePanel itself unless you pass closures. Locked view: Use Touch ID is the one primary (Unlock becomes primary when `canUseTouchID` is false or the recovery field is shown).

## DocumentCommands (menu hooks and dirty state)
```swift
@MainActor @Observable public final class DocumentCommands {
    public init()
    public enum Kind { case pdf, image, text }
    public enum Command: Hashable, Sendable {
        case find, toggleThumbnails, highlight, sign                 // PDF
        case zoomIn, zoomOut, actualSize, rotate                     // PDF and image
        case crop, resize, flipHorizontal, flipVertical              // image
        case heading(Int /* 1...3 */), bold, italic, list, link, togglePreview, toggleMonospace   // text (monospace: .txt only)
    }
    public private(set) var kind: Kind?                              // nil until a view appears
    public func isAvailable(_ c: Command) -> Bool                    // for .disabled(...)
    @discardableResult public func perform(_ c: Command) -> Bool     // false = unavailable, nothing happened
    public private(set) var isDirty: Bool
    public var onDirtyChange: ((Bool) -> Void)?                      // fires on flips only
    public func markSaved()                                          // app calls after a successful write
    // used by the views: register(kind:handlers:onSaved:), unregister(), markDirty()
}
extension FocusedValues { public var documentCommands: DocumentCommands? }
```
Wiring: one `DocumentCommands` per window, pass `commands:` to the view, publish `.focusedSceneValue(\.documentCommands, commands)` on the window content, and in `.commands { }` read `@FocusedValue(\.documentCommands)`; each menu item calls `commands?.perform(.x)` and uses `.disabled(!(commands?.isAvailable(.x) ?? false))`. Heading ⌘1/⌘2/⌘3 is `.heading(1...3)` (sets that level, or removes it if already set); the toolbar Heading button still cycles levels. Italic wraps in `*`.
- Views register on appear and unregister on disappear. The text editor drops format commands (heading/bold/italic/list/link) while in Preview.
- Behaviour: Find opens (never closes) the search bar and focuses it. PDF Actual Size = 100% scale (Fit Width stays in the Zoom menu without a shortcut). Image Actual Size = 1 image pixel per point; Fit has no shortcut. Thumbnails shows/hides the page sidebar.
- **Shortcut ownership:** when `commands` is non-nil the view drops its own shortcut for the menu-owned commands so nothing double-fires: Find, Zoom In/Out/Actual Size, Rotate (PDF and image), Crop, Resize (was ⌥⌘R, menu uses ⌥⌘I), Flip H/V (the app may give them ⌃⌘H / ⌃⌘V), Heading, Bold, List, Link. Thumbnails has no in-view shortcut. In-view shortcuts that stay even with `commands`: PDF Highlight ⇧⌘H and Sign ⌃⌘S, Edit/Preview ⇧⌘P, Mono ⇧⌘M, Lock ⌥⌘L, Convert ⇧⌘E, Save ⌘S, search next/previous/Done, crop Return/Esc.  Menu items for those would double-fire: ask for a variant before adding any. With `commands == nil` every in-view shortcut is active as before.
- Italic has no toolbar button (menu only, ⌘I).

Dirty state: with `commands` set, `isDirty` becomes true on any PDF page op / highlight / signature, any image edit (crop, resize, rotate, flip), and any change to the text binding (including programmatic ones). The app calls `commands.markSaved()` after a successful write; this also re-disables the image editor's Save button. `onDirtyChange` fires on each flip (use it to set `NSWindow.isDocumentEdited` or confirm on close). `PDFReaderActions.onChange` and `ImageEditorActions.onChange` still fire as before.

## Pure logic (public, unit-tested)
`PDFPageOps` (move, delete, insert, rotate, addHighlight, stampImage, defaultStampBounds, flattenStamps), `ImageOps` (crop, resize, rotate90, flip, aspect helpers, NSImage/CGImage bridges), `CropRect`, `MarkdownSyntaxHighlighter`, `MarkdownFormatting`, `MarkdownPreviewParser`, `WordCounter`.

## Keyboard shortcuts defined inside the views (mirror them in the app menus if you add menu items)
PDF: Highlight ⇧⌘H, Sign ⌃⌘S, Rotate ⌘R, Find ⌘F (next ⌘G, previous ⇧⌘G, Esc closes), Zoom in/out/fit ⌘= / ⌘- / ⌘0, Convert ⇧⌘E.
Image: Crop ⌘K (Return applies, Esc cancels), Resize ⌥⌘R, Rotate ⌘R, Flip H/V ⌃⌘H / ⌃⌘V, Zoom as above, Save ⌘S, Convert ⇧⌘E.
Text: Heading ⌥⌘1, Bold ⌘B, List ⇧⌘L, Link ⌘K, Edit/Preview ⇧⌘P, Mono ⇧⌘M (.txt), Lock ⌥⌘L, Convert ⇧⌘E.
Note: ⌘S in the image editor and ⌘R/⌘F may also exist in the app's menus; define the menu command once and let it win, or drop the duplicate here.

## Limits
- The signature stamp is placed at a default spot (lower third, centred, 180 pt wide); it cannot be dragged afterwards.
- Page content of `PDFView` does not draw when the view is not in a window; off-screen snapshots substitute a still image of the page (see design/snapshots).
