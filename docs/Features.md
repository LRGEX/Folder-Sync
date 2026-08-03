# Features

## Backup
- **Any folder** — right-click any folder in Explorer → "Sync folder (LRGEX)"
- **Compressed archives** — tar + zstd compression (level 1, fast)
- **Snapshot versioning** — every change creates a snapshot, rollback to any point
- **Cloud-agnostic** — works with OneDrive, Google Drive, Mega, Dropbox (any synced folder)
- **Locked files skip** — locked/in-use files are skipped and reported (never aborts)

## Restore
- **Auto-restore after format** — detects empty folders and restores automatically
- **Path healing** — paths auto-adapt to new username after format
- **Portable config** — uses environment variables (%USERPROFILE%, %LOCALAPPDATA%) and Windows Known Folder API
- **Atomic extraction** — decompresses to temp dir, swaps on success, never half-writes
- **Pre-check** — validates all folders before touching any, skips failures
- **Live progress** — byte-level percentage during decompression

## Synchronization
- **Scheduled sync** — runs automatically on interval (configurable)
- **Change detection** — only re-compresses when file count or size changes
- **Honest messages** — "Backed up 138,000 files (863 MB). 2 skipped (locked)."

## UI
- **Dark mode** — clean dark interface
- **Game detection** — auto-detects game save folders with lamp indicators
- **Health check** — Tools → Backup Health Check shows size, age, stale status
- **Close guard** — warns if you close during compression/restore
- **VM support** — software renderer, works on Hyper-V/VirtualBox/RDP
