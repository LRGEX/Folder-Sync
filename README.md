<div align="center">
  <img src="https://download.lrgex.com/Dark%20Full%20Logo.png" alt="LRGEX Logo" width="300">

  # LRGEX Folder Sync

  **Version 0.7.0**

</div>

---

## Description

LRGEX Folder Sync is a PowerShell Windows Forms app that mirrors arbitrary local folders (game saves, app data, dev projects) into a folder you choose, so they survive a PC format, then restores them to their exact original paths automatically.

It is fully cloud-agnostic: pick OneDrive, Google Drive, Mega, Dropbox, iCloud, or a local folder. Cloud is recommended (survives a format), never required. It syncs continuously, is copy-only (never deletes), and adds a right-click menu so linking a folder takes one click.

The tool does NOT use NTFS junctions or mklink. It copies real files into your chosen folder with robocopy, which any cloud service syncs reliably.

---

## Features

- **Cloud-agnostic** — OneDrive, Google Drive, Mega, Dropbox, iCloud, or local. You pick the folder.
- **Copy-only / never deletes** — no /MIR, no /PURGE. Nothing is ever removed from either side.
- **Right-click to sync** — right-click any folder in File Explorer, select "Sync folder (LRGEX)", done. No admin prompt.
- **Continuous background sync** — a scheduled task mirrors new/changed files automatically (default every 2 hours, configurable).
- **Absence-driven auto-restore** — the sync cycle restores a folder only when its source is missing or empty (the post-format signal). No login trigger.
- **Health lamp** — green (sync OK) / amber (syncing now) / red (problem with reason). Live, refreshes every 30 seconds.
- **Sync log** — Tools menu, View Sync Log: readable history of every cycle, including failure reasons.
- **Synced-folders list** — every linked folder shown in the main UI with per-folder Auto-Restore status (ON/OFF). Toggle or remove per folder.
- **Exclude subfolders** — Tools menu, Manage Exclusions: skip app-locked runtime subfolders (e.g. pending_messages) via robocopy /XD.
- **Invisible background sync** — runs via a VBS launcher (wscript.exe). No console window flash.
- **Self-healing task** — if the sync task is stale or missing, it is recreated automatically when the app opens.
- **Custom LRGEX icon** in the right-click context menu (auto-downloads on other PCs).
- **One file** — folder-sync.ps1 is the entire app. No installer, no dependencies beyond Windows 10/11.

---

## Installation

1. Download `folder-sync.ps1` (this single file is the whole app).
2. Run it:
   ```
   PowerShell.exe -ExecutionPolicy Bypass -File ".\folder-sync.ps1"
   ```
   If Windows shows a SmartScreen warning, click "Run anyway" (the script is unsigned).
3. On first run, it asks once: "Pick the folder where LRGEX sync will live." Choose your cloud folder (e.g. your OneDrive, MEGA, or Google Drive folder). The script copies itself there and creates a config. This becomes your sync home.
4. Open the app from the sync home, then go to Tools, Right-Click Sync, click it to enable. This adds "Sync folder (LRGEX)" to your File Explorer right-click menu.

---

## Usage

### Link a folder (backup it)
Right-click any folder in File Explorer, select "Sync folder (LRGEX)".
- The folder is copied into your sync home immediately.
- You are asked: "Enable auto-restore for this folder after a format?" (Yes/No).
- The folder appears in the app's synced-folders list within 30 seconds.
- New and changed files sync automatically every 2 hours (or whatever interval you set).

Alternatively, use the app's GUI: type or browse for a folder in the Source box, then click "Link Folder".

### What happens when you delete files
- Delete some files (1+ left in the folder): they stay deleted in the source. The backup keeps them (archive behavior). They do NOT come back.
- Delete ALL files (folder empty): if Auto-Restore is ON for that folder, the next sync cycle restores everything from the backup automatically.
- Want permanent deletion: toggle Auto-Restore OFF, delete from the source, then manually delete from the backup folder in your sync home.

