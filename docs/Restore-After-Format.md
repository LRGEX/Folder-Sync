# Restore After Format

## How It Works
After formatting your PC:
1. Install Windows
2. Install your cloud client (OneDrive, etc.)
3. Wait for the LRGEX-saves folder to sync
4. Double-click `LRGEXSync.exe`
5. Click **Restore All**
6. All your folders are restored to their original locations

## Path Healing
If your Windows username changed (e.g., `Bob` → `Robert`):
- Paths like `C:\Users\Bob\Saved Games` auto-heal to `C:\Users\Robert\Saved Games`
- No manual path fixing needed
- Config uses portable paths (`%USERPROFILE%`, `%LOCALAPPDATA%`, etc.)

## Program Files Folders
Folders in `C:\Program Files\` require the app to run as Administrator:
- Right-click `LRGEXSync.exe` → Run as Administrator
- Or remove Program Files folders from your sync list

## Save-ID Migration
For game saves with numeric user-ID folders:
- App detects the old user-ID folder after restore
- Auto-migrates saves to the new user-ID
- Three-state safety: only migrates when confident (score-based)
