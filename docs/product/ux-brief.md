# OpenText — UX brief

Placeholder rule: any line starting with `TODO:` counts as empty to app-idea-gate.

Visual source of truth: `BUILD-PACK.md` in the project root (Looks Good, Bento Grid × Soft Form, supplied by Walker 2026-11-08). The pack was drawn for a phone; this brief records how it translates to a Mac app. Where the pack's phone rules (44pt tap targets, tab bar, bottom sheets, status bar) don't apply to a Mac window, the Mac translation below wins. Palette, type faces, materials and the one-primary rule are kept as locked.

## Key screens
**1. Document window.** One window per file, the screen Walker sees on every double-click.
- PDF example, `Q3-lease.pdf`: title bar shows `Q3-lease` with a `.pdf ▾` chip (the format switcher: Markdown, Plain text, Word, Images, Locked). Left: page thumbnails, drag to reorder, Delete key removes, drop another PDF in to combine. Centre: the page. Toolbar tools: Highlight, Sign, Rotate, Search, Zoom. One primary button: **Convert**. Status line: "Page 3 of 12".
- Text example, `grocery-list.txt`: plain editor, title chip `.txt ▾`; switching to `.md` renames on disk and turns on the Markdown preview toggle (Edit / Preview segmented control). Footer: word count, "Saved".
- Image example, `IMG_4471.HEIC`: image centred; tools Crop, Resize (shows 4032 × 3024), Rotate, Flip; primary **Convert** (JPG, PNG, PDF).
- Locked file, `Tracy Christmas.otlock`: a single tile reading "Locked", with a password field and a "Use Touch ID" button as the one primary.

**2. Quick create panel.** Opened by the global shortcut or the menu bar icon, floating over whatever app is in front.
- Name field pre-filled "Untitled"; type choice `.md` / `.txt` / `.csv` / `.html` (last used is selected); "Save to: Desktop" with a change link; primary **Create** (Return). The file is created and opens in a document window. Escape closes.

## First 30 seconds
1. Walker opens OpenText for the first time. One setup window, no marketing and no account. Three tiles:
   - **Make OpenText your default** for images, PDF, .txt and .md. One button; macOS shows its own confirmation for each type.
   - **Turn on Finder right-click.** The button opens System Settings → Extensions → Finder for him to switch on; the tile shows a check once it's on.
   - **Your new-file shortcut.** Shows the proposed shortcut, editable; warns if it clashes with the speech-to-text app.
2. **Done** closes the window. Nothing else is asked.
3. Walker double-clicks any PDF, image or text file in Finder → it opens in OpenText. That is first value.
4. Locking asks nothing up front. The first time he locks a file he sets a password, turns on Touch ID, and is shown the one-time recovery key to print or save offline.

## Feel
From the pack: Modular, Clear, Warm. Translated for a Mac window:
- **Modular (Bento Grid):** a few large rounded tiles, each doing one job (thumbnails, page, tools), separated by gaps rather than borders. Medium density.
- **Clear:** one big type step (Inter Tight 600 titles) over quiet Inter labels; `Palette.primary` (#98b0cc soft blue) spent on exactly one action per window. High text contrast (ink on canvas 13.4:1).
- **Warm (Soft Form):** soft grey canvas (#e8eaec / dark #252a2e), raised cards and recessed wells lit from the top left, never shiny. Motion quick and eased (120/180/280 ms), nothing idle.
- **Enjoyable** (Walker's success bar): opening a file should feel lighter and calmer than Preview, never busier.
- Mac sizing (proposal, to confirm in look-lock): body 13–14pt Inter, titles 20–26pt Inter Tight, controls 28–32pt high, corners scaled from the pack (buttons ~10pt, cards ~16pt), pointer targets at macOS norms instead of 44pt.

## References
- Liked: Preview — "pretty good actually"; fast, opens everything visual, simple markup. The bar to beat for viewing.
- Liked: the Looks Good pack Walker made (Bento Grid × Soft Form), Apple's feature-grid/Bento layouts.
- Hated: TextEdit — forces rich text, hides the format, makes you rename to .txt by hand.
- Hated: Obsidian — clunky, vault-first, can't just open a document, no conversion.
- Hated: Adobe Reader — one more app to switch to.

## Hard nos
- `Palette.primary` on one button per window plus kit-listed controls only; never as a background, text colour or decoration ("orange everywhere" rule).
- No art, patterns, illustrations, gradients or decorative bands in the app (pack Part 1 and Walker's ornament rule).
- No generic templated looks: no purple gradients, no cream-and-serif default, no identical card grids with stock shadows.
- No colour outside the pack's tokens; errors are drawn in ink, not stock red.
- No marketing onboarding, sign-up or account screens.
- Never default a new document to rich text; never hide the file format.
- No late direction swaps: the look is frozen in look-lock before UI build.

## Platform and sizes
- Mac only, minimum macOS 26 (Walker's current system; personal tool, no older versions to support).
- Window sizes to design for: 1280 × 800 (default document window) and 1512 × 982 (full MacBook Pro screen); quick create panel about 420 × 260.
- Light and dark follow the system, using the pack's designed dark palette.
- Menu bar icon (MenuBarExtra) and a Finder extension; no widgets.
- Accessibility per the pack: 4.5:1 text contrast, visible keyboard focus, Reduce Motion and Increase Contrast honoured, full keyboard use (every action has a menu item and shortcut).
- Fonts: Inter and Inter Tight bundled (SIL Open Font License). Editor font: Inter for .md; .txt opens in Inter with a one-click toggle to SF Mono (D-016).

## Directions to render
All three keep the pack's palette, type and materials. They differ in structure, density and mood, so Walker can see which shape of window feels best on his Mac.

### A — Tile desk
Bento-forward. The window canvas is the soft grey; the thumbnails, the page and the tool panel each sit in their own raised tile with 14pt gaps. Format chip and Convert live in a tile header. Airy, the most visibly "the pack", calm and a little playful. Best at showing off the look; uses the most space.

### B — Native quiet
Mac-native chrome first: system toolbar and sidebar (macOS 26 Liquid Glass), document edge to edge. The pack shows up in colour, type, the format chip, the single primary Convert and the recessed sidebar well. Densest and closest to Preview; the brand is restrained to details.

### C — Command strip
No sidebar at rest. The document fills the window; one floating recessed pill at the bottom holds the format chip, tools and Convert. Thumbnails slide in on demand (⌘T). Minimal and keyboard-first, the most focused; the least discoverable for occasional tools.
