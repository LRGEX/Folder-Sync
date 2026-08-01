<div align="center">

<img src="assets/logo.png" alt="LRGEX Logo" width="220">

# Folder Sync

**Automatic folder backup, versioning, and restore after a Windows reinstall.**

**Portable • Open Source • MIT Licensed**

</div>

<table align="center">
<tr>
<td align="center">
<img src="https://github.com/user-attachments/assets/2f9b086f-dc8e-4b40-b8a7-ac8943853196" width="300">
</td>
<td width="20"></td>
<td align="center">
<img src="https://github.com/user-attachments/assets/67b2ae26-f8ca-48c2-849a-9018274201db" width="300">
</td>
</tr>
</table>

---

## Ever formatted your PC?

You know the feeling.

Windows is fresh. Your apps are reinstalled. Then you launch your favorite game...

**Your saves are gone.**

Your application settings? **Gone.**

Hours of progress and years of customization disappear because Windows doesn't protect those folders.

**Folder Sync remembers them, keeps them synchronized, and restores them to their exact original locations after you reinstall Windows.**

---

## How it works

1. **Choose a folder** — game saves, app settings, projects, or anything important.
2. **Folder Sync watches it** — changes are compressed and synchronized automatically.
3. **Reinstall Windows** — without worrying about lost files.
4. **Restore with one click** — every folder returns to its original location automatically.

**Set it once. Forget about it. Your files are always there when you need them.**

---

## Why Folder Sync?

- **One-click protection** — right-click any folder and choose **"Sync folder (LRGEX)"**.
- **Works with any cloud** — OneDrive, Google Drive, Dropbox, Mega, iCloud, NAS, Syncthing, or even a local drive.
- **Automatic synchronization** — changes are backed up in the background.
- **Built-in version history** — restore previous snapshots whenever you need them.
- **Automatic restore** — after reinstalling Windows, missing folders are restored to their original paths.
- **Portable** — a single 14 MB executable. No installer. No dependencies.

---

## Features

- **Mirror sync** — new and changed files sync to your cloud automatically
- **Snapshot versioning** — every change creates a snapshot. Roll back any folder to any point in the last 90 days
- **Auto-restore** — after a format, missing folders are restored automatically
- **Right-click integration** — right-click any folder in Explorer to sync it
- **Configurable sync interval** — 1 minute or more, your choice
- **Exclusions** — skip app-locked subfolders that cause false errors
- **Export/Import** — move your folder list to a new PC
- **Health lamp** — live status: green (safe), amber (syncing), red (problem)
- **Auto-update** — the app checks for new versions and updates itself

### What happens when you delete files?

- **Delete one file**: it leaves the backup. The old version lives in versioning for 90 days. Does NOT come back on restore.
- **Delete the entire folder**: if auto-restore is ON, the next sync brings it all back.

---

## Installation

1. Download `LRGEXSync.exe`
2. Run it — pick a **home folder** inside your cloud service (OneDrive, Google Drive, etc.) so your files survive a format. Local folder works too, but won't survive a format.
3. Open the app from the home folder
4. Go to **Tools → Right-Click Sync** to enable the right-click menu
5. Right-click any folder you want to protect — select **"Sync folder (LRGEX)"**

Your folders are now backed up continuously.

---

## Restore after a format

1. Reinstall your cloud service and let it download
2. Open `LRGEXSync.exe` from your home folder
3. Click **"Restore Saved"** — or let auto-restore handle it automatically

Every folder goes back to its exact original path.

---

## Requirements

- Windows 10/11
- A cloud service recommended (survives a format). Local folder works but won't survive a format.

---

## License

MIT License. See [LICENSE](LICENSE).
