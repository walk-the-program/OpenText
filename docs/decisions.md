# Decisions

Newest at the bottom. Never delete an entry; mark it superseded instead.

---

## D-001 — Mac only, native app
- Date: 2026-11-08
- Status: Decided
- Decision: OpenText is a native macOS app (Swift, AppKit/SwiftUI). No iPhone, iPad, web or Electron.
- Why: Walker wants "a real application on my Mac"; the pain lives in Finder and macOS default apps.
- Alternatives considered: Electron/cross-platform; Finder-only Quick Actions with no app.

## D-002 — Personal tool, free, no business model in V1
- Date: 2026-11-08
- Status: Decided
- Decision: Built for Walker first. No price, no App Store release in V1.
- Why: "It's something I could ship down the line. I don't really care about that right now."
- Alternatives considered: Paid App Store app (would force sandboxing limits on Finder integration).

## D-003 — One-off document utility, not a notes app
- Date: 2026-11-08
- Status: Decided
- Decision: No vault, library, backlinks or notes storage. The filesystem is the only organisation.
- Why: Walker will use it "just to open up documents", not to keep notes; backlinks are "generally futile".
- Alternatives considered: Obsidian-style vault with linking.

## D-004 — Default opener for images, PDF, .txt and .md
- Date: 2026-11-08
- Status: Decided
- Decision: The app registers for and Walker sets it as default for all four types.
- Why: Walker confirmed all four. Consequence: the PDF and image viewer must match Preview's basics.
- Alternatives considered: Default for text only, leaving PDF/images in Preview.

## D-005 — Engine first, with app, CLI and MCP front ends
- Date: 2026-11-08
- Status: Decided
- Decision: Conversion engine is a standalone core; the app, a CLI and an MCP server sit on top of it with the same operations. This is the working meaning of "every part editable": anything the app can do, the CLI and AI agents can do, and settings live in a plain editable file.
- Why: Walker wants AIs to be able to create and convert documents through it as a hub, more efficiently than writing one-off code.
- Alternatives considered: App only; AI writing its own conversion scripts each time.

## D-006 — Lock/unlock any file in V1, standard crypto, documented format
- Date: 2026-11-08
- Status: Decided
- Decision: "Convert to → Locked" encrypts any file with AES-256 via CryptoKit and a slow password-based key derivation. File format is documented so files are recoverable without the app.
- Why: Walker wants uncrackable password protection and moved it from V1.5 into V1. A proprietary, undocumented format would strand files if the app breaks.
- Alternatives considered: App-only proprietary format; leaving it to V1.5.

## D-007 — V2: handwriting and voice memo to text
- Date: 2026-11-08
- Status: Decided
- Decision: Handwriting photo → md and voice memo → txt are V2, on-device only.
- Why: Covers Walker's handwritten/dictated notes as conversions instead of a notes system; may link to his separate speech-to-text project.
- Alternatives considered: V1; a separate notes feature.

## D-008 — Keep "OpenText" as a private codename
- Date: 2026-11-08
- Status: Decided
- Decision: Keep OpenText as the working name while it is a personal tool. Pick a real name before any public release.
- Why: OpenText is blocked for release (Open Text Corporation publishes apps and holds the marks, domains and handles), but that doesn't matter for a private app. Walker chose to keep it for now.
- Alternatives considered: Docshift (least conflicted, domains held), Anyfile, Recast, Ferry (existing apps), Plainfile (blocked).

## D-009 — V1 viewer scope matches what Walker does in Preview
- Date: 2026-11-08
- Status: Decided
- Decision: PDF: highlight, sign, combine PDFs, reorder/delete pages. Images: crop, resize, rotate/flip. Plus zoom, thumbnails and search.
- Why: Walker listed these as everything he does in Preview today; the app is his default for PDFs and images (D-004).
- Alternatives considered: Read-only viewing in V1.

## D-010 — Unlock with password or Touch ID; hardware key later
- Date: 2026-11-08
- Status: Decided
- Decision: V1 locked files unlock with the password or Touch ID. A hardware security key is V2, pending a feasibility check and Walker finding his key.
- Why: Walker wants Touch ID or passcode and says "more secure is better"; the key is currently lost.
- Alternatives considered: Password only; hardware key in V1.

