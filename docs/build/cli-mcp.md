# CLI and MCP server

Both are built from `Packages/OpenTextKit` and call the same code (`OpenTextTools` in OpenTextKit), so they do the same things as the app. Everything is local; nothing uses the network.

```
cd Packages/OpenTextKit && swift build -c release
# binaries: .build/release/opentext   .build/release/opentext-mcp
```

## CLI: `opentext`

Add `--json` to any command for machine-readable output. Errors print a message to stderr and exit 1 (with `--json`, also `{"error": "..."}` on stdout). Bad usage exits with ArgumentParser's usage code.

| Command | What it does |
|---|---|
| `opentext convert <files…> --to <fmt> [--out <path>] [--overwrite] [--no-ocr]` | Convert. Writes next to the input; picks `name 2.ext` unless `--overwrite`. PDF to png/jpg writes `name-1.png`, `name-2.png`… (just `name.png` for a one-page PDF). `--out` only with one input. |
| `opentext text <file> [--no-ocr]` | Print plain text (txt, md, rtf, html, docx, doc, odt, pdf). Scanned PDF pages use on-device OCR. |
| `opentext new <fmt> [name] [--in <dir>]` | Create an empty txt/md/csv/html file. Folder defaults to `defaultFolder` in settings. |
| `opentext combine <pdfs…> --out <file>` | Merge PDFs in order. |
| `opentext images-to-pdf <images…> --out <file>` | One page per image. |
| `opentext lock <file> [--out <path>] [--remove-original]` | Encrypt to `.otlock`. Adds the recovery slot if `recoveryPublicKey` is set in settings. `--remove-original` moves the original to the Trash. |
| `opentext unlock <file> [--recovery-key <key>] [--out <path>]` | Decrypt with the password or a recovery key. |
| `opentext formats [<fmt>]` | Formats and what each converts to. |

Password for `lock`/`unlock`: environment variable `OPENTEXT_PASSWORD`, otherwise a no-echo prompt (twice when locking). Settings file: `~/Library/Application Support/OpenText/settings.json`, overridable with `OPENTEXT_SETTINGS_PATH`.

Formats: txt md rtf html docx doc odt csv json pdf png jpg heic tiff gif webp otlock. webp is read-only (ImageIO cannot write it), so converting to webp is reported as unsupported. `otlock` is only produced by `lock`.

Example JSON result from `convert`: `{"outputs": ["/path/a.html"], "results": [{"input": "/path/a.md", "outputs": ["/path/a.html"]}]}`.

## MCP server: `opentext-mcp`

stdio transport, JSON-RPC 2.0, built on the official MCP Swift SDK (protocol version 2025-06-18). Handles `initialize`, `notifications/initialized`, `tools/list`, `tools/call`, `ping`. Tool failures come back as results with `isError: true` and the message as text. Successful results carry the JSON as text and as `structuredContent`.

| Tool | Arguments (required in bold) |
|---|---|
| `convert` | **files** (string[]), **to**, out, overwrite, ocr |
| `extract_text` | **file**, ocr |
| `create_file` | **format** (txt/md/csv/html), name, folder |
| `combine_pdfs` | **files**, **out** |
| `images_to_pdf` | **files**, **out** |
| `list_formats` | format |
| `lock_file` | **file**, **password**, out |
| `unlock_file` | **file**, password, recovery_key, out |

Each tool publishes a JSON Schema via `tools/list`.

### Claude Code setup

After `swift build -c release`, register it (adjust the path to this checkout):

```
claude mcp add opentext -- /Users/walker_tracy/Desktop/Projects/OpenText/Packages/OpenTextKit/.build/release/opentext-mcp
```

Or in `.mcp.json` / `~/.claude.json`:

```json
{
  "mcpServers": {
    "opentext": {
      "command": "/Users/walker_tracy/Desktop/Projects/OpenText/Packages/OpenTextKit/.build/release/opentext-mcp"
    }
  }
}
```

Passwords for `lock_file`/`unlock_file` are tool arguments, so they appear in the agent's transcript. Prefer the CLI with `OPENTEXT_PASSWORD` when that matters.

## Safety rules (engine-enforced)

- Output paths: a destination that is an existing folder is refused, and its extension must match the target format (`out: ~/.zshrc` or `out: ~/Documents` fails with an error). `overwrite` replaces an existing file atomically (staged in the destination folder, then `replaceItemAt`), so a failed write keeps the old file.
- MCP: `out`, `file` and `files` must be absolute or start with `~`; relative paths are rejected. `lock_file` has no `recovery_public_key` or `remove_original` argument: it always uses the recovery key from settings and never deletes the original. The CLI (run by a human) keeps `--remove-original` and relative paths.
- `opentext lock --remove-original` decrypts the written .otlock in memory and compares bytes before moving the original to the Trash. If the Trash move fails, the command errors (`originalNotRemoved`) and the .otlock stays.
- `OPENTEXT_PASSWORD` is visible to other processes of the same user (environment, `ps eww`). Prefer the no-echo prompt.
- Unlock accepts PBKDF2 iteration counts of 600,000 to 10,000,000 only; anything else is a damaged file.
- Markdown to HTML (used for rtf/docx/odt) escapes raw HTML and renders images as their alt text, so conversion never loads remote or `file://` resources.
