# How It Works

## Backup Flow
1. User right-clicks a folder → "Sync folder (LRGEX)"
2. App walks the folder, counts files, measures size
3. Compresses to tar.zst in %TEMP% (outside cloud folder for speed)
4. Moves compressed archive to `backup/<folder>/<folder>.tar.zst`
5. If size/count changed since last backup → old version snapshotted to `_versions/`

## Restore Flow
1. User clicks Restore (single folder or all)
2. **Pre-check** — validates each folder:
   - Archive exists and is valid zstd
   - Destination is writable
3. Failed folders are **skipped** (with reason shown)
4. For each passing folder:
   - Decompresses to temp dir (atomic — never touches live data)
   - Rename-swap: old → .lrgex_bak, temp → destination, delete .lrgex_bak
   - On failure: discard temp, destination untouched
5. Result summary shows restored/skipped/failed

## Portable Paths
Config stores paths using environment variables:
- `%USERPROFILE%\Saved Games` instead of `C:\Users\Bob\Saved Games`
- `%LOCALAPPDATA%\hermes` instead of `C:\Users\Bob\AppData\Local\hermes`
- `%KNOWNFOLDER:SavedGames%` for Windows Known Folders (handles relocation)

On load: expand to absolute. On save: contract to portable. On new machine: auto-heal.

## File Structure
```
LRGEX-saves/
├── LRGEXSync.exe          # The app
├── backup/                # Compressed backups
│   ├── hermes/
│   │   └── hermes.tar.zst
│   └── Saved Games/
│       └── Saved Games.tar.zst
├── _versions/             # Snapshot history
└── .lrgex/                # Internal state (hidden)
    ├── junction-config.json
    ├── sync.log
    └── sync-status.json
```
