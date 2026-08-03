# Configuration

## Sync Interval
Tools → Set Sync Interval (in minutes)
- Under 1440 minutes: runs at exact interval
- 1440+ minutes: runs daily

## Exclusions
Tools → Manage Exclusions
- Add folder names to skip (e.g., `node_modules`, `.git`, `cache`)
- Applied to all synced folders

## Max Versions
Tools → Set Max Versions
- How many snapshot versions to keep per folder
- Default: 5
- Older versions auto-deleted when limit reached

## Right-Click Sync
Tools → Right-Click Sync
- Adds "Sync folder (LRGEX)" to Windows Explorer right-click menu
- Click to enable/disable
- Registry-based (HKCU, reversible)

## Export/Import Config
Tools → Export/Import Configuration
- Export: saves all settings as JSON (portable paths)
- Import: loads settings from JSON
- Useful for backing up config or transferring to another PC

## Internal State
All internal files live in `.lrgex/` subfolder:
- `junction-config.json` — folder list and settings
- `sync.log` — all sync/restore/crash logs
- `sync-status.json` — health status
- `sync-progress.txt` — current operation progress
