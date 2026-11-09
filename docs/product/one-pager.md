# OpenText (working name) — one-pager

Placeholder rule: any line starting with `TODO:` counts as empty to app-idea-gate.

## Who it's for
Walker, on his own Mac. Personal tool first; shipping is a maybe for later. Real example: on 2026-11-07 he tried to make a quick .txt, opened TextEdit, got forced into a rich text file, and had to rename it by hand. Today he bounces between TextEdit, Preview, Adobe and online converters depending on the file type.

## The job it does (and what it replaces)
Open any everyday document, read it or make a quick edit, change its format, and save, without choosing an app first. It replaces TextEdit (defaults to RTF, hides the format), Preview (good viewer, no real conversion, no text editing), Adobe Reader, and ad-hoc web converters. It is deliberately not a notes app or vault: Obsidian was rejected for its vault model, clunkiness, and lack of conversion.

## Competitors
Researched 2026-11-08. Review complaints are from general knowledge, not verified reviews.

| App | Price | What it does | Where OpenText wins or skips |
|---|---|---|---|
| Preview / TextEdit (built in) | Free | Viewer; rich-text-first editor | Wins: plain text by default, conversion, one opener for everything. Skips: Preview's deep markup at first |
| MarkEdit | Free (MIT) | Minimal native Markdown editor | Wins: opens PDF/images/docx, converts, encrypts |
| CotEditor | Free (Apache 2.0) | Native plain-text editor, `cot` CLI | Wins: Markdown preview, viewing, conversion |
| Plainfile | Free | New (Oct 2026) native editor for text, code, Markdown, CSV | Nearest new entrant on the editor side; text only |
| iA Writer / Typora | $49.99 / $14.99 one-off | Writing-focused Markdown editors | Skips: writing-craft features. Wins: free, not library-centric |
| BBEdit | ~$59.99 | Pro text editor with CLI | Skips: code-editor depth. Wins: simplicity, viewing, conversion |
| Permute 3 | $14.99 | Media converter | Wins: documents and text, not just media |
| Encrypto / Cryptomator | Free | Per-file AES-256 / encrypted vaults | Wins: built into the opener, documented format, no vault |
| New File Menu / iBoysoft MagicMenu | $1.99 / ~$19.60 a year | Finder "New file" | Built in, no extra utility |

No app found combines an editor, converter, Finder "New file" and encryption. The only apps with CLI plus MCP (Drafts, Clearly) are notes/vault products, so a stateless conversion engine for AI agents is open ground.

## Positioning
For Walker, who is tired of picking an app for every file, OpenText is one fast Mac document app that opens every everyday file and lets him read, edit, convert or lock it in place, and lets his AI tools do the same. Unlike Preview and TextEdit, it never asks which app or which format first. (Brand tagline from the pack: "Fuck Preview.")

## Price and business model
Free, personal tool. No business model in V1. Revisit only if Walker decides to ship, which would also bring App Store sandboxing questions (Finder integration, default-opener behaviour).

## V1 and V2
Approved: 2026-11-08

### V1
- Default opener — registered handler for images, PDF, .txt and .md; Walker sets it as default for all four.
- Text editor — .txt and .md, plain text by default (never RTF), Markdown preview toggle.
- Title-bar format switcher — the file extension in the title bar is a control: click `.txt`, pick `.md`, done.
- PDF viewer — fast zoom, page thumbnails, search, highlight text, sign (saved signature placed on the page), combine PDFs and reorder/delete pages by dragging thumbnails.
- Image viewer — zoom, crop, resize, rotate/flip, then save or convert.
- Other-document viewing — read-only docx, rtf, html and similar, with "Extract text" and "Convert to…".
- Conversion engine — one core shared by app, CLI and MCP, built on macOS built-ins (textutil, PDFKit, Vision OCR, ImageIO). No paid APIs.
- CLI — `opentext convert report.pdf --to md` and friends; same operations as the app.
- MCP server — lets Claude Code and other agents create, convert, extract text from, and lock/unlock files.
- Finder integration — right-click "New Text File" / "New Markdown File" in any folder and on empty Desktop space, plus a "Convert to…" Quick Action.
- Quick create — a global keyboard shortcut and a menu bar icon (by the clock) that pop a small picker: choose the type, name it, and the file is created in the default folder (Desktop to start, changeable in settings) and opened.
- Lock / unlock — "Convert to → Locked" wraps any file with AES-256 (CryptoKit) and a slow password-based key derivation; the file format is documented so a locked file can be opened without the app in an emergency. Unlock with the password or Touch ID; a one-time recovery key, printed or stored offline, covers a forgotten password.

### V2
- Handwriting photo → Markdown — on-device Vision handwriting recognition.
- Voice memo → text — on-device speech recognition; may connect to Walker's separate speech-to-text project.
- Hardware security key unlock — a YubiKey-style key as an extra or alternative unlock factor. Needs a feasibility check and Walker has to find the key.

### Not doing
- Backlinks / wiki-links / "connections" graph — Walker doesn't value them ("generally futile").
- Notes storage, library or vault — he'll use it for one-offs, not as a home for notes.
- Sync — files live where Finder puts them.
- iPhone / iPad — Mac only.
- App Store release — personal tool for now.
- Creating images — images are viewed and converted, not authored.

## Name check
| Check | Result | Date |
|---|---|---|
| App Store search | OpenText: blocked — Open Text Corporation already publishes Mac/iOS apps (OpenText UFT Agent, Voltage SecureFile) | 2026-11-08 |
| Domain | opentext.com and opentext.app both registered | 2026-11-08 |
| Trademark (USPTO) | OpenText Corp (NASDAQ: OTEX) holds software marks; filing not pulled, TESS not queryable from here | 2026-11-08 |
| Social handle | GitHub and X handles taken | 2026-11-08 |

Alternatives checked the same day: Plainfile (blocked, a live free Mac editor of that name), Anyfile, Recast, Ferry (risky, existing apps), Docshift (least conflicted, but .com and .app are both registered and trademark is unchecked). Fine as a private codename; needs a real name before any release.

## Data and licenses
No outside data, content or paid APIs. Core work uses Apple system frameworks and tools (PDFKit, Vision, CryptoKit, ImageIO, `textutil`), which carry no licensing issue for a personal Mac app. Any open-source library (Markdown rendering, key derivation) must be MIT, Apache 2.0 or BSD and gets its license checked before it is added.

## Success measure
30 days after the first build Walker uses daily: he hasn't gone back to Preview or TextEdit for images, PDF, .txt or .md, and opening or creating a document feels enjoyable, not neutral (his own call).
