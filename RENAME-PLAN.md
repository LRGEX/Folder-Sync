# Project Rename Plan

> **ABSOLUTE RULE: SED IS PROHIBITED. NEVER USE SED. NEVER. NEVER. NEVER.**
> **MANDATORY: Use `write` tool and `edit` tool ONLY. No exceptions. Ever.**
> **The words "Folder Sync" are ELIMINATED from EVERYWHERE — code, registry, tasks, URLs, docs, internal names. No exceptions.**

---

## Pre-Existing Bug: Sed-Corrupted Registry Path

During this session, sed corrupted config.rs:150. The backslashes were eaten:
- **Original (correct):** `SOFTWARE\LRGEX\FolderSync`
- **After sed corruption:** `SOFTWARErgexfoldersync` (no backslashes — BROKEN)

Both registry keys now exist on the machine because:
- Old builds (before corruption) wrote to the correct path `HKCU\SOFTWARE\LRGEX\FolderSync`
- Broken builds (after corruption) wrote to the mangled path `HKCU\SOFTWARErgexfoldersync`

**Fix:** Delete the mangled key, fix the code to use correct path, keep the correct key.

**Migration must check ALL of these old locations:**
1. `HKCU\SOFTWARE\LRGEX\FolderSync` (correct path — original)
2. `HKCU\SOFTWARErgexfoldersync` (mangled path — from sed corruption)

---

## Migration Code — Legacy Cleanup Module

All old name strings go in a SINGLE `legacy_migration` module:
- Marked: `// DELETE THIS MODULE after all users have migrated (N+1 release)`
- Contains old names needed to FIND and CLEAN UP old entries
- Removed entirely in the release AFTER users migrate

This is the ONLY place old name strings exist. Nowhere else.

**On first launch of the renamed app:**

1. Old scheduled task `LRGEX-FolderSync-Rust` exists? → DELETE, register NEW
2. Old context menu `HKCU\...\shell\LRGEXSync` exists? → DELETE, register NEW
3. Old registry key exists (check BOTH paths above)? → COPY to NEW key, DELETE old
4. Old `.lrgex-home` marker text? → Recognize as existing home, update marker
5. Self-updater uses `current_exe()` — works regardless of name

---

## Server URL Transition

Old URL must redirect to new URL so deployed clients reach the transitional update.
After all clients update, old URL can be removed.

---

## Full Replacement List — "Folder Sync" ELIMINATED everywhere

### Cargo.toml (2)
- `name = "folder_sync"` → NEW
- `name = "LRGEXSync"` → NEW

### src/gui.rs (14)
- Line 32: window title → NEW
- Line 133: UI sidebar text → NEW
- Line 579: About dialog title → NEW
- Line 654: "already installed" message → NEW
- Line 1106: export filename → NEW
- Line 1455: uninstall batch (task + registry) → NEW
- Line 1676: first-run setup text → NEW
- Line 1690: exe name fallback → NEW
- Line 1693: home marker text → NEW
- Line 1751: context menu registry check → NEW
- Line 1763: context menu registry create → NEW
- Line 1764: context menu display text → NEW
- Line 1781: context menu registry delete → NEW

### src/update.rs (2)
- Line 5: manifest URL → NEW
- Line 60: temp exe name → NEW

### src/sync.rs (2)
- Line 537: exe name in task → NEW
- Line 554: scheduled task name → NEW

### src/health.rs (2)
- Line 37 + 49: scheduled task name → NEW

### src/config.rs (2 + bug fix)
- Line 150: registry path → NEW (ALSO fix sed-corrupted backslashes)
- Line 170: registry subkey → NEW

### src/main.rs (2)
- Line 37: mutex name → NEW
- Line 96: mutex name → NEW

### build.rs (1)
- Add product metadata with NEW name

### deploy.ps1 (5)
- UPLOAD_PATH, DOWNLOAD_BASE, EXE_NAME, release notes, GitHub URL → NEW

### Documentation
- README.md: all references → NEW
- patchnotes.md: current version header → NEW
- AGENT.md (gitignored, local) → NEW
- Wiki (7 pages) → NEW

### External
- GitHub repo: rename
- Server folder: rename or new
- Old URL: redirect

---

## Execution Checklist

1. [ ] Fix config.rs:150 registry path (sed corruption)
2. [ ] Write legacy_migration module (old names for cleanup)
3. [ ] Update Cargo.toml
4. [ ] Update ALL source files via write/edit tools
5. [ ] Update build.rs metadata
6. [ ] Update deploy.ps1
7. [ ] Update README.md, patchnotes.md
8. [ ] Build + test
9. [ ] Commit + push
10. [ ] User renames GitHub repo
11. [ ] User sets up server URL redirect
12. [ ] Update wiki (7 pages)
13. [ ] Deploy

---

## Logo: No change needed
Logo says "LRGEX" only.
