# Security review — commit c67a567 (2026-11-08)

Independent read-only review (Sonnet). No Critical findings. Disposition by the coordinator.

| # | Severity | Finding | Fix | Task |
|---|---|---|---|---|
| 1 | High | Recovery public key lives in editable settings.json and MCP `lock_file` accepted any `recovery_public_key`: a prompt-injected agent or same-user process could add its own recovery slot to every new lock | Drop the MCP argument; add `RecoveryKey.fingerprint`; app pins the fingerprint in its Keychain, shows it in the lock sheet, refuses to lock with a changed key until Walker confirms | T6a engine, T6b app |
| 2 | High | Convert with `overwrite` + `out` removed whatever was at `out` first (a directory, `~/.zshrc`) and could lose it if the move failed | Refuse directories and extension mismatches, atomic `replaceItemAt`, absolute paths only for MCP | T6a |
| 3 | Medium | `opentext://new` and `opentext://convert` run with no gesture from any web page or app | Finder extension signs URLs with a token from a shared app-group file; unsigned URLs need a confirm dialog; paths limited to `$HOME`; rate limit | T6b |
| 4 | Medium | Lock trashed the original with errors swallowed, no round-trip check, plaintext sits in the Trash | Verify by decrypting before trashing, throw `originalNotRemoved`, UI says the original is in the Trash | T6a, T6b |
| 5 | Medium | Autosave during a format switch, no external-change check, Latin-1 files rewritten as UTF-8 | Freeze editor during switch, mtime check before writing, keep original encoding | T6b |
| 6 | Medium | Header `iterations` up to 100M could freeze the app | Accept 600k–10M; unlock off the main thread | T6a, T6b |
| 7 | Medium | Passwords pass through MCP transcripts; agents could lock with `remove_original` (ransom by injection); `OPENTEXT_PASSWORD` visible via `ps` | MCP can't remove originals; docs warn about the env var | T6a |
| 8 | Medium (unverified) | Raw HTML / `<img src>` in Markdown reached textutil's HTML importer, which may fetch remote or `file://` resources | Escape raw HTML, images become alt text | T6a |
| L | Low | Keychain store is delete-then-add; items never removed with their file; empty entitlements may make the data-protection Keychain fail (-34018) so Touch ID silently never works | Add keychain-access-groups entitlement, add-then-update, surface store errors | T6b |

Confirmed fine: AES-GCM nonces random per message with a fresh key per file; payload AAD covers the whole header; salts from the system CSPRNG; no shell or argument injection into textutil; Finder extension sandbox has no file or network entitlements; Keychain flags `biometryCurrentSet` + `WhenPasscodeSetThisDeviceOnly`.
