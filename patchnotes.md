# Patch Notes — LRGEX Folder Sync

## v1.2.19 — UX Overhaul + Compression Optimization
- Compression: zstd level 1 (2x faster than level 3)
- Compression: locked files skipped + reported (never silent, never aborts)
- Browse: folder picker starts at current path + auto-adds to sync list + immediate backup
- About button beside Tools (logo + version + info overlay)
- Window locked to 560x700 (no maximize)
- Folder list stretches + scrolls for 100+ folders
- Deselect: click selected folder again to toggle off
- Remove: asks to also delete backup files (with path traversal + empty-name guards)
- Restore: pre-check ALL folders before touching any (no partial restores)
- Restore: atomic rename-swap extraction (destination never half-written)
- Restore-all confirmation dialog
- Close guard: warns if backup or restore is running (instant flag, no timing gap)
- Health bar: no more OK overwrite during active compression
- Startup temp sweep: cleans orphaned temp files from killed processes
- Honest backup messages: file count + size + skipped count


## v1.2.18 — Game Lamp + Skip-List + Real-World Tested
- Game detection lamp per folder (green = game saves detected, cached in config)
- Column headers in folder list (Path | Game | Auto | Versions)
- Skip-list: scanner skips node_modules, .git, target, build, __pycache__, etc.
- Restore Folder button now sets migration marker (was missing — migrations never triggered after manual restore)
- Three-state classification hardened with weighted scoring (Unknown is reachable + tested)
- REFUSED messages hidden from health bar (logged only — non-game numeric dirs like npm year folders)
- Real-world tested: delete → restore → create empty ID → reopen → saves auto-migrated



## v1.2.17 — Post-Launch Migration + Research-Backed Detection
- Migration now fires on GUI launch (background thread, 3s delay, zero UI freeze)
- No more waiting for sync interval after format — open the app, saves migrate instantly
- Post-launch checks orchestrator: extensible pattern for future checks (panic-isolated, documented)
- Migration marker only clears on real migration (stays until saves actually copied)
- Save detection patterns expanded from research on 1,460 games (SaveGameExtractor database)
- Added: saved (116 UE games), saved games (100), savegame (19)
- Removed: wgs (unreachable in current scanner, UWP paths have no numeric IDs)