## D-011 — Three ways to make a new file fast
- Date: 2026-11-08
- Status: Decided
- Decision: Finder right-click "New … File" (including empty Desktop space), a menu bar icon, and a global keyboard shortcut that opens a small type picker.
- Why: Walker wants new-document creation to be "so quick"; his speech-to-text project uses the same shortcut-first pattern.
- Alternatives considered: Menu bar only; app window only.

## D-012 — One-time recovery key for locked files
- Date: 2026-11-08
- Status: Decided
- Decision: When locking is first set up, the app generates a one-time recovery key for Walker to print or store offline. The key can unlock files if the password is forgotten and Touch ID is unavailable.
- Why: Walker accepted a slightly smaller security margin so he can never be locked out of his own files.
- Alternatives considered: No recovery (most secure, files lost forever if the password is forgotten).

## D-013 — Quick-created files go to a configurable default folder, Desktop to start
- Date: 2026-11-08
- Status: Decided
- Decision: Files made from the shortcut or menu bar icon land in a default folder set in settings. It starts as ~/Desktop. Finder right-click creates the file in the folder that was clicked.
- Why: Walker: "you could establish a default… probably the desktop."
- Alternatives considered: Always the frontmost Finder folder.

## D-014 — Positioning and success measure accepted as proposed
- Date: 2026-11-08
- Status: Decided
- Decision: Positioning and success measure as written in the one-pager.
- Why: Walker: "I don't care about the positioning or success metric… whatever you think is fine."
- Alternatives considered: None discussed.

## D-015 — Visual source of truth is BUILD-PACK.md (Bento Grid × Soft Form)
- Date: 2026-11-08
- Status: Decided
- Decision: Walker's Looks Good pack is the locked look: palette, Inter / Inter Tight, materials, one-primary rule, Theme.swift. Phone-only parts (44pt targets, tab bar, bottom sheets, status bar, 17pt body) are translated to Mac conventions. The 3 directions vary layout and density only, never palette or type.
- Why: Walker supplied the pack as the UI/UX; the app is Mac only (D-001).
- Alternatives considered: Three fresh visual directions from scratch (would discard Walker's chosen look).

## D-016 — Editor font
- Date: 2026-11-08
- Status: Decided
- Decision: Markdown edits in Inter (pack body face). Plain .txt opens in Inter with a one-click toggle to SF Mono.
- Why: Recommended in the approval summary; Walker approved without changing it.
- Alternatives considered: Monospace everywhere; Inter only.

## D-017 — Kickoff approved
- Date: 2026-11-08
- Status: Decided
- Decision: Walker approved the kickoff summary (who, job, price, V1/V2, name, blockers, feel, hard nos, 3 layout directions) in words.
- Why: "Approved".
- Alternatives considered: —

## D-018 — Look locked: B reading, fading-toolbar editor, menu-bar quick create (look/b-quiet-fading-toolbar)
- Date: 2026-11-08
- Status: Decided
- Decision: Lock the look as tag look/b-quiet-fading-toolbar. Reading (PDF, images): direction B, native toolbar plus recessed thumbnail sidebar, document filling the window. Text editing: B's toolbar with text tools (Heading, Bold, List, Link, Edit/Preview, Lock, Convert) that fades while typing and returns on mouse movement. Quick create: popover hanging from the menu bar item. Palette, materials and one-primary rule from BUILD-PACK.md. Source: design/brand.json and design/directions/round2/.
- Why: Walker: "I probably like B the most for reading", quick create "attached to the top… probably B", editor "The toolbar fades, honestly… I quite like that."
- Alternatives considered: A Tile desk, C Command strip (round 1); editor tools expanding up or out from a corner button (round 2).

## D-019 — Inter's display optical size stands in for Inter Tight
- Date: 2026-11-08
- Status: Decided
- Decision: Headings use Inter SemiBold at its display optical size (Inter_28pt files) with the pack's tight tracking, instead of Inter Tight. Fonts are copied from ~/Library/Fonts into the app bundle (Inter 18pt Regular/Medium/SemiBold for body, Inter 28pt SemiBold/Bold for display).
- Why: Inter Tight isn't on this Mac and Walker asked for no downloads overnight. The two faces are close at heading sizes.
- Alternatives considered: Download Inter Tight (blocked by the no-downloads rule); system SF Pro.
