# Troubleshooting

## "sync-runner.vbs not found"
You have an old scheduled task from the PowerShell version. Delete it:
```
schtasks /Delete /TN "LRGEX-FolderSync" /F
```

## Restore says "needs admin"
Folders in `C:\Program Files\` require elevation:
- Right-click exe → Run as Administrator
- Or remove the Program Files folder from your sync list

## App doesn't launch on VM
The app uses software rendering by default — works on VMs without GPU.
If it still doesn't launch, check `sync.log` in the `.lrgex/` folder for crash info.

## Backup is slow
Large folders (100K+ files) take time to walk and compress. This is filesystem I/O, not a bug.
The health bar shows progress percentage during compression.

## Restore is slower than backup
Backup reads many files → writes one archive (fast).
Restore reads one archive → writes many files (slow — each file needs filesystem metadata).
This is normal NTFS behavior.

## Hermes/imports backup missing
Check Tools → Backup Health Check. Shows each folder's:
- Backup size
- Age (hours/days ago)
- Source status (exists/missing)
- STALE flag if older than sync interval

## Config paths broken after format
Paths auto-heal on launch. If a folder references a different username, it's replaced with the current user's profile automatically.
