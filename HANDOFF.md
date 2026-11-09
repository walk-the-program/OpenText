# Handoff log

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