### Restore after a format
1. Reinstall your cloud service (OneDrive/MEGA/etc.) and let it download your sync home folder.
2. Open folder-sync.ps1 from the sync home.
3. Click "Restore Saved", select the folders, click "Restore".
4. Every folder is copied back to its exact original path.

If Auto-Restore is ON for a folder: the background sync detects the folder is missing and restores it automatically (no manual action needed).

### Change the sync interval
Tools, Set Sync Interval, enter minutes (e.g. 120 = every 2 hours, 5 = every 5 minutes). Default is 120.

### Exclude app-locked subfolders
Tools, Manage Exclusions, type subfolder names to skip (one per line). Useful for runtime folders that apps lock (e.g. Hermes's pending_messages).

### Give it to a friend
Send them folder-sync.ps1. They run it, pick their cloud folder, enable right-click, and start linking folders. The icon and logo auto-download. No manual setup beyond picking a folder.

---

## The Main Window

| Element | Purpose |
|---|---|
| Folder Sync (title) | App name + version number. |
| Health lamp | Green = sync OK, amber = syncing now, red = problem (with reason). |
| Synced folders list | Every linked folder with its Auto-Restore status (ON/OFF). |
| Toggle Auto-Restore | Flips the selected folder's auto-restore ON/OFF. |
| Remove | Removes the selected folder from the sync list (backup NOT deleted). |
| Source folder box | Type or Browse to pick a folder, then click Link Folder. |
| Link Folder | Links the folder + mirrors it immediately + asks auto-restore. |
| Restore Saved | Opens the restore dialog (select folders to restore). |

### Tools menu
| Item | Purpose |
|---|---|
| View Sync Log | Readable history of every sync cycle + failure reasons. |
| Set Sync Interval | Change how often the background sync runs (default 120 min). |
| Manage Exclusions | List subfolder names to skip during sync. |
| Right-Click Sync | Enable/Disable the File Explorer context menu entry (registry only, does NOT affect the sync task). |
| Export Configuration | Save your folder list to a JSON file. |
| Import Configuration | Load a previously exported folder list. |
| Remove | Remove linked folders (backup copies NOT deleted). |

---

## Requirements

- Windows 10/11 (NTFS)
- A cloud service is recommended (OneDrive, Google Drive, Mega, Dropbox, or iCloud) so backups survive a format. Not required: a local folder works but will not survive a format.
- PowerShell 5.1+ (built into Windows 10/11)
- Admin is requested automatically only for the GUI. Right-click and background sync run without admin prompts.

---

## Important: Unique Folder Names

The backup copy is named after the folder's own name (the last part of its path), not its full path. Each linked folder must have a unique name:

- C:\Users\you\Saved Games\Cyberpunk is backed up as Cyberpunk
- C:\Users\you\Saved Games\Witcher3 is backed up as Witcher3
- Two folders both named "data" on different paths would clash

Game saves, app data, and repos almost always have distinct names.

---

## Configuration

Stored in `junction-config.json`, next to the script (in your sync home):

```json
{
  "Junctions": [
    {
      "SourcePath": "C:\\Users\\you\\Saved Games\\Cyberpunk",
      "AutoRestore": true,
      "Created": "2025-07-30 12:00:00"
    }
  ],
  "SyncIntervalMinutes": 120,
  "ExcludedNames": ["pending_messages"]
}
```

| Field | Meaning |
|---|---|
| SourcePath | The original full path. Restore puts files back exactly here. |
| AutoRestore | Per-folder opt-in for absence-driven auto-restore (true/false). |
| SyncIntervalMinutes | Background sync interval in minutes (default 120). |
| ExcludedNames | Subfolder names to skip during sync. |

---

## Safety

- **Copy-only everywhere** — no /MIR, no /PURGE. Nothing is ever deleted.
- **Archive behavior** — deleting a file locally keeps it in the backup (survives accidental deletes).
- **Right-click is UAC-free** — no admin prompt on each use.
- **Restore is exact** — every folder goes back to its recorded original path.
- **Background sync is invisible** — no window flash, no console popup.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

---

## Contributing

This is an LRGEX project. For issues, suggestions, or contributions, contact LRGEX.

See [patchnotes.md](patchnotes.md) for the full changelog.