## v1.2.16 — Save-ID Migration Hardened
- Three-state classification: HasSaveData / FreshInstall / Unknown — refuses migration if ANY folder is ambiguous
- Weighted scoring: save dirs +100, SAVEFILE*/autosave* +50, *.sav/*.save +30, 6+ files +20
- Unknown is now reachable and tested — ambiguous folders abort migration with logged REFUSED message
- Expanded save detection: 9 directory patterns + 6 filename patterns
- Deterministic source ranking: save count > bytes > mtime
- Universal scan (any numeric ID parent, not just users/userdata)
- Post-restore gate: marker file, 7-day window, zero cost on normal syncs





## v1.2.15 — Auto Save-ID Migration
- **Auto-migrates game saves when numeric user-ID folders change after format/reinstall
- Detects old folder (has saves) vs new empty folder (game-created) and copies saves over
- Scoped to users and userdata directories only — never touches unrelated folders
- Smart source selection: most recent saves, tiebreak by file count
- Target safety: only migrates into folders with no save data AND ≤5 files (prevents clobbering)
- Non-destructive: never deletes, never overwrites existing files
- Runs automatically after restore and on every sync cycle
- Sync mutex prevents concurrent sync processes from stacking
- Temp compression in %TEMP% (outside OneDrive) — 10x faster for large folders
- PID-based stale progress detection with 10-min mtime backstop






## v1.2.14 — Sync Reliability Overhaul

### Critical Fixes
- **Sync mutex** — prevents concurrent sync processes from stacking up (was the root cause of stuck "Compressing..." forever)
- **PID-based stale progress detection** — health bar auto-clears if sync process dies or PID gets reused (10-min mtime backstop)
- **Temp file now in %TEMP%** — compresses outside OneDrive, ~10x faster for large folders (Hermes: 10min → ~90s)
- **PID-unique temp filenames** — prevents file corruption if two syncs ever collide
- **Single-pass compression** — eliminated redundant directory walk (was scanning folder twice)

### Restore Improvements
- **Restore now shows real failure state** — red "Restore Failed" with exact reason per folder (was showing fake success)
- **Program Files detection** — failure message tells user to run as admin when target needs elevation
- **Partial restore handling** — shows "Partial: X of N" with failed folder names

### UI Polish
- **Restore overlay enlarged** (460x280) with proper padding + word-wrap for multi-line errors
- **Live compression progress** — shows percentage + file count during compression
- **"Scanning..." feedback** during folder pre-walk (no more frozen look on large folders)






## v1.2.13
- Restore progress overlay (impossible to miss)
- Slint-native input dialog replaces ps_inputbox (no more UI freeze)
- Restore runs on background thread






## v1.2.12
- Right-click sync shows confirmation dialog after completion (success or failure with error)






## v1.2.11
- Preview button: browse snapshot in WinRAR/7-Zip (or extract to temp + Explorer)
- "Backup Folder" renamed to "Backup Now"
- "Uninstall" renamed to "Unlink from Windows..."
- Removed unused code (parse_timestamp, SystemTime imports)






## v1.2.10
- Version limit: keep last N snapshots instead of 90-day retention (default 5)
- Tools menu: Set Max Versions... (user-configurable)






## v1.2.9
- Backup Folder compression runs on background thread (UI stays alive, live progress)
- Set Sync Interval no longer hangs (schtasks on background thread)






## v1.2.7
- Cache-buster fix: download URL appends ?v=version (bypasses Cloudflare cache)






## v1.2.6
- Backup Folder button forces compression (no more silent skip)
- Health bar shows "Compressing [folder]..." during manual compression






## v1.2.5
- Exe renamed to LRGEXSync.exe everywhere (Cargo [[bin]] name)
- Batch updater retry loop for OneDrive locks
- deploy.ps1 verifies upload size matches local
- Legacy PS task cleanup on startup
- AGENT.md updated (no VBS, no self_replace references)






## v1.2.4
- Replaced self_replace with batch updater (OneDrive-safe: app exits before copy)
- Copy retry loop in updater batch (handles OneDrive lock)
- Old PS task cleanup on startup
- Click folder in list fills source box






## v1.2.3
- Click folder in list fills source box (can re-sync by clicking Backup Folder)
- Equal-width buttons (min-width + stretch)
- Canonical home registry verified






## v1.2.2
- **Root cause fix**: scheduled task uses canonical home path from registry, not current_exe()
- **No VBS runner**: task runs exe directly (windows_subsystem=windows, zero console flash)
- **Single home enforcement**: registry key HKCU\SOFTWARE\LRGEX\FolderSync\HomePath is the ONE source of truth
- **Migration**: existing installs auto-promote to registry on first launch
- **Stray copy protection**: running from non-home path warns user, refuses to retarget task
- **Uninstall**: clears registry key too






## v1.2.1
- **UI fix**: all 4 bottom buttons equal width (min-width + stretch)






## v1.2.0
- **Compression switched to tar+zstd**: 100x faster than LZMA2, same or better ratio
- **Backup folder structure**: all backups now inside `backup/<folder-name>/` — clean home root
- **No staging**: compresses directly from source (no robocopy temp copy)
- **Rename fix**: copy+delete fallback when OneDrive locks files
- **UI layout fix**: ON/OFF status fixed position, buttons equal width
- **Compression progress**: health lamp shows "Compressing [folder]..." in real-time
- **Health status**: writes immediately on manual sync
- **Right-click confirmation**: Yes/No before syncing
- **Snapshot restore fix**: `.tar.zst` extension detection






## v1.1.3
- **Compression switched to tar+zstd**: 100x faster than LZMA2, same or better ratio. Hermes compresses in seconds, not minutes.
- **No staging**: compresses directly from source (no robocopy temp copy)
- **UI layout fix**: ON/OFF status fixed position, buttons equal width
- **Compression progress**: health lamp shows "Compressing [folder]..." in real-time (3-second polling)
- **Exclusions**: properly skipped during compression
- **Health status**: writes immediately on manual sync, not just scheduled cycles
- **Right-click confirmation**: Yes/No before syncing
- **Health cache**: 3-second timer restores cached health when progress clears






## v1.1.2
- **Compression**: all backups now compressed as .7z (LZMA2) instead of raw files
- **Space savings**: 50 small files compressed from 58K to 3.9K
- **Timestamps preserved**: files restore with exact original modification times (game saves sort correctly)
- **Migration**: existing raw folder backups auto-compress to .7z on first sync
- **Change detection**: file count + total size (catches symmetric add+delete)
- **Versioning**: snapshots are .7z files with hardlink deduplication
- **Corruption handling**: corrupted .7z fails gracefully, logged, no garbage files
- **Uninstall fix**: cleanup runs via detached batch, no UI freeze
- **Self-cleaning scheduled task**: VBS runner with 3-miss grace period
- **Single home enforcement**: blocks second installation






## v1.1.1
- **Uninstall freeze fix**: cleanup runs via detached batch file instead of blocking on UI thread






## v1.1.0
- **Uninstall**: Tools menu -> type "yes" -> removes scheduled task, right-click menu, home marker
- **Single home enforcement**: blocks creating a second home if one already exists
- **VBS runner**: scheduled task runs via wscript.exe (no console window flash), self-cleans after 3 consecutive exe-misses (prevents OneDrive false positives)
- **Non-NTFS fallback**: hardlinks fall back to copy on FAT32/exFAT/network drives
- **Assets folder**: icons moved to assets/
- **Single-home check**: uses health::task_exists() to detect existing installation






## v1.0.8
- **Auto-update fix**: update.rs rewritten with download validation (size check), proper error dialogs at every step, no more silent failures.
- **Assets folder**: icons moved to assets/ for cleaner project structure.
- **Git history purged**: deploy scripts removed from all past commits.
- **.gitattributes**: silenced CRLF/LF warnings.






## v1.0.7
- **Non-NTFS support**: hardlink fallback to copy for FAT32/exFAT/network drives.
- **README cleanup**: stripped to essentials, added Features section.
- **deploy.ps1 read-only**: reads version from Cargo.toml (no auto-bump).






## v1.0.6
- **Auto-update system**: app checks for updates on launch, downloads and swaps the exe via self-replace, relaunches automatically.
- **Deploy pipeline**: deploy.ps1 + deploy.bat for one-click build + upload to server + GitHub Releases.
- **MSVC toolchain**: native Windows toolchain (smaller binaries, no MinGW).
- **Version single-source-of-truth**: gui.rs and update.rs use env!(CARGO_PKG_VERSION). deploy.ps1 reads from Cargo.toml (read-only).
- **README rewritten** as marketing copy.
- **Docs updated** for MSVC, auto-update, and deploy workflow.
- **Clean build**: 0 warnings.






## v1.0.0 — Complete Rust Rewrite
### Architecture
- **Complete rewrite from PowerShell to Rust** (edition 2021, MSVC toolchain).
- **Slint UI** — dark-themed native interface replacing Windows Forms. LRGEX branding, logo, Tools dropdown menu.
- **No more PowerShell dependency** — single self-contained `.exe`, no script execution policy issues.
### Sync Engine
- **Mirror sync (/MIR)** — deletions now propagate to the backup (was copy-only /E in PS version).
- **Hardlink snapshot versioning** — before each /MIR sync, the app creates a full-folder snapshot using NTFS hardlinks. Unchanged files share disk blocks (near-zero space). Only changed files take additional storage. This is how rsync --link-dest and Apple Time Machine work.
- **90-day retention** — old snapshots auto-delete after configurable retention period (default 90 days).
- **Per-file change detection** — snapshots only created when something actually changed (file count, size, OR timestamp). No wasted snapshots on unchanged folders.
- **Version restore** — "Versions" button per folder opens a clickable list of snapshots. Pick a timestamp, restore the entire folder to that point.
### UI
- **Slint dark theme** with LRGEX colors (background #1e1e1e, accent #cb803c).
- **Logo embedded** in the binary via @image-url (compile-time, no runtime file needed).
- **Health lamp** — honest status: RED if task not registered, AMBER if waiting/syncing, GREEN if last sync succeeded. Refreshes live every 30 seconds.
- **Tools dropdown menu** — Health Check, Remove, Export/Import Config, Right-Click Sync, View Sync Log, Set Sync Interval, Manage Exclusions.
- **Backed up folders list** with full paths, auto-restore status, per-folder Versions button.
- **Folder selection** with left accent bar highlight (clean, not full orange fill).
- **No console window** — `#![windows_subsystem = "windows"]` hides the terminal completely.
### Infrastructure
- **Scheduled task self-registration** via `schtasks.exe` (not PowerShell Register-ScheduledTask, which fails with Access Denied on some systems). Task name `LRGEX-FolderSync-Rust` to avoid conflicts with old PS task.
- **First-run setup** — pick home folder, app copies itself there, creates `.lrgex-home` marker, relaunches.
- **Config backward-compatible** — reads PowerShell's PascalCase JSON format (`Junctions`, `SourcePath`, etc.) with BOM stripping.
- **Right-click context menu** — proper registry structure with display name, icon, and command.
- **Log per-installation** — sync.log lives in the home folder, not shared with PowerShell version's LOCALAPPDATA log.
- **Local timezone** — all timestamps use the system's local timezone (chrono crate).
### Versioning Details
- Snapshot folder structure: `_versions/<folder_name>/<YYYYMMDD_HHMMSS>/` (hidden + system attribute).
- Deleted files: hardlinked to snapshot (survives /MIR purge).
- Modified files: old version copied to snapshot (survives /MIR overwrite).
- Unchanged files: hardlinked to snapshot (near-zero space).
- `_versions/` excluded from robocopy via `/XD` to prevent purging.
- One-time migration: old `_trash/` auto-renamed to `_versions/`.
---






## v0.7.0 (PowerShell — superseded by v1.0.0)
- Default sync interval = 120 min (2 hours).
- Decoupled right-click from the sync task.
- Self-healing sync task.
- Synced-folders list in the main UI.
- Absence-driven auto-restore.
- Exclude feature (Manage Exclusions).
- VBS launcher for invisible background sync.
- Custom LRGEX icon in right-click context menu.






## v0.6.x — v0.5.0 (PowerShell — archived)
See git history for details. These versions used Windows Forms + PowerShell + copy-only (/E) sync without versioning.

