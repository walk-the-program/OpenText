# App (T3a + T3b)

`project.yml` -> `xcodegen generate` -> `OpenText.xcodeproj`. Targets `OpenText` (not sandboxed, hardened runtime, team 7ZT7J8C9QP, automatic signing) and `OpenTextFinder` (sandboxed FinderSync, embedded in Contents/PlugIns). Dependencies: local packages OpenTextKit, OpenTextDesign, OpenTextUI, App/Logic (OpenTextAppLogic); remote KeyboardShortcuts >= 1.10.0 (MIT, approved in contract rev 2). The app target uses Swift language mode 5; the packages use 6.

Signed build: `xcodebuild -project OpenText.xcodeproj -scheme OpenText -configuration Debug -destination 'platform=macOS' DEVELOPMENT_TEAM=7ZT7J8C9QP -allowProvisioningUpdates build`.

## Layout
- `App/Logic/` SwiftPM package `OpenTextAppLogic` (pure logic, shared with the Finder extension, `swift test`): `HotkeyParser` (+`format`), `URLRouter`/`AppRoute`, `FileRouting`/`FileKind`, `PasswordRules`.
- `App/Services/`: `AppModel` (settings, hotkey, routing, new/convert entry points), `DocumentSession` (per-window state, save, format switch, convert, lock/unlock), `LockFlow`, `BiometricKeychain`, `HotkeyManager` (KeyboardShortcuts), `OpenTextSetup` (setup button actions).
- `App/Views/`: `DocumentWindowView` (PDFReaderView / ImageEditorView / TextEditorView / LockedFileView + sheets), `QuickCreateHost`, `SetupHost`, `Sheets.swift` (`LockSheet`, `NoticeCard`).
- `FinderExtension/FinderSync.swift`; Info.plists are generated from project.yml.

