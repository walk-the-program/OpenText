# Mesh Gradient round — plan (2026-11-10)

Owner of this file: coordinator (Opus). Workers report in their return messages, not here.

## Request (Walker, 2026-11-10)
1. Replace the Soft Form look with the new build pack (`BUILD-PACK.md`, Mesh Gradient). Use it as the UI guide; don't port its web code literally; no art, no patterns, logo untouched.
2. Fix the font feeling squished (Inter Tight + negative tracking is gone).
3. Premium, bouncy, active-but-clean motion.
4. PDF editing: signatures must be movable; the whole PDF toolset refined.
5. Refine every remaining product piece.

## Shared decisions (contract rev 1)
- **Faces:** Plus Jakarta Sans (display: Light 300, SemiBold 600), Inter (body: Regular 400, Medium 500, SemiBold 600), Geist Mono (600, mono). Inter Tight is removed. Font sources already on disk (OFL): `/Users/walker_tracy/Desktop/Projects/Signl/design/generated/fonts/PlusJakartaSans.ttf` (variable), Inter statics already in `Packages/OpenTextDesign/Sources/OpenTextDesign/Fonts/`, Geist Mono at `/Users/walker_tracy/Desktop/Looks Good/fonts/woff/geist-mono-01c0aaee.woff` (variable WOFF) or the static Regular/Bold TTFs under `~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/*/*/skills/canvas-design/canvas-fonts/`. No downloads.
- **Mac type scale** (the pack's phone scale translated to macOS; tracking 0 unless stated):
  Display Jakarta Light 30/36, -0.01em · Large title Jakarta SemiBold 26/32, -0.01em · Title Jakarta SemiBold 22/28, -0.01em · Title 2 Jakarta SemiBold 17/22, -0.01em · Headline Inter Medium 14/19 · Body Inter Regular 14/20 · Callout Inter 13/18 · Footnote Inter 12/16 · Caption Inter SemiBold 11/14 · Label Inter SemiBold 11/14 uppercase +0.1em · Button label Inter SemiBold 13, -0.01em.
- **Mac sizes:** buttons 34pt high, pill; fields 32pt, radius 12; cards radius 20, 1pt `line` hairline + two-layer neutral shadow; list rows 36pt (44pt with a detail line); 8pt grid from the pack's spacing list; 24pt window margins, 28pt between sections. Mac minimum hit area 28pt.
- **Colours:** only the pack's tokens (Part 1 Colors, Part 2 Theme.swift), light and dark as designed. Gradient only on the primary button (135°, `primary` to `abMHue`), the selected segment (140°), progress fills, and the selected-tab pill. Cards are opaque `card` white. Errors use `error` (= ink), never red.
- **Motion** (Walker's request overrides the pack's plain ease-out): springs. `Motion.press` = spring(response 0.22, damping 0.62), press scale 0.97. `Motion.settle` = spring(response 0.36, damping 0.74) for selection, hover and state. `Motion.enter` = spring(response 0.42, damping 0.8) for sheets, panels and content appearing (opacity + scale 0.98 to 1 + 6pt rise). The selection indicator slides between segments and chips (matchedGeometryEffect). Cards and rows lift 1pt with a deeper shadow on hover. Notices and toasts slide in. Home content staggers in once on open (30 ms steps, at most 6 items). Nothing loops idly except loading indicators. Reduce Motion means instant state swaps; colour changes still animate.
- **API compatibility:** OpenTextDesign keeps its public names working (`Brand.Palette.*`, `Brand.Fonts.*`, `.primaryAction`, `.secondaryAction`, `.toolbarItem`, `raisedSurface`/`recessedSurface` may become aliases of the new card or field surfaces), so W2 compiles against either version. New names may be added.
- **Buttons never change view identity on press or hover** (BTN-1a lesson). Value-only changes.

## Tasks
| ID | Owner | Writable | Depends | Status |
|---|---|---|---|---|
| MESH-1 Design system + restyle of every non-PDF view + motion | Sonnet W1 | `Packages/OpenTextDesign/**`, `Packages/OpenTextUI/Sources/OpenTextUI/*` except `PDF*.swift`, `SignaturePad.swift`, `CropGeometry.swift`; `App/Views/*` except PDF; `design/brand.json`; `docs/decisions.md`; `Packages/OpenTextUI/Tests/**/__Snapshots__` for non-PDF views | none | running |
| PDF-1 PDF editing toolset rework | Sonnet W2 | `Packages/OpenTextUI/Sources/OpenTextUI/PDF*.swift`, `SignaturePad.swift`, `CropGeometry.swift`, a new `PDFAnnotations*.swift`, PDF tests, PDF parts of `App/Services/DocumentSession.swift` (save path only), new self-test scenarios in `App/Services/SelfTestScenarios.swift` (append-only, PDF scenarios) | none | running |
| POLISH-1 Restyle PDF views to the kit, product polish pass on every view, full verify | Sonnet W3 | everything | MESH-1, PDF-1 accepted | planned |

Shared files: `scripts/selftest.sh` is W2's only for appending scenario names. `project.yml` belongs to W1 (fonts); W2 asks the coordinator if it needs a change. Commits go straight to main, each prefixed with its task ID. Before committing, each worker runs `git pull`-free `git status` and commits only its own paths (`git add <paths>`, never `git add -A`).

## Acceptance (coordinator checks)
1. No Inter Tight left anywhere; headings Jakarta, body Inter, as in the scale above.
2. Every view uses the kit components; no Soft Form raised or recessed neumorphic surfaces remain.
3. Primary gradient only where the contract allows.
4. Light and dark snapshots re-recorded and visually checked by the coordinator.
5. Springs on press, selection, enter and hover; Reduce Motion respected.
6. PDF: a signature can be placed, moved, resized and deleted, with undo; it is burned into the page on save, and the crop box is kept.
7. All `swift test` suites pass; `scripts/selftest.sh` passes all scenarios with zero exceptions; frontmost app unchanged.
8. One installed copy, via `scripts/install.sh` (coordinator).
