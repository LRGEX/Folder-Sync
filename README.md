<div align="center">
  <img src="logo.png" alt="LRGEX Logo" width="240">

  # Folder Sync

  **Version 1.0.7**

  **Your files survive a PC format. Automatically.**

</div>

---

## Ever formatted your PC?

You know the feeling. Windows is fresh. Apps are reinstalled. Then you open your game — **saves gone**. Your configs — **gone**. Hours of progress, years of settings, all wiped because Windows doesn't protect those folders.

You tell yourself "I'll back them up next time." You forget. You format again. Same thing.

**Folder Sync ends this cycle.**

---

## How it works

1. **Pick a folder** — game saves, app data, any folder you care about
2. **It syncs automatically** — every change is mirrored to your cloud storage
3. **Format your PC** — reinstall Windows without fear
4. **Folder Sync restores everything** — back to the exact original path, automatically

You set it once. You forget it exists. When you need it, your files are there.

---

## Why Folder Sync?

- **Right-click any folder** in File Explorer — select "Sync folder (LRGEX)" — done. One click.
- **Works with any cloud** — OneDrive, Google Drive, Mega, Dropbox, iCloud. Your choice.
- **Versioning built in** — every change is saved as a snapshot. Delete a file by mistake? Roll back the entire folder to any point in the last 90 days. Zero disk waste (NTFS hardlinks).
- **Auto-restore after format** — folders that go missing are automatically restored from backup on the next sync cycle.
- **Health monitoring** — green lamp means your files are safe. Red means something needs attention.
- **Dark themed, native, fast** — single 14MB exe. No installer. No dependencies. No bloat.

---

## Installation

1. Download `folder_sync.exe`
2. Run it — the app asks you to pick a **home folder**. This is where the app installs itself and stores backups. **Pick a folder inside your cloud service** (OneDrive, Google Drive, etc.) so your files survive a PC format. A local folder works too, but it won't survive a format — that's your choice.
3. Open the app from the home folder.
4. Go to **Tools → Right-Click Sync** to enable the File Explorer right-click menu.
5. Right-click any folder you want to protect — select **"Sync folder (LRGEX)"**.

Alternatively, use the app GUI: browse for a folder, click **"Backup Folder"**.

Your folders are now backed up continuously.

---

## Features

| Feature | What it does |
|---|---|
| **Mirror sync** | New and changed files sync to your cloud automatically |
| **Snapshot versioning** | Every change creates a space-efficient snapshot — roll back to any point in time |
| **Auto-restore** | After a format, missing folders are restored automatically |
| **Right-click integration** | Right-click any folder in Explorer to sync it |
| **Configurable interval** | Sync every 5 minutes or every 12 hours — your choice |
| **Exclusions** | Skip app-locked subfolders that cause false errors |
| **Export/Import config** | Move your folder list to a new PC |
| **Health lamp** | Live status: green (safe), amber (syncing), red (problem) |

### Versioning

Every time a file changes or is deleted, a snapshot is captured BEFORE syncing. Click "Versions" on any folder to see a list of timestamps — pick one, click Restore, the entire folder rolls back to that moment.

Snapshots use NTFS hardlinks — unchanged files share disk blocks, so each snapshot costs near-zero space. Only genuinely changed files take storage. Old snapshots auto-delete after 90 days.

### What happens when you delete files?

- **Delete one file**: it leaves the backup (mirror sync). The old version lives in versioning for 90 days. Does NOT come back on restore.
- **Delete the entire folder**: if auto-restore is ON, the next sync cycle brings it all back from backup.

---

## Restore after a format

1. Reinstall your cloud service (OneDrive, Google Drive, etc.)
2. Let it download your sync folder
3. Open `folder_sync.exe` from that folder
4. Click "Restore Saved" — or let auto-restore handle it automatically

Every folder goes back to its exact original path.

---

## Requirements

- Windows 10/11
- **NTFS recommended** for best experience — snapshot versioning uses NTFS hardlinks (near-zero disk usage per snapshot). On non-NTFS drives (FAT32, exFAT, network), versioning still works but uses full copies instead of hardlinks (more disk space).
- A cloud service recommended (survives a format). Local folder works but won't survive a format.

---

## License

MIT License. See [LICENSE](LICENSE).

---

## Contributing

This is an LRGEX project. For issues or contributions, contact LRGEX.

See [patchnotes.md](patchnotes.md) for the full changelog.
