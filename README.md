
<div align="center">
<img src="https://download.lrgex.com/Dark%20Full%20Logo.png" alt="LRGEX Logo" width="300">

# LRGEX Folder Sync
*Back up any folder to **any** location you choose — OneDrive, Google Drive, Mega, Dropbox, iCloud, or even a local folder — and restore it to its exact original path after a PC format.*
</div>

## Overview

**LRGEX Folder Sync** is a PowerShell Windows Forms app that **mirrors** any local folder into **a folder you pick** so it survives a PC format — then **restores** it to its exact original path automatically. Built for things like **game saves, app data (`%AppData%`), and Visual Studio repos** that live in fixed locations you can't change.

It is **fully cloud-agnostic**: you choose where backups live. A cloud folder is **recommended** (so backups sync across machines and survive a format), but the tool also works with a plain local folder if that's what you want. It syncs **continuously**, is **copy-only (never deletes)**, and adds a **right-click** menu so linking a folder takes one click.

> **Heads-up — this is the mirror-engine version.** Earlier versions used NTFS *junctions* (`mklink`), but cloud services do **not** reliably sync junctions, so backups could silently fail. This version copies **real files** into your chosen folder with `robocopy`, which any cloud service syncs reliably.

## Key Features

- **Pick any destination** — OneDrive, Google Drive, Mega, Dropbox, iCloud, or a local folder. Cloud is recommended, never required.
- **Right-click to sync** — right-click any folder → *“Sync to OneDrive (LRGEX)”* → done. No admin prompt.
- **Continuous sync** — a background task mirrors new/changed files every few minutes automatically.
- **Copy-only / never deletes** — your data is never removed from either side.
- **One-click restore** — after a format, *Restore Saved* puts every folder back at its **original path**.
- **Works anywhere** — run the script from any PC / any path / any partition; it asks you once where to set up.
- **Dark-themed Windows Forms GUI** with LRGEX branding.
- **Self-backing-up** — the script and its config live inside the folder you chose, so if that folder is in a cloud, they survive a format too.

## How It Works

1. **First run** — open the script. It asks **once**: *"Pick the folder where LRGEX sync will live."* Choose a folder (your cloud folder is suggested). If you pick a non-cloud folder, it warns you (won't survive a format) but lets you continue.
2. **Enable right-click once** — *Tools → Right-Click Sync → Enable*. (This also turns on the automatic background sync.)
3. **Link any folder** — right-click it → *“Sync to OneDrive (LRGEX)”*. Real files are copied into your home folder; a confirmation appears.
4. **Keep playing / working** — new files you create are mirrored automatically (~every 5 min).
5. **After a format** — open the app → *Restore Saved* → every folder returns to its original path.

## ⚠️ Important: each folder must have a unique name

The backup copy is named after the **folder's own name** (the last part of its path), not its full path. So:

- ✅ **Works fine** — folders with **different** names:
  - `C:\Users\you\Saved Games\Cyberpunk` → backed up as `Cyberpunk`
  - `C:\Users\you\Saved Games\Witcher3` → backed up as `Witcher3`
  - `C:\Users\you\AppData\Steam` → backed up as `Steam`
- ⚠️ **Avoid** — two folders with the **same name** on different paths (e.g. `C:\App1\data` and `C:\App2\data`) would both back up to `data` and clash.

Game saves, app data, and repos almost always have distinct names, so in practice this is never an issue — just don't link two folders that happen to share a name.

## Use Cases

- **Game saves** — back up saves stored in `%AppData%`, `Saved Games`, etc., and restore them after reinstalling the game.
- **Application data** — sync app settings/profile folders that live in fixed system paths.
- **Development projects** — keep `source\repos` and similar backed up automatically.
- **Creative assets / config** — mirror any important folder without moving it.

## Installation & Usage

1. **Get the script** — `onedrivesync.ps1` (this single file is the whole app).
2. **Run it** — double-click / launch. On first run it asks you to pick the home folder (your cloud folder is suggested).
3. **One-time setup** — *Tools → Right-Click Sync → Enable “Sync to OneDrive” on right-click*. (This also turns on the automatic background sync.)
4. **Link folders** — right-click any folder → *“Sync to OneDrive (LRGEX)”*.
5. **After a format** — open the app → *Restore Saved*.

> First launch may show a Windows SmartScreen / execution-policy warning (the script is unsigned). Click **Run anyway**, or run:
> `PowerShell.exe -ExecutionPolicy Bypass -File ".\onedrivesync.ps1"`

## Technical Features

### Mirror Engine
- `robocopy` copies real files into your chosen home folder (`/E /XJ`, **no `/MIR`/`/PURGE`** — copy-only).
- Continuous background sync via Windows Task Scheduler (default every 5 min; locked files skipped, never fatal).
- Restore = copy back from the home folder to the **original path** (home copy stays intact). The original path is remembered in the config, so restore always puts files back exactly where they were.

### Right-Click Integration
- File Explorer context-menu entry *“Sync to OneDrive (LRGEX)”*.
- Registry command passes only the folder (`%V`); the destination is the script's own folder (home) — no hardcoded paths, so it works for any user.

### Cloud-Agnostic Destination
- You pick the home folder once (a cloud folder is recommended, not required).
- Everything — script, config, and mirrored folders — lives in that one folder.
- The script recognizes its home via a hidden `.lrgex-home` marker, so the folder can have **any name**.

### Professional GUI
- Custom dark theme (RGB 45,45,45), web logo/icon with 24h cache, custom menu renderer, real-time status.
- A read-only line shows where your backups are stored (your home folder).

## Configuration

Stored in `junction-config.json`, **next to the script** (inside the home folder you picked):
```json
{
  "Junctions": [
    { "SourcePath": "C:\\Users\\you\\Saved Games\\Cyberpunk", "TargetRelativePath": null, "Created": "..." }
  ],
  "AutoRestoreEnabled": false
}
```
> - **`SourcePath`** is the original full path — restore uses it to put the folder back exactly where it was.
> - The backup copy is named after the folder's leaf (e.g. `Cyberpunk`), so each linked folder needs a **unique name**.
> - The `"Junctions"` key and `TargetRelativePath` field are kept for backward compatibility; entries are folder pairs, not junction links, and `TargetRelativePath` is ignored.

## Advanced Tools (Tools menu)

- **Right-Click Sync** — Enable / Disable the File Explorer right-click entry.
- **Remove** — remove a linked folder (uses safe clear; real data preserved).
- **Export / Import Configuration** — back up / restore the folder list.
- **Auto-Restore** — enable post-format auto-restore on login.
- **Health Check** — *(legacy; retained from the junction era)*.

## System Requirements

- Windows 10/11, NTFS
- **A cloud service is recommended** (OneDrive, Google Drive, Mega, Dropbox, or iCloud) so backups survive a format — but **not required** (a local folder works too, it just won't survive a format).
- PowerShell 5.1+
- Admin (requested automatically **only for the GUI**; right-click/background sync run without prompts)

## Safety

- **Non-destructive** — copy-only; nothing is ever deleted from source or home.
- **Archive behavior** — deleting a file locally keeps it in the home backup, so backups survive accidental deletes.
- **Right-click is UAC-free** — no admin prompt on each use.
- **Restore is exact** — every folder goes back to its recorded original path.

---

**Version:** 5.0 (Cloud-Agnostic Mirror Engine)
**Developer:** LRGEX
**License:** Proprietary
