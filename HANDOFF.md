# Handoff log

## 2026-11-09 (night) · Home window, open-after-create, RTF and Office viewing

**Did:** Walker's first-use feedback. Root cause of both bugs: every window opened through SwiftUI's `openWindow` captured from the MenuBarExtra label, which never opens anything (settings showed `setupShown: true` with no setup window; `~/Desktop/stuff.txt` was created but never opened).
- HOME-1 (0562aa5): `Window("OpenText", id: "home")` presented on launch (`HomeView` in OpenTextUI + `App/Views/HomeHost.swift`): mark, New file card (embedded quick create), Open card (Open a file…, drop zone, recents), "Finish setup" link. Dock click and Window ▸ OpenText Home (⇧⌘H) reopen it; closing leaves the menu bar item. RouterBridge now on every live window and the popover content, not the label. Quick create closes its popover first, then creates and opens the file. First-run setup opens from home. Launch-to-open-files closes home if the open arrives within 3 s.
- HOME-2 (e0aba07): read-only viewer for rtf, docx, doc, odt (`RichTextView`; white page, Copy Text, Save as .txt/.md, Convert); html shows as source text (the HTML importer can fetch remote content). Declared as Viewer / Alternate so TextEdit stays default for RTF. rtfd not supported (DocFormat doesn't know it).
- HOME-3 (41de943): tighter New file card spacing.
**Verified:** OpenTextUI 46 tests, App/Logic 28 pass; Debug build; home and rich-text snapshots checked. Installed with `scripts/install.sh`; Spotlight and LaunchServices list only `/Applications/OpenText.app`; built Info.plist has the Rich Text and Office types. Nothing launched by me.
**Decided:** Rich documents are read-only (Walker's original pain was being pushed into RTF); RTF isn't offered in New file.
**Next:** Walker launches /Applications/OpenText.app: home window appears, Create opens the file, an .rtf opens. The 3 s launch-with-file rule and openWindow after its source window closes are the least certain parts.

## 2026-11-09 (evening) · App icon fixed, one installed copy

**Did:** Found why the icon looked wrong: macOS 26 drew the pre-drawn `AppIcon.appiconset` tile as a grey legacy icon with no citron fold at 128–256px (Spotlight, Finder). Added `App/AppIcon.icon` (Icon Composer format, vector mark from Walker's source SVGs, light and dark backgrounds, no glass translucency) and regenerated the project. Deleted all built copies (`build/OpenText.app`, both DerivedData builds, 11 stale scratch registrations) and added `scripts/install.sh`, which builds once and installs the only copy at `/Applications/OpenText.app`.
**Verified:** The system-rendered icon (`NSWorkspace.icon(forFile:)`) of `/Applications/OpenText.app` shows the citron fold and clean edges from 64px up; at 16–32px the fold is a few pixels. LaunchServices and Spotlight list exactly one OpenText. `codesign --verify --deep --strict` passes. App not launched.
**Decided:** The single install lives in /Applications (normal place for a default opener and the Finder extension); `build/` is no longer used.
**Next:** Walker opens /Applications/OpenText.app for the first real run. Spotlight may need a minute to drop the old entries.

## 2026-11-09 (later) · Icon mark as the in-app logo

**Did:** Walker's final icon mark is now drawn in code (`Packages/OpenTextDesign/Sources/OpenTextDesign/BrandMark.swift`, one geometry for the colour view and the monochrome template) and used in the setup window, the menu bar extra (template, replaces `doc.text`), the Finder extension's menu items (template; the extension now links OpenTextDesign) and the "couldn't open" empty state. The About panel already uses AppIcon (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`). Decision D-021; `identity.mark-fold` #e2e58a added to `design/brand.json` as logo-only.
**Verified:** OpenTextDesign 4 tests and OpenTextUI 44 pass. Off-screen renders of the mark (light, dark, template at 16 and 64pt) and the setup window checked against the source SVG. Signed Release build succeeds; `build/OpenText.app` refreshed and passes `codesign --verify --deep --strict`. Not rendered: the empty state, the real menu bar and Finder menu (need a launch).
**Decided:** Draw the mark as vector from the SVG paths instead of shipping PNG copies, so it scales and follows dark mode; the citron fold stays the same in both modes.
**Next:** On first launch, check the menu bar icon and the Finder right-click icons at real size, then run the audit's launch checklist.

## 2026-11-09 · UI polish pass and full code audit

**Did:**
- UI pass (`docs/review/2026-11-09-ui/findings.md`, status table at the end): Edit/Preview is one control; blue only on each screen's main button (selection is ink); title tracking loosened for Inter Tight (-0.02em ≥22pt, -0.01em below); control-sized shadows on chips and buttons, flat when disabled; softer recessed fields; convert and recovery sheets match the other sheets; setup fits its real 900×440 window. Commits UI-001 to UI-010.
- Full audit (`docs/review/2026-11-09-audit.md`), 20 findings, 19 fixed (commits `AUD-…`): MCP can no longer overwrite files; ⌘Q asks Save / Don't Save / Cancel; text saves keep BOM and encoding and ask before switching to UTF-8; open/save run off the main thread, text over 20 MB opens read-only; editor restyles only the edited paragraph; locking avoids extra copies and refuses files over 2 GB; saves keep Finder tags; image save keeps EXIF, refuses animated GIFs; File ▸ Revert to Saved; images→PDF embeds the compressed photo; Markdown→HTML drops unsafe links; password-protected PDFs get a password prompt; per-file batch convert results; dead code removed.
- `docs/build/cli-mcp.md` updated for the new convert result shape and MCP limits.

**Verified:** `swift test`: OpenTextKit 47, OpenTextDesign 3, OpenTextUI 43, App/Logic 28 — all pass. Signed Release build succeeds; `build/OpenText.app` refreshed and passes `codesign --verify --deep --strict`. All screens re-rendered off-screen and checked. App still not launched, so every runtime item listed at the end of the audit file is unverified.

**Decided:**
- Selection uses ink, primary only on the one main action (BUILD-PACK rule 2 over the kit table's "selected segment = primary").
- Heading tracking looser than the kit's CSS values: the bundled Inter Tight has no optical-size axis, so -0.03/-0.04em made letters touch.
- Lock format unchanged; a chunked v2 format for very large files and a stable Touch ID Keychain id (audit 20) are format decisions left for Walker.

**Next:** Walker opens `build/OpenText.app` and runs through the "Needs the first real launch" list in `docs/review/2026-11-09-audit.md`, starting with ⌘Q on an edited PDF. Nothing is blocking it.

## 2026-11-08 (late) · Signed build after Xcode sign-in

**Did:** Signed Debug and Release builds after Walker signed in to Xcode; `-allowProvisioningDeviceRegistration` registered this Mac and created the profiles. Copied the Release app to `build/OpenText.app` (git-ignored). Added the signed build command to `docs/build/app.md`; cleared the sign-in row in `docs/product/owner-blockers.md`.
**Verified:** Both builds `BUILD SUCCEEDED`; `codesign --verify --deep --strict` passes on Debug, Release and the copied app; entitlements show app group `7ZT7J8C9QP.com.walkertracy.opentext` on the app and the Finder extension, plus `keychain-access-groups` on the app. App still not launched.
**Decided:** No GitHub repo for now (Walker: "No Github yet"); work stays committed on local `main`.
**Next:** Walker opens `build/OpenText.app` for the first real run, goes through the setup window, and reports what's off. Nothing is blocking it.

## 2026-11-08 · Kickoff, look lock and overnight V1 build

**Did:**
- Product kickoff: `docs/product/one-pager.md`, `ux-brief.md`, `owner-blockers.md`, `open-questions.md`; decisions D-001 to D-020 in `docs/decisions.md`. Idea gate passed 24/24.
- Look locked from Walker's `BUILD-PACK.md`: B reading window, fading-toolbar editor, menu-bar quick create (`design/brand.json`, tags `look/b-quiet-fading-toolbar`, `look/b-quiet-fading-toolbar-r2`; rounds in `design/directions/`).
- Fixed `~/.claude/skills/app-look-lock/scripts/wk_snapshot.swift`: it put a visible window at screen origin; it now parks it ~25,000 px off-screen (confirmed with CGWindowList).
- Built V1 with 3 parallel Sonnet workers against `docs/build/PLAN.md`:
  - `Packages/OpenTextKit`: conversions, `.otlock` locking (spec `docs/build/otlock-format.md`), settings, `opentext` CLI, `opentext-mcp` server (`docs/build/cli-mcp.md`).
  - `Packages/OpenTextDesign` + `Packages/OpenTextUI`: tokens, Inter/Inter Tight, PDF reader, image editor, text editor, quick create, setup, lock/convert/recovery sheets; off-screen snapshots in `design/snapshots/`.
  - `project.yml` / `App/` / `FinderExtension/`: app, menus, hotkey (⌃⌥N), `opentext://` routing with signed Finder links, Touch ID + recovery key pinning, close prompts, safe autosave.
- Independent security review and fixes: `docs/build/security-review.md`.

**Verified (run and seen):**
- `swift test`: OpenTextKit 40 tests, OpenTextDesign 3, OpenTextUI 36, App/Logic 26 — all pass.
- Unsigned Debug and Release `xcodebuild` builds: BUILD SUCCEEDED.
- Earlier signed build (before the app-group/Keychain entitlements) passed `codesign --verify --deep --strict`, team 7ZT7J8C9QP.
- Not verified: the app has never been launched (Walker asked for nothing on screen), so windows, menus, hotkey, Finder menu, Touch ID and the app-group token are untested at runtime. Snapshots of the views were reviewed; the live PDFView renders blank off-screen, so the PDF snapshot uses a still image of the page.

**Decided:**
- PBKDF2-SHA256 at 600k iterations, not Argon2: Argon2 needs libsodium's prebuilt binary (supply-chain risk). (D-020)
- Approved downloads only: Inter Tight, swift-markdown, swift-argument-parser, MCP Swift SDK, KeyboardShortcuts — all Apache/MIT/BSD/OFL, fine for commercial use. A release must ship a third-party notices file.
- MCP agents can lock files but never delete originals or choose the recovery key (security review #1, #7).
- Team ID is 7ZT7J8C9QP; QGPDXDQ9SW is the certificate's own ID (it was wrongly recorded at first).

**Next:** Sign in to Xcode (Xcode ▸ Settings ▸ Accounts) so the app group and Keychain group get a provisioning profile, then run the signed build in `docs/build/app.md` and launch the app for the first real check. Blocked on Walker for the sign-in. Also waiting on Walker: approval to create a private GitHub repo — `gh repo create` was refused by the permission system, so nothing is pushed; all work is committed on local `main`.