## Behavior
- One window per file: `WindowGroup(for: URL.self)`, hidden title bar; the view's own toolbar row shows title + format chip (`DocumentHeader`). Picking a format calls `ConversionEngine.switchFormat` (original goes to the Trash) and reloads the same window with the new file.
- Open: Finder double-click / Open With / `opentext://` via `application(_:open:)` and `.onOpenURL` (same URL de-duped within 1 s), plus File > Open.
- Save: text autosaves 1 s after typing and on Cmd-S; PDF Cmd-S runs `PDFPageOps.flattenStamps` then writes `dataRepresentation()`; images Cmd-S (or the editor's Save) encode the edited image in the original format (png, jpg, tiff, gif, heic; webp cannot be written by ImageIO, so saving a webp shows an error and Convert is the route).
- Convert: ConvertSheet with `ConversionEngine.targets`; the result card lists the written files with a Show in Finder button (never auto-opens). Finder `convert` routes report in a small notice window.
- Quick create: `QuickCreateView` in the MenuBarExtra popover and in the hotkey window ("quick-create"); `NewFile.create` in `settings.defaultFolder`; Change opens an NSOpenPanel (folders only) on click and saves the folder to settings. Finder `new` uses the same `AppModel.createNew`.
- Setup window: `SetupView` wired to `OpenTextSetup` (set defaults for png/jpeg/heic/tiff/gif/webp/pdf/plain-text/markdown, open System Settings > Extensions, `FIFinderSyncController.isExtensionEnabled`). Opens on first launch only (UserDefaults `setupShown`, because OpenTextSettings has no field for it); also under the app menu. Nothing runs until a button is pressed.
- Hotkey: KeyboardShortcuts name `.quickCreate`, default ctrl+opt+N. settings.json `hotkey` is the readable mirror: setup changes write it; on launch and on app activation the file wins when it differs from the stored shortcut. Setup's shortcut field is OpenTextUI's own recorder (single-character keys); `KeyboardShortcuts.Recorder` is not used because `SetupView` has no slot for it.
- Lock: password + confirm (min 8), Touch ID toggle. First lock generates `RecoveryKey`, shows `RecoveryKeySheet` once, saves only the public key (after the lock succeeds). The original goes to the Trash (`removeOriginal`). Touch ID: Keychain item (service `com.walkertracy.opentext.lock`, account `Locker.lockID(of:)`, `.biometryCurrentSet`, data-protection keychain) stored on lock and on a successful password unlock; read with LAContext. Password / Touch ID unlock decrypts to memory (`Locker.decrypt`) and shows the document with no plaintext file. Recovery-key unlock is an explicit unlock to a file (`Locker.unlock(_:recoveryKey:)`): the original is written next to the .otlock and the window reloads it.
- Menus: File New (Cmd-N, quick create), Open (Cmd-O), Save (Cmd-S), Convert (Shift-Cmd-E), Lock (Ctrl-Cmd-L). The menu wins over the views' own Save/Convert bindings, so each key does one thing. Find, Zoom, Thumbnails and the Markdown tools are bound inside the views (Cmd-K is Crop in images and Link in markdown text; not in the menu).
- URL routes: `opentext://new?format=<txt|md|csv|html>&dir=<abs path>`, `convert?to=<fmt>&file=<abs path>`, `lock?file=<abs path>`. Absolute or ~ paths only, `..` resolved, formats whitelisted.
- Finder extension: monitors "/", container menu New Text File / New Markdown File, item menu Convert to > (engine targets filtered to pdf/md/txt/png/jpg) and Lock; each action opens an opentext:// URL (the sandboxed extension never writes files).

## CLI and MCP server
Build (from the repo root): `cd Packages/OpenTextKit && swift build -c release`. Binaries: `Packages/OpenTextKit/.build/release/opentext` and `.../opentext-mcp`.
Claude Code MCP config line (run by Walker; nothing outside the repo is edited here):
`claude mcp add opentext -- /Users/walker_tracy/Desktop/Projects/OpenText/Packages/OpenTextKit/.build/release/opentext-mcp`
See docs/build/cli-mcp.md for tools and arguments.

## T5d + T6b additions
- Menus drive views through `DocumentCommands` (`session.commands`, `.focusedSceneValue(\.documentCommands, ...)`): Edit > Find; View > Zoom In/Out/Actual Size/Thumbnails; Markdown > Heading 1-3, Bold, Italic, List, Link; Image > Crop, Resize, Rotate, Flip H/V. Highlight, Sign, Edit/Preview, Mono stay in the views. Save / Convert / Lock keep their menu items; an event is consumed once, so a key never fires twice.
- Close prompt (Save / Don't Save / Cancel) for windows with unsaved changes (`WindowCloseGuard` in DocumentWindowView.swift); `markSaved()` after every save and load; the close button shows the edited dot.
- Opened .otlock documents are editable: Save calls `Locker.lock(data:...output: original)` off the main thread with the session password, then stores Touch ID under the new `Locker.lockID(of:)` and deletes the old item. Unlocking with the recovery key has no password, so Save asks for a new one. PBKDF2 (unlock, lock, save-back) runs off the main thread with a progress overlay.
- Security: (1) URL token in the app-group container (`TokenStore`, group `7ZT7J8C9QP.com.walkertracy.opentext`); unsigned URLs ask first (`ConfirmationPolicy`, one dialog at a time); paths must be inside $HOME and outside ~/Library after symlink resolution (`PathPolicy`/`RouteGuard`). (2) Recovery public key pinned in the Keychain (`RecoveryPin`); `PinPolicy` decides; mismatch blocks locking and save-back with Keep original / Accept new (Touch ID or Mac password); fingerprint shown in the lock sheet. (3) `originalNotRemoved` and the Trash message in `DocumentSession.lock`. (4) Save checks the modification date (Reload / Keep Mine), frozen editor during format switch, original text encoding kept (`TextCoding`). (5) keychain-access-groups entitlement, add-then-update, store errors shown in the UI.
- First-launch flag now `OpenTextSettings.setupShown` (UserDefaults value migrated once). Setup uses `KeyboardShortcuts.Recorder` via `shortcutRecorder`.

## Signing note
App group + keychain-access-groups are restricted entitlements and need a provisioning profile. This Mac's Xcode has no Apple ID signed in (Settings > Accounts), so `-allowProvisioningUpdates` fails with "No Accounts / No profiles for com.walkertracy.opentext". Walker: sign in under Xcode > Settings > Accounts, then run the signed build command above; Xcode registers the App ID and the app group. Unsigned compile check: add `CODE_SIGNING_ALLOWED=NO`.

## Known gaps
- Not launched or UI-tested (constraint): RouterBridge, hidden-title-bar layout, hotkey, Finder menu, close prompt delegate forwarding, Touch ID flows.
- No unsaved-changes prompt on Cmd-Q (only on closing a window).
- Animated GIFs lose extra frames when saved from the image editor; webp cannot be saved.
- `findLockedSibling` guesses the new .otlock by name prefix when the original could not be trashed.


## Signed build (verified 2026-11-08)
```bash
xcodebuild -project OpenText.xcodeproj -scheme OpenText -configuration Release -destination 'platform=macOS' DEVELOPMENT_TEAM=7ZT7J8C9QP -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```
The first signed build registered this Mac in the developer account and created the Mac development profiles for the app group and Keychain group. A verified Release copy is kept at `build/OpenText.app` (git-ignored).
