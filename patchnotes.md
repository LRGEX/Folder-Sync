# Patch Notes — LRGEX Folder Sync

## v0.7.0
- **Default sync interval = 120 min (2 hours)** — was 5 min. Less churn, less resource use. Change anytime via Tools → Set Sync Interval.
- **Decoupled right-click from the sync task** — enabling/disabling the right-click context menu now ONLY manages the File Explorer entry (registry). It no longer starts/stops the background sync task. They are completely independent.
- **Self-healing sync task** — on every GUI launch, the app checks if the background task exists and points to a valid path. If stale (old home deleted) or missing, it unregisters + re-registers with the current home. Zero stale tasks, zero manual cleanup.
- **Removed the broken cloud-detection warning** — hardcoded path matching couldn't detect MEGA/custom cloud locations. Removed entirely; the first-run dialog already recommends a cloud folder. No more false alarms.
- **Fixed GUI hang** — TopMost on the main form caused MessageBoxes to appear behind it (frozen UI / blue circle). Removed TopMost from the main form.
- **VBS launcher for truly invisible sync** — the background task now runs via wscript.exe (no console) instead of PowerShell.exe -WindowStyle Hidden (which flashed a window for ~1 second).
- **Synced-folders list in the main UI** — each linked root folder shown with Auto-Restore status (ON/OFF). Toggle or Remove per folder. Selecting a folder fills the Source box. List auto-refreshes every 30s.
- **Absence-driven auto-restore** — the sync cycle restores a folder only when its source is missing/empty (post-format). No more 'on login' trigger. The health lamp shows 'RESTORED N folder(s)' when a restore happens.
- **Exclude feature** — Tools → Manage Exclusions: skip app-locked subfolders (e.g. Hermes's pending_messages) via robocopy /XD.
- **Robocopy failure reasons in the log** — failures now show the human reason (e.g. 'Access is denied.') instead of just 'SYNC FAIL'.
- **Toggle Auto-Restore fix** — used Add-Member for pairs missing the AutoRestore field (direct assignment failed silently → always ON).
- **Harden AutoRestore parsing** — [bool]'false' is $true in PowerShell; replaced all casts with ConvertTo-Bool helper.
- **Custom LRGEX icon** in the right-click context menu (auto-downloads on other PCs).
- **Console-flash fix** — VBS launcher eliminates the 1-second window flash during background sync.
- **Title clipping fix** — hero 24pt title label height 34→48 + MiddleLeft alignment.
- **Version at bottom-center** of the window.
- **Rebrand** — 'Junction Sync Tool' → 'Folder Sync' everywhere.

## v0.6.1
- **Synced-folders list** in the main UI with per-folder Auto-Restore toggle + Remove.
- **Absence-driven auto-restore** — the sync cycle restores a folder only when its source is missing/empty. Removed the 'on login' trigger entirely.
- **Toggle Auto-Restore fix** — pairs missing the AutoRestore field couldn't be toggled (direct assignment failed silently). Fixed via Add-Member.
- **Harden AutoRestore parsing** — `[bool]"false"` is `$true` in PowerShell; added `ConvertTo-Bool` helper.
- **Robocopy failure reasons in the log** — shows the human cause (e.g. 'Access is denied.') instead of just 'SYNC FAIL'.
- **VBS launcher** — truly invisible background sync via `wscript.exe` (no console). Was `PowerShell.exe -WindowStyle Hidden` which flashed a window for ~1 second.
- **GUI hang fix** — removed TopMost from the main form (MessageBoxes were hidden behind it → frozen UI).
- **Hero title** (24pt bold) + version label at bottom-center.
- **Custom LRGEX icon** in the right-click context menu (auto-downloads on other PCs).

## v0.6.0
- **Exclude feature**: Tools → Manage Exclusions — list subfolder NAMES to skip during sync (e.g. `pending_messages`). robocopy runs with `/XD` for those names, so app-locked runtime folders no longer cause false failures. Resolves the `hermes\pending_messages` access-denied case (Hermes locks that folder; it's empty, so excluding it loses nothing and the lamp goes green).

## v0.5.9
- **Cleaner sync log**: each cycle now has a header and tidy `[ OK ] / [FAIL] <folder> - <reason>` lines (previously verbose). Failures show the human reason (e.g. `Access is denied.`), de-duplicated across robocopy retries.
- **Rebrand**: "Junction Sync Tool" → **"Folder Sync"** everywhere (window title, header, user-agent).
- **Version label** moved next to the header title (small, one line beneath it) — single source `$script:AppVersion`.
- **Documented the `hermes` failure**: `AppData\Local\hermes\pending_messages` is **locked by the Hermes app itself** — even a plain `Copy-Item` is denied ("Access to the path is denied"). It contains 0 files, so **no data is at risk**. This is not a sync bug; robocopy simply cannot copy a folder the owning app has locked. The sync logs it and continues with everything else. Resolution options: exclude that subfolder, or unlink `hermes` if its runtime data isn't needed.

## v0.5.8
- **Accurate health lamp**: now reads the real sync outcome (`sync-status.json`), so green = genuinely all-OK and red = a real failure — it no longer trusts the task's exit code alone.
- **Solid-colored lamp**: green / amber (while syncing) / red background bar — easy to see.
- **UI sync log**: Tools → **View Sync Log**; stored locally (`%LOCALAPPDATA%\LRGEX\folder-sync.log`), capped at 2000 lines (no cloud churn).
- **Per-link auto-restore**: linking a folder asks whether to auto-restore *that specific folder* after a format; only the folders you opt in are auto-restored.
- **Configurable sync interval**: Tools → **Set Sync Interval…** (e.g. `120` = every 2 hours). Saved to config; survives a format.
- **Smart auto-restore**: a folder is restored only when its original path is missing/empty (true post-format signal) — a complete no-op on normal logins.
- **Renamed script** `onedrivesync.ps1` → **`folder-sync.ps1`** (code, `.gitignore`, README, home copy, scheduled task, and right-click registry all migrated to the new name).
- **Fixed the silent sync-breaker**: the old task action was stored corrupted (`-File $` → error 267 "directory invalid") AND the at-logon trigger never fired mid-session (LastRunTime stayed 1999) — so new files silently stopped syncing. Replaced with a clean action + two triggers (AtLogon + Once-repeat) + immediate start. Dropped `-RunLevel Highest` (sync only touches your own files → no admin needed).
- **State-aware right-click menu toggle** (shows ON/OFF and flips its action).
- **robocopy `/R:5 /W:5`** (was `/R:1 /W:1`) so briefly-locked files are caught within the same cycle.
- **Removed the vestigial `TargetRelativePath`** field from saved pairs (was always `null`).

## v0.5.0 — Cloud-Agnostic Mirror Engine
- **Fully cloud-agnostic**: pick ANY folder as the sync home — OneDrive, Google Drive, Mega, Dropbox, iCloud, or even a plain local folder. Cloud is *recommended* (survives a format), never *required*.
- **Marker-based home** (`.lrgex-home`); all paths resolve relative to the script's own folder. Nothing hardcoded to OneDrive / Documents / a fixed folder name.
- **Copy-only everywhere** (no `/MIR`, no `/PURGE`) — nothing is ever deleted on either side; deleting a file locally keeps it in the backup (archive behavior).
- First run asks where to set up; picking a non-cloud folder shows a warning but proceeds.
