# Patch Notes — LRGEX Folder Sync

## v1.0.6
- **Auto-update system**: app checks for updates on launch, downloads and swaps the exe via self-replace, relaunches automatically.
- **Deploy pipeline**: deploy.ps1 + deploy.bat for one-click build + upload to server + GitHub Releases.
- **MSVC toolchain**: switched from stable-gnu to stable-msvc (native Windows, smaller binaries, no MinGW).
- **Version single-source-of-truth**: gui.rs and update.rs use env!(CARGO_PKG_VERSION). deploy.ps1 reads from Cargo.toml (read-only).
- **README rewritten** as marketing copy.
- **Guideline updated**: Slint section + auto-update (Approach 3) added to Rust guidelines.
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
