
<div align="center">
<img src="https://download.lrgex.com/Dark%20Full%20Logo.png" alt="LRGEX Logo" width="300">

# LRGEX Folder Sync
*Back up any folder to **any** cloud — OneDrive, Google Drive, Mega, Dropbox, iCloud — and restore it to its exact original path after a PC format.*
</div>

---

## What It Does

**LRGEX Folder Sync** backs up your important folders (game saves, app data, dev projects — anything in a fixed location) into a folder YOU choose, then **restores them to their exact original paths** after a PC format.

- **Cloud-agnostic** — pick OneDrive, Google Drive, Mega, Dropbox, iCloud, or even a local folder. Cloud is *recommended* (survives a format), never *required*.
- **Copy-only** — your data is **never deleted** from either side.
- **Continuous** — a background task mirrors new/changed files automatically (default every **2 hours**; configurable).
- **Right-click** — link any folder from File Explorer in one click. No admin prompt.
- **One-click restore** — after a format, every folder goes back to exactly where it was.

---

## Quick Start (3 Steps)

### Step 1 — Get & Run the Script
Download `folder-sync.ps1` (it's the **entire app** — one file, no installer).

```powershell
# If Windows blocks it (SmartScreen / execution policy):
PowerShell.exe -ExecutionPolicy Bypass -File ".\folder-sync.ps1"
```

On first run, it asks **once**: *"Pick the folder where LRGEX sync will live."*
- **Pick your cloud folder** (e.g. your OneDrive, MEGA, Google Drive folder).
- The script copies itself there + creates a config. This becomes your **sync home**.
- Everything (script, config, backups) lives in this one folder.

### Step 2 — Enable Right-Click
Open the app → **Tools → Right-Click Sync → click it** (it shows ON/OFF).
- This adds *"Sync folder (LRGEX)"* to your File Explorer right-click menu.
- This is ONLY the context menu entry — it does **not** control the background sync (they're independent).

### Step 3 — Link Folders
**Right-click any folder** → *"Sync folder (LRGEX)"*.
- The folder is **copied into your sync home** (immediately).
- A confirmation appears. You're asked: *"Enable auto-restore for this folder after a format?"* (Yes/No).
- The folder appears in the app's **synced-folders list** (within 30 seconds).
- New/changed files sync automatically every **2 hours** (or whatever interval you set).

**Done.** Keep working. Your files back up automatically.

---

## After a PC Format — Restore

1. Reinstall your cloud service (OneDrive/MEGA/etc.) → let it download your sync home folder.
2. Open `folder-sync.ps1` from the sync home.
3. Click **Restore Saved** → select the folders → **Restore**.
4. Every folder is copied back to its **exact original path**.

**OR** — if auto-restore is ON for a folder: the background sync detects the folder is missing and **restores it automatically** (no manual action needed).

---

## The Main Window

| Element | What it shows |
|---|---|
| **Folder Sync** (title) | App name (hero font) + version number below it. |
| **Health lamp** | 🟢 green = sync OK / 🟡 amber = syncing now / 🔴 red = problem (with the reason). Refreshes every 30 seconds. |
| **Synced folders list** | Every folder you've linked, with its **Auto-Restore** status (ON/OFF). Select one to see its path in the Source box. |
| **Toggle Auto-Restore** | Flips the selected folder's auto-restore ON/OFF. |
| **Remove** | Removes the selected folder from the sync list (backup copy is NOT deleted). |
| **Source folder** box | Type or Browse to pick a folder to link, then click **Link Folder**. |
| **Link Folder** button | Links the folder in the Source box + mirrors it immediately + asks auto-restore. |
| **Restore Saved** button | Opens the restore dialog (select folders to restore). |

---

## Tools Menu (Everything Explained)

| Menu Item | What it does |
|---|---|
| **View Sync Log** | Shows a readable log of every sync cycle: which folders synced OK/FAIL + the reason if something failed. |
| **Set Sync Interval…** | Change how often the background sync runs. Default = **120 min** (2 hours). Enter any number of minutes (e.g. `5` for every 5 min, `60` for hourly). |
| **Manage Exclusions…** | List subfolder names to SKIP during sync (e.g. `pending_messages` for app-locked runtime folders). One per line. robocopy skips them via `/XD`. |
| **Right-Click Sync** | Enable/Disable the *"Sync folder (LRGEX)"* File Explorer context menu entry. **This is ONLY the registry entry — it does NOT start/stop the background sync task.** |
| **Export Configuration** | Save your folder list to a JSON file (backup). |
| **Import Configuration** | Load a previously exported folder list. |
| **Remove** | Remove linked folders (backup copies are NOT deleted). |
| **Health Check** | *(Legacy from the junction era — still functional but mostly informational.)* |

---

## How Sync Works (Explained)

### Backup direction (source → home)
Every sync cycle, the app runs `robocopy` to **copy** new/changed files from each linked folder INTO your sync home. It uses:
- `/E` — copy all subdirectories (including empty ones).
- `/XJ` — skip junctions/symlinks (don't follow them).
- `/R:5 /W:5` — retry locked files 5 times (5 seconds apart).
- **NO `/MIR`, NO `/PURGE`** — **nothing is ever deleted** from either side.

### What happens when you delete a file?
| What you delete | Source | Home backup | Comes back? |
|---|---|---|---|
| **Some files** (1+ left) | stays deleted ✅ | keeps them (archive) | **NO** |
| **All files** (folder empty) | auto-restored from backup | keeps them | **YES** (if Auto-Restore is ON) |
| **Want permanent delete** | toggle Auto-Restore OFF → delete → manually delete from home backup | cleaned | gone for good |

### Auto-restore (absence-driven)
Auto-restore is **NOT** on a timer or login trigger. It happens **inside the sync cycle**: for each folder with Auto-Restore ON, if the source folder is **missing or empty** (the post-format signal), it's restored from the backup automatically. On normal logins (folders present), **nothing happens** — a complete no-op.

### Background sync task
- Runs via a **VBS launcher** (`wscript.exe`) — **truly invisible** (no console window flash).
- **Self-healing**: every time you open the app, it checks the task exists + points to a valid path. If stale (old home deleted) → recreates it.
- **Independent from right-click**: enabling/disabling the right-click menu does NOT affect the sync task.
- Default interval: **120 minutes**. Change via Tools → Set Sync Interval.

---

## ⚠️ Important: Unique Folder Names

The backup copy is named after the **folder's own name** (the last part of its path), not its full path:

- ✅ `C:\Users\you\Saved Games\Cyberpunk` → backed up as `Cyberpunk`
- ✅ `C:\Users\you\Saved Games\Witcher3` → backed up as `Witcher3`
- ⚠️ Two folders named `data` on different paths would clash. Use unique names.

---

## Use Cases

- **Game saves** — back up saves in `%AppData%`, `Saved Games`, etc. Restore after reinstalling.
- **App data** — sync settings/profile folders at fixed system paths.
- **Dev projects** — keep `source\repos` backed up automatically.
- **Any folder** — mirror anything important without moving it.

---

## Configuration

Stored in `junction-config.json`, **next to the script** (in your sync home):
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
| `SourcePath` | The **original full path** — restore puts files back exactly here. |
| `AutoRestore` | Per-folder opt-in for absence-driven auto-restore (ON/OFF). |
| `SyncIntervalMinutes` | Background sync interval (default 120). |
| `ExcludedNames` | Subfolder names to skip during sync (app-locked folders). |

---

## System Requirements

- **Windows 10/11** (NTFS)
- **A cloud service recommended** (OneDrive, Google Drive, Mega, Dropbox, iCloud) — but **not required** (local folder works, just won't survive a format)
- **PowerShell 5.1+** (built into Windows 10/11)
- **Admin** — requested automatically **only for the GUI**. Right-click and background sync run **without** admin prompts.

---

## Safety Guarantees

- **Copy-only everywhere** — no `/MIR`, no `/PURGE`. Nothing is ever deleted.
- **Archive behavior** — deleting a file locally keeps it in the backup (survives accidental deletes).
- **Right-click is UAC-free** — no admin prompt on each use.
- **Restore is exact** — every folder goes back to its recorded original path.
- **Background sync is invisible** — no window flash, no console popup.

---

## Giving It to a Friend

Just send them **`folder-sync.ps1`** — that's the entire app. They:
1. Run it → pick their cloud folder → done.
2. Enable right-click (Tools menu) → right-click any folder → synced.
3. The icon + logo auto-download from the web. No manual setup.

---

**Version:** 0.7.0
**Developer:** LRGEX
**License:** MIT (see [LICENSE](LICENSE))
