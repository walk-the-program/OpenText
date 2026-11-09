# Findings — 2026-11-09 ui

Scope: commit a08be7a. All OpenTextUI views rendered off-screen (`swift test --filter SnapshotTests` in Packages/OpenTextUI), 1280x800 at 2x, light and dark. Checked against `design/brand.json` and the BUILD-PACK UI kit. Mac app, so the iPhone sizes in the refine template don't apply. The app itself was not launched.

IDs: UI-001 onward. Severity: P1 broken or blocks release, P2 clearly wrong and visible, P3 polish. Before shots: `screenshots/before/`.

## UI-001 — Edit/Preview spends the primary colour twice
- Severity: P2
- Screen: text editor, both modes (`text-editor-*`, `text-editor-preview-*`)
- Problem: the selected Edit/Preview segment is filled `Palette.primary` next to the primary Convert button, so the toolbar has two blue fills. The two segments also read as two loose buttons, not one control. BUILD-PACK rule 2: primary on one button per screen; the selected segment uses `Palette.ink`.
- Fix: one recessed track holding both segments; the selected segment is ink with canvas text, the other is clear with ink text.

## UI-002 — Heading letters touch
- Severity: P2
- Screen: every title (window titles "gift-ideas", "Set up OpenText", setup card titles, "Locked", "Your recovery key", "Convert .pdf")
- Problem: `brandHeading` applies -0.04em at every size. On Inter Tight below 22pt the letters collide. The kit uses -0.04em only for 22pt card and dialog titles and -0.03em for the 17pt top bar.
- Fix: -0.04em at 22pt and up, -0.03em below.

## UI-003 — Smudgy halos around small raised controls
- Severity: P2
- Screen: format chip, secondary buttons (Set again, Turn on…, Change, Cancel, Copy, Save as Text, Unlock, Save), worst in dark
- Problem: small controls use the card-sized raised shadow (5pt blur, 3/4pt offset), so 24–28pt controls get a grey or black cloud. Disabled buttons keep the lift.
- Fix: a control-sized raised depth for chips and buttons; cards keep the current depth. Disabled secondary buttons go flat.

## UI-004 — Recessed fields show a hard dark bar
- Severity: P2
- Screen: quick create name field, password field, recovery key well, search field
- Problem: the inner shadow is a 3pt band with 2pt blur, so the top and left edges look like a dark border rather than a soft press.
- Fix: wider, softer inner shadow at lower strength; same top-left light.

## UI-005 — Convert and recovery sheets differ from the other sheets
- Severity: P3
- Screen: `convert-sheet-*`, `recovery-key-sheet-*`
- Problem: these two fill with `surface` while the app's other sheets (App/Views/Sheets.swift) fill with `canvas`; in the snapshots the square fill also pokes out of the rounded panel.
- Fix: canvas fill like the other sheets; snapshot clips the panel to its corners.

## UI-006 — Setup snapshot doesn't match the real window
- Severity: P3
- Screen: `setup-*`
- Problem: rendered at 1280x800 with half the window empty; the app opens it at 900x440 (App/Views/SetupHost.swift), which was never checked for fit.
- Fix: render at 900x440 and make the three cards fit without clipping.

## UI-007 — Snapshot fixtures misreport content
- Severity: P3
- Screen: `pdf-reader-*`, `image-editor-*`
- Problem: the lease fixture's first line runs off the page edge; the photo fixture is a drawing-handler image, so the editor shows 8064 × 6048 for a 4032 × 3024 photo.
- Fix: wrap the fixture lines; build the photo as a 4032 × 3024 bitmap.

## UI-008 — Lighter band behind the PDF page in snapshots
- Severity: P3
- Screen: `pdf-reader-*`
- Problem: a lighter column sits behind the page. It comes from the off-screen still drawn over the live PDFView, which renders blank off-screen.
- Fix: none here; check on the first real launch.

## UI-009 — Titles still tight after UI-002
- Severity: P2
- Screen: setup card titles, window titles
- Problem: Inter Tight ships with only a weight axis and is already tightly spaced, so even -0.03em made letters touch in CoreText.
- Fix: -0.02em at 22pt and up, -0.01em below.

## UI-010 — Selection also spent the primary colour
- Severity: P2
- Screen: quick create (selected type chip), convert sheet (selected format row)
- Problem: the selected item was primary next to the primary Create / Convert button (BUILD-PACK rule 2).
- Fix: selected item is ink with canvas text.

## Status

| ID | Severity | Screen or area | Summary | Status | Fix commit |
|---|---|---|---|---|---|
| UI-001 | P2 | Text editor | Edit/Preview is one recessed control; ink selection | fixed | c79ffd3 |
| UI-002 | P2 | All titles | Heading tracking by size | fixed (superseded by UI-009) | 75eca71 |
| UI-003 | P2 | Chips, secondary buttons | Control-sized raised shadow; disabled goes flat | fixed | 4ad275c |
| UI-004 | P2 | Fields, wells | Softer inner shadow | fixed | bb86c5f |
| UI-005 | P3 | Convert, recovery sheets | Canvas fill like other sheets; snapshot clipped | fixed | 8d068dd, fb0aa2c |
| UI-006 | P3 | Setup | Rendered at real 900x440; cards equal height, buttons aligned | fixed | b54fbb7, fb0aa2c |
| UI-007 | P3 | Snapshot fixtures | Lease lines wrapped; photo is a real 4032x3024 bitmap | fixed | fb0aa2c |
| UI-008 | P3 | PDF reader | Lighter band behind page is an off-screen artifact | won't fix (check at first launch) | |
| UI-009 | P2 | All titles | Tracking -0.02em / -0.01em for Inter Tight | fixed | 43eb27e |
| UI-010 | P2 | Quick create, convert sheet | Selection in ink, primary only on the action | fixed | 021c89e |

Round log: Round 1 shot 2026-11-09, 8 findings. Round 2 shot 2026-11-09, 2 new (UI-009, UI-010), 0 P1/P2 open.
