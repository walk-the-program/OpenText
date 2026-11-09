# Kickoff notes

Running log for app-kickoff. Update after every answer that settles or changes something.

## Topic status
| Half | Topic | Status | Key answer |
|---|---|---|---|
| Product | Who it's for | done | Walker, personal tool; TextEdit-forced-RTF incident 2026-11-07 |
| Product | Job and what it replaces | done | Open/read/quick-edit/convert any doc; replaces TextEdit, Preview, Adobe, web converters |
| Product | Competitors | done | 9 rows in one-pager; gap = editor+converter+Finder+encryption in one opener; CLI/MCP only in notes apps |
| Product | Positioning | done | Walker: "whatever you think is fine"; proposed sentence accepted |
| Product | Price and business model | done | Free personal tool, no business model in V1 |
| Product | V1 and V2 | done | Viewer scope (D-009), unlock (D-010), quick create (D-011) added; needs approval in words |
| Product | Name check | done | Keep OpenText as private codename (D-008); rename before any release |
| Product | Data and licenses | done | No outside data; Apple frameworks; OSS must be MIT/Apache/BSD |
| Product | Success measure | done | 30 days, no going back to Preview/TextEdit, feels enjoyable |
| Product | Owner blockers | done | Signing identity present; hardware key to find (V2) |
| UX | Key screens | done | Proposed: document window + quick create panel; awaiting Walker |
| UX | First 30 seconds | done | Proposed 3-tile setup window; awaiting Walker |
| UX | Feel | done | From BUILD-PACK: Modular, Clear, Warm + Walker's "enjoyable" |
| UX | References | done | Liked Preview, the pack; hated TextEdit, Obsidian, Adobe |
| UX | Hard nos | done | Seeded from pack + known dislikes; awaiting Walker's confirm |
| UX | Platform and sizes | done | Mac only, macOS 26, 1280x800 + 1512x982; editor font open |
| UX | Directions to render | done | 3 layout directions within the locked pack; awaiting Walker |

## Threads to pull
- The "Tracy Christmas password" file: what's actually in it? Real passwords (password-manager job) or private content (locked doc job)?
- Shortcut collisions with the speech-to-text app's shortcut.
- "Enjoyable" is the success bar: feeds the Feel topic directly.
- Separate speech-to-text project: name, state, and whether V2 voice→text should reuse it.
- "Every part editable": Walker was unsure; working meaning recorded in D-005. Confirm if it comes up again.
- What Walker does in Preview today (sign, fill forms, annotate, crop, combine PDFs) — sets V1 viewer scope.
- Look-lock renders for the phone; this is a Mac app, so app-look-lock renders at 1280x800 and 1512x982 in the browser, and freezes brand.json from BUILD-PACK rather than inventing a palette.

## Contradictions to resolve
- BUILD-PACK is phone-first (44pt targets, tab bar, 17pt body, bottom sheets) but the app is Mac only (D-001). Resolved in ux-brief: keep palette, faces, materials and primary rule; translate sizes and navigation to Mac.

## Log
- 2026-11-08: Walker approved the full kickoff summary in words ("Approved"). Editor font set by default recommendation (D-016). Handing off to app-idea-gate.
- 2026-11-08: Walker accepted positioning and success measure as proposed. BUILD-PACK.md (Looks Good, Bento Grid × Soft Form) saved to project root and translated into ux-brief.
- 2026-11-08: Recovery key (D-012) and default folder (D-013) settled. Apple Development signing identity found on this Mac.
- 2026-11-08: Viewer scope, unlock methods, quick-create surfaces settled (D-009 to D-011).
- 2026-11-08: Competitor and name research back. OpenText, Plainfile blocked; Docshift least conflicted.
- 2026-11-08: Brainstorm settled scope; D-001 to D-007 recorded. Competitor + name research started.
