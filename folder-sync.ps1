# LRGEX Folder Sync
# Backs up folders to your chosen sync home so they survive a PC format
# Features: Create junctions, save configurations, restore after PC format

param(
    [switch]$AutoRestore,
    [switch]$Sync,
    [string]$Link
)

# Self-unblock to prevent security warnings
try {
    $currentScript = $MyInvocation.MyCommand.Path
    if ($currentScript -and (Test-Path $currentScript)) {
        Unblock-File -Path $currentScript -ErrorAction SilentlyContinue
    }
} catch { 
    # Ignore errors - file may already be unblocked
}

<#
.SYNOPSIS
    Returns the folder the running script lives in (HOME). Cloud-agnostic.
.DESCRIPTION
    Everything (config, sync targets, cache) is relative to the script's OWN folder.
    Works on any PC / any user / any cloud (or none). Nothing is hardcoded.
.OUTPUTS [string] the script's folder path.
#>
function ConvertTo-Bool {
    # Safe bool parse. CRITICAL: [bool]"false" is $true in PowerShell, which would make
    # auto-restore fire when the user thinks it's OFF. This treats "false" correctly.
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    if ($Value -is [string]) { return $Value.Trim() -match '^(?i:true|1|yes|on)$' }
    return [bool]$Value
}
function Get-ScriptDir {
    $p = $null
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $p = $PSCommandPath }
    elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) { $p = $MyInvocation.MyCommand.Path }
    else {
        try {
            foreach ($frame in (Get-PSCallStack)) {
                if ($frame.ScriptName -and (Test-Path $frame.ScriptName) -and $frame.ScriptName.EndsWith('.ps1')) { $p = $frame.ScriptName; break }
            }
        } catch { }
    }
    if (-not $p) { return (Get-Location).Path }
    return (Split-Path $p -Parent)
}

<#
.SYNOPSIS
    Returns $true if the script is running from its HOME folder.
.DESCRIPTION
    HOME = the folder containing the hidden .lrgex-home marker (created at first-run setup).
    Marker-based so ANY folder name works - nothing hardcoded.
#>
function Test-IsHome {
    return (Test-Path (Join-Path (Get-ScriptDir) '.lrgex-home'))
}

<#
.SYNOPSIS
    Detects a known cloud-sync root (OneDrive / Google Drive / Mega / Dropbox / iCloud) for the
    first-run SUGGESTION only. Returns $null if none found. The tool never REQUIRES a cloud.
#>
function Get-CloudRootSuggestion {
    $candidates = @()
    if ($env:OneDrive) { $candidates += $env:OneDrive }
    if ($env:OneDriveCommercial) { $candidates += $env:OneDriveCommercial }
    $user = $env:USERPROFILE
    if ($user) {
        $candidates += (Join-Path $user 'Google Drive')
        $candidates += (Join-Path $user 'MEGA')
        $candidates += (Join-Path $user 'Dropbox')
        $candidates += (Join-Path $user 'iCloudDrive')
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

<#
.SYNOPSIS
    Legacy OneDrive\Documents resolver. Kept for backward compatibility; new code uses Get-ScriptDir.
#>
function Get-OneDrivePathRaw {
    $od = $Env:OneDrive
    if ([string]::IsNullOrEmpty($od)) {
        try { $od = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\OneDrive" -ErrorAction Stop).UserFolder } catch { $od = $null }
    }
    if ([string]::IsNullOrEmpty($od)) { return [Environment]::GetFolderPath("MyDocuments") }
    return Join-Path $od "Documents"
}

<#
.SYNOPSIS
    Portable setup: if the script is NOT yet in its home folder, ask the user to pick ANY folder
    (cloud strongly recommended), copy itself + create the config + drop a marker there, and
    relaunch. If already home, do nothing.
.DESCRIPTION
    HOME = the folder containing the hidden .lrgex-home marker. Any folder name works - nothing
    is hardcoded - and the tool is fully cloud-agnostic (OneDrive / Google Drive / Mega / Dropbox
    / iCloud / or even a plain local folder).
    - Bare GUI launch, NOT home -> ASK the user to pick the home folder (FolderBrowserDialog,
      pre-filled with a detected cloud root if any). If the picked folder is NOT under a known
      cloud root, show a NON-BLOCKING warning that backups won't auto-sync / survive a format,
      then proceed anyway (the user's choice). Copy the script there, create a fresh
      junction-config.json ONLY if one doesn't already exist (preserves post-format data), write
      the .lrgex-home marker, then relaunch from home (elevating for the GUI) and exit.
    - Already home -> return immediately (no prompt).
    - Flag modes (-Sync/-AutoRestore/-Link) never prompt.
    Universal: run it from ANY path/partition/PC and it sets itself up.
.OUTPUTS none. May exit the process after relaunch.
#>
function Test-AndRelocateScript {
    # --- Detect our own path (Methods 1-3, then a generic fallback search) ---
    $currentPath = $null
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $currentPath = $PSCommandPath
    } elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
        $currentPath = $MyInvocation.MyCommand.Path
    } else {
        try {
            $callStack = Get-PSCallStack
            foreach ($frame in $callStack) {
                if ($frame.ScriptName -and (Test-Path $frame.ScriptName) -and $frame.ScriptName.EndsWith(".ps1")) {
                    $currentPath = $frame.ScriptName
                    break
                }
            }
        } catch { }
    }
    # Method 4: generic fallback search (current dir / Desktop)
    if ([string]::IsNullOrEmpty($currentPath) -or !(Test-Path $currentPath)) {
        $scriptName = "folder-sync.ps1"
        $searchPaths = @(
            (Join-Path $pwd $scriptName),
            (Join-Path ([Environment]::GetFolderPath("Desktop")) $scriptName)
        )
        foreach ($path in $searchPaths) {
            if (Test-Path $path) { $currentPath = $path; break }
        }
    }
    if ([string]::IsNullOrEmpty($currentPath) -or !(Test-Path $currentPath)) {
        Write-Host "Could not determine current script path, skipping setup" -ForegroundColor Yellow
        return
    }

    # --- Are we already HOME? (hidden .lrgex-home marker next to the script) ---
    $dir = Split-Path $currentPath -Parent
    if (Test-Path (Join-Path $dir '.lrgex-home')) { return }

    # --- Flag modes only ever run from home; if reached from a non-home copy, just proceed. ---
    if ($Sync -or $AutoRestore -or $Link) { return }

    # --- BARE launch from a portable copy -> FIRST-RUN SETUP: pick the home folder. ---
    Add-Type -AssemblyName System.Windows.Forms
    $cloudRoot = Get-CloudRootSuggestion
    $preselect = $cloudRoot
    if (-not $preselect -or -not (Test-Path $preselect)) { $preselect = [Environment]::GetFolderPath("UserProfile") }

    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = "Pick the folder where LRGEX sync will live.`n`nRECOMMENDED: a folder inside a cloud service (OneDrive, Google Drive, Mega, Dropbox, iCloud) so your backups survive a PC format and sync across machines.`n`nYou may pick ANY folder, but a non-cloud folder will NOT survive a format."
    if (Test-Path $preselect) { $fb.SelectedPath = $preselect }
    if ($fb.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $homeFolder = $fb.SelectedPath
    # Non-blocking warning if the picked folder isn't under a known cloud root.
    $underCloud = $false
    if ($cloudRoot -and $homeFolder.StartsWith($cloudRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $underCloud = $true }
    if (-not $underCloud) {
        $msg = "This folder does not appear to be inside a cloud-synced location (OneDrive / Google Drive / Mega / Dropbox / iCloud).`n`nBackups stored here will NOT sync automatically and will NOT survive a PC format.`n`nUse this folder anyway?"
        if ([System.Windows.Forms.MessageBox]::Show($msg, "Not a cloud folder", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning) -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $targetPath = Join-Path $homeFolder "folder-sync.ps1"
    $configPath = Join-Path $homeFolder "junction-config.json"
    $markerPath = Join-Path $homeFolder ".lrgex-home"

    try {
        # Copy the script itself into the chosen home folder
        Copy-Item -Path $currentPath -Destination $targetPath -Force
        try { Unblock-File -Path $targetPath -ErrorAction SilentlyContinue } catch { }
        # Create a fresh config ONLY if one doesn't exist (preserves recovered data post-format)
        if (-not (Test-Path $configPath)) {
            @{ Junctions = @(); AutoRestoreEnabled = $false } | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
        }
        # Drop the home marker so we recognize this folder later (any folder name works)
        if (-not (Test-Path $markerPath)) { New-Item -Path $markerPath -ItemType File -Force | Out-Null }

        # Relaunch from home (preserve -AutoRestore/-Link flags; elevate for the GUI)
        $arguments = @("-ExecutionPolicy", "Bypass", "-File", "`"$targetPath`"")
        if ($AutoRestore) { $arguments += "-AutoRestore" }
        if ($Link) { $arguments += "-Link " + [char]34 + $Link + [char]34 }
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        try {
            if ($isAdmin) {
                Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru | Out-Null
            } else {
                Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru | Out-Null
            }
            Start-Sleep -Milliseconds 500
            exit
        } catch {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "PowerShell.exe"
            $psi.Arguments = "-ExecutionPolicy Bypass -File `"$targetPath`"" + $(if ($AutoRestore) { " -AutoRestore" }) + $(if ($Link) { " -Link " + [char]34 + $Link + [char]34 })
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $psi.CreateNoWindow = $true
            if (-not $isAdmin) { $psi.Verb = "runas" }
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            exit
        }
    } catch {
        Write-Host "Setup could not complete; continuing from current location." -ForegroundColor Yellow
    }
}

# Call self-relocation check BEFORE admin check
Test-AndRelocateScript

# Check if running as administrator, if not, restart as admin
if (-not $Link -and -not $Sync -and -not $AutoRestore -and (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))) {
    # Relaunch as administrator with hidden window from the start
    try {
        # Get the current script path using same detection method as relocation function
        $scriptPath = $null
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            $scriptPath = $PSCommandPath
        } elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
            $scriptPath = $MyInvocation.MyCommand.Path
        } else {
            # Try call stack
            try {
                $callStack = Get-PSCallStack
                foreach ($frame in $callStack) {
                    if ($frame.ScriptName -and (Test-Path $frame.ScriptName) -and $frame.ScriptName.EndsWith(".ps1")) {
                        $scriptPath = $frame.ScriptName
                        break
                    }
                }
            } catch { }
            
            # Fallback search
            if ([string]::IsNullOrEmpty($scriptPath)) {
                $scriptName = "folder-sync.ps1"
                $searchPaths = @(
                    (Join-Path $pwd $scriptName),
                    (Join-Path ([Environment]::GetFolderPath("Desktop")) $scriptName)
                )
                
                foreach ($path in $searchPaths) {
                    if (Test-Path $path) {
                        $scriptPath = $path
                        break
                    }
                }
            }
        }
        
        if ([string]::IsNullOrEmpty($scriptPath)) {
            # If we still can't find the script, exit
            exit
        }
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "PowerShell.exe"
        $psi.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`" $(if ($AutoRestore) { '-AutoRestore' })"
        $psi.Verb = "runas"
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        # If user cancels UAC, exit silently
    }
    exit
}

# Hide console window immediately for better GUI experience
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'

# Hide console window immediately (0 = hide, 5 = show)
try {
    $consolePtr = [Console.Window]::GetConsoleWindow()
    [Console.Window]::ShowWindow($consolePtr, 0)
} catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Web-based logo/icon configuration
$script:LogoUrl = "https://download.lrgex.com/Light%20Full%20logo.png"
$script:IconUrl = "https://download.lrgex.com/bigx-dark-icon.ico"
$script:AppVersion = '0.6.1'

function Get-WebAsset {
    param(
        [string]$Url,
        [string]$LocalFileName,
        [int]$MaxAgeHours = 24
    )
      try {
        $cacheDir = Join-Path (Get-ScriptDir) ".cache"
        $localPath = Join-Path $cacheDir $LocalFileName
        
        # Create cache directory if it doesn't exist
        if (-not (Test-Path $cacheDir)) {
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
        }
        
        # Check if cached file exists and is recent enough
        $shouldDownload = $true
        if (Test-Path $localPath) {
            $fileAge = (Get-Date) - (Get-Item $localPath).LastWriteTime
            if ($fileAge.TotalHours -lt $MaxAgeHours) {
                $shouldDownload = $false
            }
        }
        
        # Download if needed
        if ($shouldDownload) {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "LRGEX Folder Sync")
            $webClient.DownloadFile($Url, $localPath)
            $webClient.Dispose()
        }
        
        return $localPath
    } catch {
        # Return null if download fails - caller should handle gracefully
        return $null
    }
}

function Set-FormIcon {
    param($Form)
    
    try {
        $iconPath = Get-WebAsset -Url $script:IconUrl -LocalFileName "app-icon.ico"
        if ($iconPath -and (Test-Path $iconPath)) {
            $Form.Icon = New-Object System.Drawing.Icon($iconPath)
        } else {
            # Create a fallback programmatic icon if web download fails
            $bitmap = New-Object System.Drawing.Bitmap(32, 32)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            
            # Draw LRGEX logo colors (blue circle with "LR" text)
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 215))
            $graphics.FillEllipse($brush, 2, 2, 28, 28)
            
            $font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold)
            $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $graphics.DrawString("LR", $font, $textBrush, 8, 10)
            
            $graphics.Dispose()
            $brush.Dispose()
            $textBrush.Dispose()
            $font.Dispose()
            
            # Convert bitmap to icon
            $iconHandle = $bitmap.GetHicon()
            $Form.Icon = [System.Drawing.Icon]::FromHandle($iconHandle)
        }
    } catch {
        # Silently ignore icon loading errors
    }
}

function Add-LogoPanel {
    param($Form)
    
    try {
        # Increase form size to accommodate logo
        $Form.Size = New-Object System.Drawing.Size(520, 545)
        
        # Create logo panel
        $logoPanel = New-Object System.Windows.Forms.Panel
        $logoPanel.Location = New-Object System.Drawing.Point(10, 30)
        $logoPanel.Size = New-Object System.Drawing.Size(490, 60)
        $logoPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
        $logoPanel.BorderStyle = 'FixedSingle'
        $Form.Controls.Add($logoPanel)
        
        # Try to load logo from web
        $logoPath = Get-WebAsset -Url $script:LogoUrl -LocalFileName "logo.png"
        
        if ($logoPath -and (Test-Path $logoPath)) {
            # Use web-downloaded logo
            $logoPictureBox = New-Object System.Windows.Forms.PictureBox
            $logoPictureBox.Location = New-Object System.Drawing.Point(10, 10)
            $logoPictureBox.Size = New-Object System.Drawing.Size(120, 40)
            $logoPictureBox.SizeMode = 'Zoom'
            $logoPictureBox.Image = [System.Drawing.Image]::FromFile($logoPath)
            $logoPanel.Controls.Add($logoPictureBox)
              # Company text next to logo
            $logoLabel = New-Object System.Windows.Forms.Label
            $logoLabel.Location = New-Object System.Drawing.Point(140, 6)
            $logoLabel.Size = New-Object System.Drawing.Size(340, 34)
            $logoLabel.Text = "Folder Sync"
            $logoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
            $logoLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
            $logoPanel.Controls.Add($logoLabel)
            $verLabel = New-Object System.Windows.Forms.Label
            $verLabel.Location = New-Object System.Drawing.Point(140, 42)
            $verLabel.Size = New-Object System.Drawing.Size(200, 16)
            $verLabel.Text = 'v' + $script:AppVersion
            $verLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            $verLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
            $logoPanel.Controls.Add($verLabel)
        } else {            # Fallback text-only logo if web download fails
            $logoLabel = New-Object System.Windows.Forms.Label
            $logoLabel.Location = New-Object System.Drawing.Point(10, 6)
            $logoLabel.Size = New-Object System.Drawing.Size(470, 34)
            $logoLabel.Text = "LRGEX Folder Sync"
            $logoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
            $logoLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
            $logoLabel.TextAlign = 'MiddleCenter'
            $logoPanel.Controls.Add($logoLabel)
            $verLabel = New-Object System.Windows.Forms.Label
            $verLabel.Location = New-Object System.Drawing.Point(10, 42)
            $verLabel.Size = New-Object System.Drawing.Size(470, 16)
            $verLabel.Text = 'v' + $script:AppVersion
            $verLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            $verLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
            $verLabel.TextAlign = 'MiddleCenter'
            $logoPanel.Controls.Add($verLabel)}
        
    } catch {
        # If logo panel creation fails, continue without it
    }
}

function Get-OneDrivePath {
    # Legacy wrapper kept for backward compat. New code uses Get-ScriptDir (home).
    return Get-OneDrivePathRaw
}

function Get-ConfigPath {
    # Config lives next to the script (home = the script's own folder). Cloud-agnostic.
    return Join-Path (Get-ScriptDir) "junction-config.json"
}

function Get-JunctionConfig {
    $configPath = Get-ConfigPath
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath | ConvertFrom-Json
            # Handle legacy format (just array of junctions)
            if ($config -is [array]) {
                return @{
                    AutoRestoreEnabled = $false
                    Junctions = $config
                }
            }
            # New format with settings
            if (-not $config.PSObject.Properties.Name -contains "AutoRestoreEnabled") {
                $config | Add-Member -NotePropertyName "AutoRestoreEnabled" -NotePropertyValue $false
            }
            if (-not $config.PSObject.Properties.Name -contains "Junctions") {
                $config | Add-Member -NotePropertyName "Junctions" -NotePropertyValue @()
            }
            return $config
        } catch {
            return @{
                AutoRestoreEnabled = $false
                Junctions = @()
            }
        }
    }
    return @{
        AutoRestoreEnabled = $false
        Junctions = @()
    }
}

<#
.SYNOPSIS
    Safely clears a junction link path before (re)creating a junction.
.DESCRIPTION
    Replaces the old destructive Remove-Item -Recurse that could delete real
    downloaded files after a format. Behavior:
      - Missing path              -> nothing to do (success)
      - Reparse point (junction)  -> remove the link only (safe, no data behind it)
      - Empty real folder         -> remove (safe)
      - Real folder WITH files    -> NEVER delete:
          * source empty/missing  -> move recovered files INTO the source (post-format restore)
          * source already has data -> move the OneDrive copy aside to -RESTORED-<timestamp>
    On any failure it returns $false (caller skips) so real data is never destroyed.
.PARAMETER JunctionPath
    The path where the junction link will be created (inside OneDrive).
.PARAMETER SourcePath
    The original local folder the junction should point to.
.OUTPUTS
    [bool] $true if the path is clear and the junction can be created; $false on failure.
#>
function Clear-JunctionPath {
    param(
        [string]$JunctionPath,
        [string]$SourcePath
    )
    try {
        if (-not (Test-Path $JunctionPath)) { return $true }

        $item = Get-Item $JunctionPath -Force -ErrorAction Stop

        # A reparse point is just a link -> remove the link ONLY, never the target's contents.
        # Remove-Item crashes on a junction whose target is non-empty, so use rmdir (primary) and
        # .NET Directory.Delete($false) (fallback). Both delete the reparse point without touching target data.
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir "`"$JunctionPath`"" 2>$null | Out-Null
            if (Test-Path $JunctionPath) {
                try { [System.IO.Directory]::Delete($JunctionPath, $false) } catch { }
            }
            return (-not (Test-Path $JunctionPath))
        }

        # It's a real folder. Does it contain anything?
        $hasContent = ((Get-ChildItem $JunctionPath -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
        if (-not $hasContent) {
            Remove-Item $JunctionPath -Force -Recurse -ErrorAction Stop
            return $true
        }

        # Real folder WITH files -> never delete. Decide where the data should go.
        $sourceHasContent = (Test-Path $SourcePath) -and ((Get-ChildItem $SourcePath -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)

        if (-not $sourceHasContent) {
            # Post-format restore: source is empty/missing. Move recovered files to their real home.
            if (-not (Test-Path $SourcePath)) {
                New-Item -Path $SourcePath -ItemType Directory -Force | Out-Null
            }
            Get-ChildItem $JunctionPath -Force | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $SourcePath -Force -ErrorAction SilentlyContinue
            }
            Remove-Item $JunctionPath -Force -ErrorAction SilentlyContinue
            return $true
        } else {
            # Conflict: both spots have data. Don't destroy anything - move OneDrive copy aside.
            $aside = "$JunctionPath-RESTORED-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -Path $JunctionPath -Destination $aside -Force -ErrorAction Stop
            return $true
        }
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    Returns the backup path where a folder pair's real files are stored (cloud-agnostic).
.DESCRIPTION
    Synced files live INSIDE the script's own folder (home): <home>\<sourceLeaf>.
    Real files (no junction) so any cloud service (or none) syncs them normally.
#>
function Get-PairCloudPath {
    param([string]$SourcePath, [string]$TargetRelativePath)
    # Cloud-agnostic: synced files live INSIDE the script's own folder (home): <home>\<sourceLeaf>.
    # TargetRelativePath is accepted for backward compatibility but ignored (home is the destination).
    $leaf = Split-Path -Path $SourcePath -Leaf
    return Join-Path (Get-ScriptDir) $leaf
}

<#
.SYNOPSIS
    Mirror a folder TO OneDrive (backup direction). Copy-only.
.DESCRIPTION
    robocopy /E with NO /MIR and NO purge -> nothing is ever deleted. New/changed files
    in the source are copied into the OneDrive cloud folder; the cloud copy keeps everything
    (archive + latest versions). This robocopy mirror is the engine that replaced junctions.
.OUTPUTS [bool] $true if robocopy succeeded (exit code < 8).
#>
function Sync-PairToCloud {
    param([string]$SourcePath, [string]$TargetRelativePath)
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path $SourcePath)) { return $false }
    $tmpLog = [System.IO.Path]::GetTempFileName()
    try {
        $cloud = Get-PairCloudPath -SourcePath $SourcePath -TargetRelativePath $TargetRelativePath
        $parent = Split-Path $cloud -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        # Capture robocopy output to a temp log so failures can be EXPLAINED in the sync log.
        # /XD: skip app-locked runtime subfolders listed in config (ExcludedNames).
        # Build args as an array + splat so /XD + names are separate tokens (string concat broke robocopy).
        $names = @()
        try { $cfgX = Get-JunctionConfig; if ($cfgX.PSObject.Properties.Name -contains 'ExcludedNames' -and $cfgX.ExcludedNames) { $names = @($cfgX.ExcludedNames | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }) } } catch { }
        $rcArgs = @("$SourcePath", "$cloud", '/E', '/XJ', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:5', '/W:5')
        if ($names.Count) { $rcArgs += '/XD'; $rcArgs += $names }
        $rcArgs += "/LOG:$tmpLog"
        & robocopy.exe @rcArgs
        $code = $LASTEXITCODE
        if ($code -lt 8) { return $true }
        # Failure: capture the human reason (e.g. "Access is denied.") for a clean log line.
        $reason = "robocopy exit $code"
        try {
            $reasonPat = 'Access is denied|being used by another process|cannot find the|not enough space|syntax is incorrect|The process cannot access|already exists|is not a valid|file name is too long'
            $found = Get-Content $tmpLog -ErrorAction SilentlyContinue | Select-String -Pattern 'ERROR' -Context 0,4
            if ($found) {
                foreach ($m in $found) {
                    $why = $m.Context.PostContext | Where-Object { $_ -and $_ -match $reasonPat } | Select-Object -First 1
                    if ($why) { $reason = $why.Trim(); break }
                }
            }
        } catch { }
        $leaf = Split-Path $SourcePath -Leaf
        Write-SyncLog ("  [FAIL] " + $leaf + "  -  " + $reason)
        return $false
    } catch { return $false }
    finally { Remove-Item $tmpLog -Force -ErrorAction SilentlyContinue }
}

<#
.SYNOPSIS
    Restore a folder FROM OneDrive to its original path. Copy-only, never deletes.
.DESCRIPTION
    After a format, OneDrive holds the real recovered files; this copies them back to SourcePath.
    robocopy /E with NO purge -> nothing in either location is deleted. The cloud copy stays intact.
.OUTPUTS [bool] $true if robocopy succeeded (exit code < 8).
#>
function Restore-PairFromCloud {
    param([string]$SourcePath, [string]$TargetRelativePath)
    $tmpLog = [System.IO.Path]::GetTempFileName()
    try {
        $cloud = Get-PairCloudPath -SourcePath $SourcePath -TargetRelativePath $TargetRelativePath
        if (-not (Test-Path $cloud)) { return $false }
        if (-not (Test-Path $SourcePath)) { New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null }
        robocopy.exe "$cloud" "$SourcePath" /E /XJ /NFL /NDL /NJH /NJS /NP /R:5 /W:5 /LOG:"$tmpLog" | Out-Null
        $code = $LASTEXITCODE
        if ($code -lt 8) { return $true }
        $reason = 'no detail captured'
        try {
            $found = Get-Content $tmpLog -ErrorAction SilentlyContinue | Select-String -Pattern 'ERROR' -Context 0,4
            $reasonPat = 'Access is denied|being used by another process|cannot find the|not enough space|syntax is incorrect|The process cannot access|already exists|is not a valid|file name is too long'
            if ($found) {
                $seen = @{}
                $bits = foreach ($m in $found) {
                    $main = ($m.Line -replace '^\d+/\d+/\d+ \d+:\d+:\d+ ', '').Trim()
                    if ($seen.ContainsKey($main)) { continue }
                    $seen[$main] = $true
                    $why = $m.Context.PostContext | Where-Object { $_ -and $_ -match $reasonPat } | Select-Object -First 1
                    if ($why) { "$main -> $($why.Trim())" } else { $main }
                }
                $reason = ($bits | Select-Object -First 3) -join '  |  '
            }
        } catch { }
        Write-SyncLog "RESTORE FAIL : $SourcePath (robocopy exit $code) -> $reason"
        return $false
    } catch { return $false }
    finally { Remove-Item $tmpLog -Force -ErrorAction SilentlyContinue }
}

<#
.SYNOPSIS
    Mirror ALL registered folder pairs to OneDrive. Used by the periodic background sync task.
.OUTPUTS hashtable @{ Ok = <int>; Fail = <int> }
#>
function Sync-AllPairs {
    $config = Get-JunctionConfig
    $ok = 0; $fail = 0; $restored = 0; $restoredNames = @()
    Write-SyncLog ('------------------------------------------------------------')
    Write-SyncLog ("Sync cycle  -  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    if ($config.Junctions) {
        foreach ($j in $config.Junctions) {
            $src = $j.SourcePath
            $leaf = Split-Path $src -Leaf
            # Absence-driven auto-restore: if the source is MISSING/empty (post-format) AND this
            # pair has auto-restore on AND a backup exists -> restore it. NOT a login trigger.
            $doAuto = $true
            if ($j.PSObject.Properties.Name -contains 'AutoRestore') { $doAuto = (ConvertTo-Bool $j.AutoRestore) }
            $missing = (-not (Test-Path $src)) -or ((Get-ChildItem $src -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)
            if ($missing -and $doAuto) {
                if (Restore-PairFromCloud -SourcePath $src -TargetRelativePath $j.TargetRelativePath) {
                    $restored++; $restoredNames += $leaf; Write-SyncLog ("  [RESTORE] " + $leaf + "  -  was missing, restored from backup")
                } else {
                    $fail++; Write-SyncLog ("  [FAIL] " + $leaf + "  -  restore failed")
                }
            } elseif (Sync-PairToCloud -SourcePath $src -TargetRelativePath $j.TargetRelativePath) {
                $ok++; Write-SyncLog ("  [ OK ] " + $leaf)
            } else {
                $fail++
            }
        }
    }
    Write-SyncLog ("Done: $ok mirrored, $restored restored, $fail failed.")
    Write-SyncStatus -Ok ($ok + $restored) -Fail $fail -Restored $restored -RestoredNames $restoredNames
    return @{ Ok = ($ok + $restored); Fail = $fail }
}



function Save-JunctionConfig {
    param($sourcePath, $autoRestore = $true)
    
    $configPath = Get-ConfigPath
    $config = Get-JunctionConfig
    
    # Add new junction to config (avoid duplicates). Destination is always the home folder
    # (<home>\<leaf>) - there is no per-pair target, so none is stored. AutoRestore is the
    # per-pair opt-in for post-format auto-restore (asked at link time).
    $newJunction = @{
        SourcePath = $sourcePath
        AutoRestore = [bool]$autoRestore
        Created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    # Remove existing entry with same source path
    $filteredJunctions = $config.Junctions | Where-Object { $_.SourcePath -ne $sourcePath }
    
    # Convert to proper array and add new junction
    $junctionArray = @()
    if ($filteredJunctions) {
        $junctionArray += $filteredJunctions
    }
    $junctionArray += $newJunction
    
    # Update config with new array
    $config.Junctions = $junctionArray
    
    # Save config
    try {
        $config | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
    } catch {
        # Ignore save errors
    }
}

function Save-AutoRestoreSettings {
    param([bool]$Enabled)
    
    $configPath = Get-ConfigPath
    $config = Get-JunctionConfig
    $config.AutoRestoreEnabled = $Enabled
    
    # Save config
    try {
        $config | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
    } catch {
        # Ignore save errors
    }
}

function Export-JunctionConfig {
    $config = Get-JunctionConfig
    if ($config.Junctions.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No junction configurations to export.","No Config","OK","Information")
        return
    }
      $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $saveDialog.Title = "Export Junction Configuration"
    $saveDialog.FileName = "junction-config.json"
    
    if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $config | ConvertTo-Json -Depth 3 | Set-Content $saveDialog.FileName -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("Configuration exported successfully to:`n$($saveDialog.FileName)","Export Success","OK","Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to export configuration:`n$_","Export Error","OK","Error")
        }
    }
}

function Import-JunctionConfig {
    $openDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $openDialog.Title = "Import Junction Configuration"
    
    if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $importedConfig = Get-Content $openDialog.FileName | ConvertFrom-Json
            $currentConfig = Get-JunctionConfig
            
            # Handle legacy format (just array of junctions)
            if ($importedConfig -is [array]) {
                $importedConfig = @{
                    AutoRestoreEnabled = $false
                    Junctions = $importedConfig
                }
            }
              # Merge configurations (imported takes precedence)
            $mergedJunctions = @()
            
            $importedPaths = $importedConfig.Junctions | ForEach-Object { $_.SourcePath }
            
            # Add imported configs
            if ($importedConfig.Junctions) {
                $mergedJunctions += $importedConfig.Junctions
            }
            
            # Add current configs that don't conflict
            $currentConfig.Junctions | ForEach-Object {
                if ($_.SourcePath -notin $importedPaths) {
                    $mergedJunctions += $_
                }
            }
            
            $mergedConfig = @{
                AutoRestoreEnabled = $importedConfig.AutoRestoreEnabled
                Junctions = $mergedJunctions
            }
            
            # Save merged config
            $configPath = Get-ConfigPath
            $mergedConfig | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
            
            [System.Windows.Forms.MessageBox]::Show("Configuration imported successfully!`n$($importedConfig.Junctions.Count) junctions imported.`nAuto-restore setting: $($importedConfig.AutoRestoreEnabled)","Import Success","OK","Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to import configuration:`n$_","Import Error","OK","Error")
        }
    }
}

function Test-JunctionHealth {
    $config = Get-JunctionConfig
    if ($config.Junctions.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No junction configurations found to check.","No Config","OK","Information")
        return
    }
      # Create health check form
    $healthForm = New-Object System.Windows.Forms.Form
    $healthForm.Text = "Junction Health Check"
    $healthForm.Size = New-Object System.Drawing.Size(700,500)
    $healthForm.StartPosition = "CenterScreen"
    $healthForm.FormBorderStyle = 'FixedDialog'
    $healthForm.MaximizeBox = $false
    $healthForm.TopMost = $true
    
    # Results text box
    $resultsText = New-Object System.Windows.Forms.TextBox
    $resultsText.Location = New-Object System.Drawing.Point(10,10)
    $resultsText.Size = New-Object System.Drawing.Size(665,400)
    $resultsText.Multiline = $true
    $resultsText.ScrollBars = 'Vertical'
    $resultsText.ReadOnly = $true
    $resultsText.Font = New-Object System.Drawing.Font("Consolas", 9)
    $healthForm.Controls.Add($resultsText)
    
    # Close button
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Location = New-Object System.Drawing.Point(610,420)
    $btnClose.Size = New-Object System.Drawing.Size(75,30)
    $btnClose.Text = "Close"
    $btnClose.Add_Click({ $healthForm.Close() })
    $healthForm.Controls.Add($btnClose)
    
    # Perform health check
    $results = @()
    $results += "=== Junction Health Check Results ==="
    $results += "Checked: $(Get-Date)"
    $results += "Auto-Restore: $($config.AutoRestoreEnabled)"
    $results += ""
    
    $healthy = 0
    $broken = 0
    $missing = 0
      foreach ($junction in $config.Junctions) {
        $sourcePath = $junction.SourcePath
        $junctionPath = Get-PairCloudPath -SourcePath $sourcePath
        
        $results += "Checking: $sourcePath"
        
        if (-not (Test-Path $junctionPath)) {
            $results += "  [ERROR] MISSING: Junction not found at $junctionPath"
            $missing++
        } else {            # Check if it's a valid junction
            try {
                $dirInfo = Get-Item $junctionPath -Force
                if ($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $fsutil = cmd /c "fsutil reparsepoint query `"$junctionPath`"" 2>$null
                    # Ensure fsutil output exists and is not null/empty before regex matching
                    if ($fsutil -and ($fsutil | Out-String).Trim() -ne "") {
                        $fsutilText = $fsutil | Out-String
                        if ($fsutilText -match "Print Name:\s*(.+)") {
                            $existingTarget = $matches[1].Trim()
                            if ($existingTarget -eq $sourcePath) {
                                $results += "  [OK] HEALTHY: Junction points correctly to $sourcePath"
                                $healthy++
                            } else {
                                $results += "  [WARN] BROKEN: Junction points to wrong location: $existingTarget"
                                $broken++
                            }
                        } else {
                            $results += "  [ERROR] BROKEN: Cannot determine junction target"
                            $broken++
                        }
                    } else {
                        $results += "  [ERROR] BROKEN: fsutil returned no output"
                        $broken++
                    }
                } else {
                    $results += "  [ERROR] BROKEN: Path exists but is not a junction"
                    $broken++
                }
            } catch {
                $results += "  [ERROR] ERROR: Cannot check junction: $_"
                $broken++
            }}
        $results += ""
    }
    
    $results += "=== Summary ==="
    $results += "[OK] Healthy: $healthy"
    $results += "[WARN] Broken: $broken"
    $results += "[ERROR] Missing: $missing"
    $results += "[TOTAL] Total: $($config.Junctions.Count)"
    
    $resultsText.Text = $results -join "`r`n"
    $resultsText.SelectionStart = 0
    $resultsText.SelectionLength = 0
    
    [void]$healthForm.ShowDialog()
}

function Set-AutoRestoreSettings {
    param([bool]$Enable)
    
    # Save setting to JSON config
    $configPath = Get-ConfigPath
    $config = Get-JunctionConfig
    $config.AutoRestoreEnabled = $Enable
    
    # Save config
    try {
        $config | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
    } catch {
        # Ignore save errors
    }
      $taskName = "LRGEX-AutoRestore"
      $legacyTaskName = "OneDriveJunctionRestore"   # pre-cloud-agnostic name; cleaned up on enable/disable
    
    # Get script path using same detection method
    $scriptPath = $null
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $scriptPath = $PSCommandPath
    } elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
        $scriptPath = $MyInvocation.MyCommand.Path
    } else {
        # Try call stack
        try {
            $callStack = Get-PSCallStack
            foreach ($frame in $callStack) {
                if ($frame.ScriptName -and (Test-Path $frame.ScriptName) -and $frame.ScriptName.EndsWith(".ps1")) {
                    $scriptPath = $frame.ScriptName
                    break
                }
            }
        } catch { }
        
        # Fallback: the home folder (script's own folder)
        if ([string]::IsNullOrEmpty($scriptPath)) {
            $homeScript = Join-Path (Get-ScriptDir) "folder-sync.ps1"
            if (Test-Path $homeScript) { $scriptPath = $homeScript }
        }
    }
      try {
        if ($Enable) {
            # Create scheduled task for startup with smart conditions
            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument ('-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -AutoRestore')
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            
            # Smart settings: Don't run too frequently, allow battery operation
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Hours 1) -RestartCount 3
            
            # Migration: remove any task left over from older versions (old task name).
            Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false -ErrorAction SilentlyContinue
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            [System.Windows.Forms.MessageBox]::Show("Auto-restore enabled.`nSetting saved to JSON config (in your sync home folder).`nOn each login it restores a folder ONLY if its original path is missing or empty (e.g. after a format). On normal logins, nothing happens.","Auto-Restore Enabled","OK","Information")
        } else {
            # Remove scheduled task (new + legacy names, for cleanliness)
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show("Auto-restore disabled.`nSetting saved to JSON config (in your sync home folder).","Auto-Restore Disabled","OK","Information")
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to configure auto-restore:`n$_","Auto-Restore Error","OK","Error")
    }
}

<#
.SYNOPSIS
    Adds/removes the File Explorer right-click "Sync folder (LRGEX)" entry.
.DESCRIPTION
    Registry command passes ONLY the folder (%V) to -Link; destination resolved dynamically.
    Enabling also ensures the JSON knows the default destination and (re)creates the
    continuous background sync task once (this GUI runs elevated).
#>
function Set-RightClickMenu {
    param([bool]$Enable)
    $regKey = "HKCU:\Software\Classes\Directory\shell\LRGEXSync"
    try {
        if ($Enable) {
            $scriptPath = $null
            if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $scriptPath = $PSCommandPath }
            elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) { $scriptPath = $MyInvocation.MyCommand.Path }
            else {
                $homeScript = Join-Path (Get-ScriptDir) "folder-sync.ps1"
                if (Test-Path $homeScript) { $scriptPath = $homeScript }
            }
            if (-not $scriptPath) { [System.Windows.Forms.MessageBox]::Show("Could not find the script path.","LRGEX Sync","OK","Warning") | Out-Null; return }
            Set-SyncTask -Enable $true
            New-Item -Path $regKey -Force | Out-Null
            Set-ItemProperty -Path $regKey -Name '(Default)' -Value 'Sync folder (LRGEX)'
            Set-ItemProperty -Path $regKey -Name 'Icon' -Value 'shell32.dll,165'
            $cmdKey = "$regKey\command"
            New-Item -Path $cmdKey -Force | Out-Null
            $cmd = 'PowerShell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '" -Link "%V"'
            Set-ItemProperty -Path $cmdKey -Name '(Default)' -Value $cmd
            [System.Windows.Forms.MessageBox]::Show("Right-click 'Sync folder' enabled!`nRight-click any folder to sync it. Background sync is also on.","LRGEX Sync","OK","Information") | Out-Null
        } else {
            Remove-Item -Path $regKey -Recurse -Force -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show("Right-click sync removed.","LRGEX Sync","OK","Information") | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed: $_","LRGEX Sync","OK","Error") | Out-Null
    }
}

function Test-AutoRestoreSettings {
    # Check JSON config first (primary source of truth)
    $config = Get-JunctionConfig
    return $config.AutoRestoreEnabled
}

<#
.SYNOPSIS
    Returns the health of the continuous sync task for the UI lamp.
.DESCRIPTION
    GREEN  = task registered, last run succeeded (0) and within the last hour.
    AMBER  = a sync is currently running (State=Running or result 267009). NEVER red while running.
    RED    = task missing / never ran / last run failed (real error code) / stale (>1h).
    This is what stops the user from being blind to a broken sync.
.OUTPUTS hashtable @{ Status='GREEN'|'AMBER'|'RED'; Label=[string]; Reason=[string] }
#>
function Get-SyncHealth {
    # 1) Is the task registered, running, and recent?
    try { $t = Get-ScheduledTask -TaskName 'LRGEX-FolderSync' -ErrorAction Stop }
    catch { return @{ Status='RED'; Label='SYNC OFF'; Reason='Task not registered - enable Right-Click Sync' } }
    $i = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    $code = [int]$i.LastTaskResult
    $last = $i.LastRunTime
    if (($t.State -eq 'Running') -or ($code -eq 267009)) { return @{ Status='AMBER'; Label='SYNCING'; Reason='Running now' } }
    if ($code -eq 267011 -or -not $last -or $last.Year -lt 2000) { return @{ Status='RED'; Label='SYNC NEVER RAN'; Reason='Registered but never ran' } }
    if ($code -ne 0 -and $code -ne 267008) { return @{ Status='RED'; Label='SYNC ERROR'; Reason="Last run failed (code $code)" } }
    if ($last -lt (Get-Date).AddHours(-1)) { return @{ Status='RED'; Label='SYNC STALE'; Reason='Last run over 1h ago' } }
    # 2) Did the last sync ACTUALLY copy everything? Read the REAL outcome (exit 0 alone is not enough).
    $sp = Join-Path $env:LOCALAPPDATA 'LRGEX\sync-status.json'
    if (Test-Path $sp) {
        try {
            $s = Get-Content $sp -Raw | ConvertFrom-Json
            if ($s.Fail -gt 0) { return @{ Status='RED'; Label='SYNC HAD FAILURES'; Reason="$($s.Fail) folder(s) failed last sync - see View Sync Log" } }
            if ($s.Restored -gt 0) { return @{ Status='GREEN'; Label='RESTORED ' + $s.Restored + ' folder(s)'; Reason="auto-restored: $($s.RestoredNames)  (sync OK)" } }
            return @{ Status='GREEN'; Label='SYNC OK'; Reason="Last sync $($s.LastSync) - $($s.Ok) folder(s) OK" }
        } catch { }
    }
    return @{ Status='GREEN'; Label='SYNC OK'; Reason="Last run $($last.ToString('HH:mm'))" }
}

<#
.SYNOPSIS
    Appends a timestamped line to the sync log (inside the home folder). Capped at 2000 lines.
.DESCRIPTION
    Called by Sync-AllPairs / restore so the user has a readable history. To stop the log
    growing unbounded (the task fires every ~5 min), it is trimmed to the last 2000 lines.
#>
function Get-SyncLogPath {
    # Local (NOT in the synced home) so writing it every ~5 min doesn't churn OneDrive.
    $dir = Join-Path $env:LOCALAPPDATA 'LRGEX'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir 'folder-sync.log')
}
function Write-SyncLog {
    param([string]$Message)
    try {
        $logPath = Get-SyncLogPath
        $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
        Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        # Cap the log so it never grows unbounded.
        if (Test-Path $logPath) {
            $lines = Get-Content $logPath -ErrorAction SilentlyContinue
            if ($lines -and $lines.Count -gt 2000) {
                $lines | Select-Object -Last 2000 | Set-Content $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
            }
        }
    } catch { }
}

<#
.SYNOPSIS
    Opens a readable window showing the sync log (tail).
#>
function Write-SyncStatus {
    param([int]$Ok, [int]$Fail, [int]$Restored = 0, $RestoredNames = @())
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'LRGEX'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $path = Join-Path $dir 'sync-status.json'
        @{ LastSync = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Ok = $Ok; Fail = $Fail; Restored = $Restored; RestoredNames = ($RestoredNames -join ', ') } | ConvertTo-Json -Compress | Set-Content $path -Encoding UTF8
    } catch { }
}

function Show-Exclusions {
    Add-Type -AssemblyName System.Windows.Forms
    $cfg = Get-JunctionConfig
    $cur = if ($cfg.PSObject.Properties.Name -contains 'ExcludedNames' -and $cfg.ExcludedNames) { ($cfg.ExcludedNames -join "`r`n") } else { '' }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Manage Exclusions"
    $f.Size = New-Object System.Drawing.Size(520,420)
    $f.StartPosition = "CenterScreen"
    $f.TopMost = $true
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(10,10)
    $lbl.Size = New-Object System.Drawing.Size(480,45)
    $lbl.Text = "Subfolder NAMES to SKIP while syncing (one per line).`nUse for app-locked runtime folders (e.g. pending_messages). Matching subfolders are not backed up."
    $f.Controls.Add($lbl)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(10,60)
    $tb.Size = New-Object System.Drawing.Size(480,280)
    $tb.Multiline = $true
    $tb.ScrollBars = 'Vertical'
    $tb.Font = New-Object System.Drawing.Font("Consolas",9)
    $tb.Text = $cur
    $f.Controls.Add($tb)
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(380,348)
    $btnSave.Size = New-Object System.Drawing.Size(110,28)
    $btnSave.Text = "Save"
    $btnSave.Add_Click({
        $names = $tb.Text -split "`r`n|`n" | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
        if ($cfg.PSObject.Properties.Name -contains 'ExcludedNames') { $cfg.ExcludedNames = $names }
        else { $cfg | Add-Member -NotePropertyName ExcludedNames -NotePropertyValue $names -Force }
        $cfg | ConvertTo-Json -Depth 5 | Set-Content (Get-ConfigPath) -Encoding UTF8
        [System.Windows.Forms.MessageBox]::Show("Exclusions saved.","Exclusions","OK","Information") | Out-Null
        $f.Close()
    })
    $f.Controls.Add($btnSave)
    [void]$f.ShowDialog()
}

function Show-SyncLog {
    Add-Type -AssemblyName System.Windows.Forms
    $logPath = Get-SyncLogPath
    $lf = New-Object System.Windows.Forms.Form
    $lf.Text = "Sync Log"
    $lf.Size = New-Object System.Drawing.Size(720,520)
    $lf.StartPosition = "CenterScreen"
    $lf.TopMost = $true
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ScrollBars = 'Vertical'
    $tb.ReadOnly = $true
    $tb.Font = New-Object System.Drawing.Font("Consolas",9)
    $tb.Dock = 'Fill'
    if (Test-Path $logPath) {
        $tb.Text = ((Get-Content $logPath -Tail 500) -join "`r`n")
        $tb.SelectionStart = $tb.Text.Length
        $tb.ScrollToCaret()
    } else {
        $tb.Text = "No sync log yet. It is written on the first background sync (every ~5 min)."
    }
    $lf.Controls.Add($tb)
    [void]$lf.ShowDialog()
}

<#
.SYNOPSIS
    Enables/disables the continuous background sync task that mirrors all folder pairs to OneDrive.
.DESCRIPTION
    Registers a Windows Scheduled Task "LRGEX-FolderSync" that fires at logon AND repeats every
    IntervalMinutes. Each run executes folder-sync.ps1 -Sync, which mirrors every registered
    folder pair into OneDrive (copy-only, never deletes). The repeat interval IS the sync lag
    window (max time between a local change and it reaching the cloud).
.PARAMETER Enable
    $true to create/update the task; $false to remove it.
.PARAMETER IntervalMinutes
    Repeat interval in minutes. Default 5. This is the maximum sync lag.
#>
function Set-SyncTask {
    param([bool]$Enable, [int]$IntervalMinutes = 0)
    $taskName = "LRGEX-FolderSync"
    try {
        if ($Enable) {
            # Interval: use the passed value, else read the configured SyncIntervalMinutes (default 5).
            if ($IntervalMinutes -le 0) {
                $cfg = Get-JunctionConfig
                if ($cfg.PSObject.Properties.Name -contains 'SyncIntervalMinutes' -and $cfg.SyncIntervalMinutes -gt 0) { $IntervalMinutes = [int]$cfg.SyncIntervalMinutes }
                else { $IntervalMinutes = 5 }
            }
            $scriptPath = $null
            if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $scriptPath = $PSCommandPath }
            elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) { $scriptPath = $MyInvocation.MyCommand.Path }
            else {
                $homeScript = Join-Path (Get-ScriptDir) "folder-sync.ps1"
                if (Test-Path $homeScript) { $scriptPath = $homeScript }
            }
            if (-not $scriptPath) { return }

            # Argument built by concatenation (the old backtick-escaped quotes corrupted the
            # stored action -> "-File $" -> error 267 "directory invalid").
            $arg = '-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -Sync'
            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $arg
            # TWO triggers (you cannot reliably attach a repetition to -AtLogon directly):
            #  1) AtLogon         -> fires on every login (incl. after a format)
            #  2) Once-now+repeat -> the continuous ticker (every IntervalMinutes, indefinitely)
            $tLogon = New-ScheduledTaskTrigger -AtLogon
            $tRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
            # No -RunLevel Highest: sync only robocopies the user's OWN files (no admin needed),
            # so the task registers without elevation.
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -MultipleInstances IgnoreNew
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($tLogon, $tRepeat) -Principal $principal -Settings $settings -Force | Out-Null
            # Kick it off NOW so it never sits idle waiting for the next logon.
            Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        } else {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Remove-JunctionDialog {
    $config = Get-JunctionConfig
    if ($config.Junctions.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No junction configurations found to remove.","No Config","OK","Information")
        return
    }
      # Create remove form
    $removeForm = New-Object System.Windows.Forms.Form
    $removeForm.Text = "Remove Junctions"
    $removeForm.Size = New-Object System.Drawing.Size(600,450)
    $removeForm.StartPosition = "CenterScreen"
    $removeForm.FormBorderStyle = 'FixedDialog'
    $removeForm.MaximizeBox = $false
    $removeForm.TopMost = $true
    
    # Instructions label
    $lblInstructions = New-Object System.Windows.Forms.Label
    $lblInstructions.Location = New-Object System.Drawing.Point(10,10)
    $lblInstructions.Size = New-Object System.Drawing.Size(570,30)
    $lblInstructions.Text = "Select junctions to remove (this will delete the junction link AND remove from config):"
    $lblInstructions.ForeColor = [System.Drawing.Color]::DarkRed
    $removeForm.Controls.Add($lblInstructions)
    
    # CheckedListBox for junctions
    $checkedList = New-Object System.Windows.Forms.CheckedListBox
    $checkedList.Location = New-Object System.Drawing.Point(10,45)
    $checkedList.Size = New-Object System.Drawing.Size(570,250)
    $checkedList.CheckOnClick = $true
      foreach ($junction in $config.Junctions) {
        $displayText = "$($junction.SourcePath)"
        $checkedList.Items.Add($displayText, $false)  # Default to unchecked for safety
    }
    $removeForm.Controls.Add($checkedList)
    
    # Warning label
    $warningLabel = New-Object System.Windows.Forms.Label
    $warningLabel.Location = New-Object System.Drawing.Point(10,305)
    $warningLabel.Size = New-Object System.Drawing.Size(570,40)
    $warningLabel.Text = "âš ï¸ WARNING: This will permanently delete the junction links. The original source folders will remain safe, but you'll need to recreate junctions if you want them back."
    $warningLabel.ForeColor = [System.Drawing.Color]::DarkRed
    $warningLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 9, [System.Drawing.FontStyle]::Bold)
    $removeForm.Controls.Add($warningLabel)
    
    # Remove button
    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Location = New-Object System.Drawing.Point(400,365)
    $btnRemove.Size = New-Object System.Drawing.Size(80,25)
    $btnRemove.Text = "Remove"
    $btnRemove.UseVisualStyleBackColor = $true
    $btnRemove.BackColor = [System.Drawing.Color]::LightCoral
    $btnRemove.Add_Click({
        $selectedCount = 0
        for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
            if ($checkedList.GetItemChecked($i)) { $selectedCount++ }
        }
        
        if ($selectedCount -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select at least one junction to remove.","No Selection","OK","Warning")
            return
        }
          # Confirmation dialog
        $confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to remove $selectedCount junction(s)?`n`nThis will:`n- Delete the junction links`n- Remove them from configuration`n- Keep original source folders safe","Confirm Removal","YesNo","Warning")
          if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        $removed = 0
        $errors = 0
        $configPath = Get-ConfigPath
        $updatedConfig = Get-JunctionConfig
        $keptJunctions = @()
        
        for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
            if ($checkedList.GetItemChecked($i)) {
                $junction = $config.Junctions[$i]
                $sourcePath = $junction.SourcePath
                $targetRelPath = $junction.TargetRelativePath
                  try {
                    # Calculate junction path
                    $junctionPath = Get-PairCloudPath -SourcePath $sourcePath
                    
                    # Remove junction if it exists
                    if (Test-Path $junctionPath) {
                        Remove-Item $junctionPath -Force -Recurse -ErrorAction Stop
                    }
                    $removed++
                } catch {
                    $errors++
                }            } else {
                # Keep this junction in config
                $keptJunctions += $config.Junctions[$i]
            }
        }
        
        # Update config with kept junctions
        $updatedConfig.Junctions = $keptJunctions
        
        # Save updated configuration
        try {
            if ($updatedConfig.Junctions.Count -gt 0) {
                $updatedConfig | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
            } else {
                # Keep config file but with empty junctions array (preserve settings)
                $updatedConfig | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
            }
        } catch {
            $errors++
        }
        
        $message = "Removal complete!"
        if ($removed -gt 0) { $message += "`n[OK] Removed: $removed junctions" }
        if ($errors -gt 0) { $message += "`n[ERROR] Errors: $errors" }
        
        [System.Windows.Forms.MessageBox]::Show($message,"Removal Complete","OK","Information")
        $removeForm.Close()
    })
    $removeForm.Controls.Add($btnRemove)
    
    # Cancel button
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point(490,365)
    $btnCancel.Size = New-Object System.Drawing.Size(80,25)
    $btnCancel.Text = "Cancel"
    $btnCancel.UseVisualStyleBackColor = $true
    $btnCancel.Add_Click({ $removeForm.Close() })
    $removeForm.Controls.Add($btnCancel)
    
    [void]$removeForm.ShowDialog()
}

function Show-RestoreDialog {
    $config = Get-JunctionConfig
    if ($config.Junctions.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No saved junction configurations found.","No Config","OK","Information")
        return
    }
      # Create restore form
    $restoreForm = New-Object System.Windows.Forms.Form
    $restoreForm.Text = "Restore Saved Junctions"
    $restoreForm.Size = New-Object System.Drawing.Size(600,450)
    $restoreForm.StartPosition = "CenterScreen"
    $restoreForm.FormBorderStyle = 'FixedDialog'
    $restoreForm.MaximizeBox = $false
    $restoreForm.TopMost = $true
    
    # Instructions label
    $lblInstructions = New-Object System.Windows.Forms.Label
    $lblInstructions.Location = New-Object System.Drawing.Point(10,10)
    $lblInstructions.Size = New-Object System.Drawing.Size(570,30)
    $lblInstructions.Text = "Select junctions to restore (missing source folders will be created automatically):"
    $restoreForm.Controls.Add($lblInstructions)
    
    # CheckedListBox for junctions
    $checkedList = New-Object System.Windows.Forms.CheckedListBox
    $checkedList.Location = New-Object System.Drawing.Point(10,45)
    $checkedList.Size = New-Object System.Drawing.Size(570,250)
    $checkedList.CheckOnClick = $true
      foreach ($junction in $config.Junctions) {
        $displayText = "$($junction.SourcePath)"
        $checkedList.Items.Add($displayText, $true)
    }
    $restoreForm.Controls.Add($checkedList)
    
    # Progress bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10,305)
    $progressBar.Size = New-Object System.Drawing.Size(570,20)
    $progressBar.Visible = $false
    $restoreForm.Controls.Add($progressBar)
    
    # Progress label
    $progressLabel = New-Object System.Windows.Forms.Label
    $progressLabel.Location = New-Object System.Drawing.Point(10,330)
    $progressLabel.Size = New-Object System.Drawing.Size(570,20)
    $progressLabel.Text = ""
    $progressLabel.Visible = $false
    $restoreForm.Controls.Add($progressLabel)
    
    # Restore button
    $btnRestore = New-Object System.Windows.Forms.Button
    $btnRestore.Location = New-Object System.Drawing.Point(400,365)
    $btnRestore.Size = New-Object System.Drawing.Size(80,25)
    $btnRestore.Text = "Restore"
    $btnRestore.UseVisualStyleBackColor = $true
    $btnRestore.Add_Click({
        $selectedCount = 0
        for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
            if ($checkedList.GetItemChecked($i)) { $selectedCount++ }
        }
        
        if ($selectedCount -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select at least one junction to restore.","No Selection","OK","Warning")
            return
        }
        
        # Show progress controls
        $progressBar.Visible = $true
        $progressLabel.Visible = $true
        $progressBar.Maximum = $selectedCount
        $progressBar.Value = 0
          # Disable buttons during operation
        $btnRestore.Enabled = $false
        $btnCancel.Enabled = $false
        
        $restored = 0
        $errors = 0
        $current = 0
        
        for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
            if ($checkedList.GetItemChecked($i)) {
                $current++
                $junction = $config.Junctions[$i]
                $sourcePath = $junction.SourcePath
                $targetRelPath = $junction.TargetRelativePath
                
                # Update progress
                $progressBar.Value = $current
                $progressLabel.Text = "Processing: $sourcePath ($current of $selectedCount)"
                $restoreForm.Refresh()
                
                try {
                    # Mirror engine: copy this folder back from OneDrive to its original path (copy-only, never deletes)
                    if (Restore-PairFromCloud -SourcePath $sourcePath -TargetRelativePath $targetRelPath) {
                        $restored++
                    } else {
                        $errors++
                    }
                } catch {
                    $errors++
                }
            }
        }
        
        # Hide progress controls
        $progressBar.Visible = $false
        $progressLabel.Visible = $false
        
        # Re-enable buttons
        $btnRestore.Enabled = $true
        $btnCancel.Enabled = $true
        
        $message = "Restore complete!"
        if ($restored -gt 0) { $message += "`n[OK] Restored: $restored folders" }
        if ($errors -gt 0) { $message += "`n[ERROR] Errors: $errors" }
        
        [System.Windows.Forms.MessageBox]::Show($message,"Restore Complete","OK","Information")
        $restoreForm.Close()
    })
    $restoreForm.Controls.Add($btnRestore)
    
    # Cancel button
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point(490,365)
    $btnCancel.Size = New-Object System.Drawing.Size(80,25)
    $btnCancel.Text = "Cancel"
    $btnCancel.UseVisualStyleBackColor = $true
    $btnCancel.Add_Click({ $restoreForm.Close() })
    $restoreForm.Controls.Add($btnCancel)
    
    [void]$restoreForm.ShowDialog()
}

# Auto-restore (post-format recovery). SMART: a pair is restored ONLY when its original
# source path is MISSING or EMPTY - the true post-format signal. On a normal login (sources
# already present with data) nothing happens - a complete no-op. Only when at least one
# restore actually runs do we also recreate the continuous-sync task (absent on a fresh install).
if ($AutoRestore) {
    $config = Get-JunctionConfig
    if ($config.Junctions.Count -gt 0) {
        $restored = 0
        foreach ($j in $config.Junctions) {
            # Per-pair auto-restore opt-in (default true for legacy entries without the field).
            $doAuto = $true
            if ($j.PSObject.Properties.Name -contains 'AutoRestore') { $doAuto = (ConvertTo-Bool $j.AutoRestore) }
            if (-not $doAuto) { continue }
            $src = $j.SourcePath
            $needsRestore = $false
            if (-not (Test-Path $src)) {
                $needsRestore = $true
            } else {
                try {
                    if ((Get-ChildItem $src -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) { $needsRestore = $true }
                } catch { }
            }
            if ($needsRestore) {
                Restore-PairFromCloud -SourcePath $src -TargetRelativePath $j.TargetRelativePath | Out-Null
                $restored++
            }
        }
        # Recreate the continuous-sync task only if we actually restored something (post-format).
        if ($restored -gt 0) { Set-SyncTask -Enable $true }
    }
    exit
}

# If invoked for periodic background sync, mirror ALL folder pairs to OneDrive and exit.
# This is the continuous-sync engine: a Windows Scheduled Task calls the (already relocated,
# already elevated) script with -Sync every few minutes, so new/changed files reach OneDrive
# automatically while you keep working. Copy-only (never deletes).
if ($Sync) {
    Sync-AllPairs | Out-Null
    exit
}

# Invoked by the right-click "Sync folder" menu (folder passed via %V as -Link).
# Admin-free by design: NO elevation, NO Set-SyncTask => no UAC on every right-click.
# Destination is the script's own folder (home); nothing hardcoded - works for any user.
if ($Link) {
    Add-Type -AssemblyName System.Windows.Forms
    try {
        $folder = $Link.Trim('"').Trim("'").Trim()
        if (-not (Test-Path $folder -PathType Container)) {
            [System.Windows.Forms.MessageBox]::Show("Not a valid folder:`n$folder","LRGEX Sync","OK","Warning") | Out-Null
            exit
        }
        $leaf = Split-Path $folder -Leaf
        $ar = ([System.Windows.Forms.MessageBox]::Show("Enable AUTO-RESTORE for '$leaf' after a PC format?`n`nYes = this folder is put back automatically after a format.`nNo = restore it manually.","Auto-restore for this folder?","YesNo","Question") -eq [System.Windows.Forms.DialogResult]::Yes)
        Save-JunctionConfig -sourcePath $folder -autoRestore $ar
        $ok = Sync-PairToCloud -SourcePath $folder
        $arText = if ($ar) { "auto-restore ON" } else { "auto-restore OFF" }
        if ($ok) {
            [System.Windows.Forms.MessageBox]::Show("Linked and mirrored into your sync home:`n$leaf ($arText)`nNew files will sync automatically.","LRGEX Sync","OK","Information") | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("Registered, but the first mirror had issues (background sync will retry).`n$leaf ($arText)","LRGEX Sync","OK","Warning") | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed: $_","LRGEX Sync","OK","Error") | Out-Null
    }
    exit
}

# Create Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "LRGEX Folder Sync"
$form.Size = New-Object System.Drawing.Size(520,545)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.WindowState = 'Normal'

# Set web-based icon and add logo panel
Set-FormIcon -Form $form
Add-LogoPanel -Form $form



# Create custom renderer class to override default menu styling
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class DarkMenuRenderer : ToolStripProfessionalRenderer
{
    public DarkMenuRenderer() : base(new DarkMenuColorTable()) { }
    
    protected override void OnRenderMenuItemText(ToolStripItemTextRenderEventArgs e)
    {
        // Keep Tools button text dark when pressed/selected
        if (e.Item.Owner is MenuStrip && e.Item.Text == "Tools")
        {
            e.TextColor = Color.FromArgb(45, 45, 45); // Dark text for main menu
        }
        else
        {
            e.TextColor = Color.White; // White text for dropdown items
        }
        base.OnRenderMenuItemText(e);
    }
}

public class DarkMenuColorTable : ProfessionalColorTable
{
    public override Color MenuItemSelected
    {
        get { return Color.FromArgb(65, 65, 65); }
    }
    
    public override Color MenuItemSelectedGradientBegin
    {
        get { return Color.FromArgb(65, 65, 65); }
    }
    
    public override Color MenuItemSelectedGradientEnd
    {
        get { return Color.FromArgb(65, 65, 65); }
    }
    
    public override Color MenuItemPressedGradientBegin
    {
        get { return Color.FromArgb(85, 85, 85); }
    }
    
    public override Color MenuItemPressedGradientEnd
    {
        get { return Color.FromArgb(85, 85, 85); }
    }
    
    public override Color MenuItemPressed
    {
        get { return Color.FromArgb(85, 85, 85); }
    }
    
    public override Color MenuItemBorder
    {
        get { return Color.FromArgb(45, 45, 45); }
    }
    
    public override Color MenuBorder
    {
        get { return Color.FromArgb(45, 45, 45); }
    }
    
    public override Color ToolStripDropDownBackground
    {
        get { return Color.FromArgb(45, 45, 45); }
    }
    
    public override Color ImageMarginGradientBegin
    {
        get { return Color.FromArgb(45, 45, 45); }
    }
    
    public override Color ImageMarginGradientEnd
    {
        get { return Color.FromArgb(45, 45, 45); }
    }
    
    public override Color ImageMarginGradientMiddle
    {
        get { return Color.FromArgb(45, 45, 45); }
    }
}
"@

# Create menu strip with custom dark renderer
$menuStrip = New-Object System.Windows.Forms.MenuStrip
$menuStrip.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$menuStrip.ForeColor = [System.Drawing.Color]::FromArgb(64, 64, 64)
$menuStrip.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$menuStrip.Renderer = New-Object DarkMenuRenderer

# Tools menu with enhanced styling
$toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$toolsMenu.Text = "Tools"
$toolsMenu.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)  # Match menu strip background
$toolsMenu.ForeColor = [System.Drawing.Color]::FromArgb(45, 45, 45)  # Dark text to match the form theme
$toolsMenu.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$healthCheckItem = New-Object System.Windows.Forms.ToolStripMenuItem
$healthCheckItem.Text = "Junction Health Check"
$healthCheckItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$healthCheckItem.ForeColor = [System.Drawing.Color]::White
$healthCheckItem.Add_Click({ Test-JunctionHealth })

$removeItem = New-Object System.Windows.Forms.ToolStripMenuItem
$removeItem.Text = "Remove Junctions"
$removeItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$removeItem.ForeColor = [System.Drawing.Color]::White
$removeItem.Add_Click({ Remove-JunctionDialog })

$exportItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exportItem.Text = "Export Configuration"
$exportItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$exportItem.ForeColor = [System.Drawing.Color]::White
$exportItem.Add_Click({ Export-JunctionConfig })

$importItem = New-Object System.Windows.Forms.ToolStripMenuItem
$importItem.Text = "Import Configuration"
$importItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$importItem.ForeColor = [System.Drawing.Color]::White
$importItem.Add_Click({ Import-JunctionConfig })

# (Auto-Restore-on-Login menu removed - auto-restore is now absence-driven, inside the sync cycle.)

# Right-click sync: a single STATE-AWARE toggle. Label + action reflect whether it's on,
# and the label refreshes every time the Tools menu opens (always shows live state).
function Test-RightClickMenuEnabled {
    [bool](Test-Path 'HKCU:\Software\Classes\Directory\shell\LRGEXSync')
}
function Update-RightClickMenuLabel {
    if (Test-RightClickMenuEnabled) { $rcMenu.Text = "Right-Click Sync: ON   (click to disable)" }
    else { $rcMenu.Text = "Right-Click Sync: OFF   (click to enable)" }
}

$rcMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$rcMenu.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$rcMenu.ForeColor = [System.Drawing.Color]::White
$rcMenu.Add_Click({
    # Toggle based on the CURRENT state, then refresh the label.
    if (Test-RightClickMenuEnabled) { Set-RightClickMenu -Enable $false }
    else { Set-RightClickMenu -Enable $true }
    Update-RightClickMenuLabel
})
Update-RightClickMenuLabel   # initial label from current state
# Keep the label fresh whenever the Tools menu is opened.
$toolsMenu.Add_DropDownOpening({ Update-RightClickMenuLabel })

$logItem = New-Object System.Windows.Forms.ToolStripMenuItem
$logItem.Text = "View Sync Log"
$logItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$logItem.ForeColor = [System.Drawing.Color]::White
$logItem.Add_Click({ Show-SyncLog })

$intervalItem = New-Object System.Windows.Forms.ToolStripMenuItem
$intervalItem.Text = "Set Sync Interval..."
$intervalItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$intervalItem.ForeColor = [System.Drawing.Color]::White
$intervalItem.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $cfg = Get-JunctionConfig
    $cur = if ($cfg.PSObject.Properties.Name -contains 'SyncIntervalMinutes') { [int]$cfg.SyncIntervalMinutes } else { 5 }
    $val = [Microsoft.VisualBasic.Interaction]::InputBox("Enter sync interval in MINUTES.`n(e.g. 5 = every 5 min,  120 = every 2 hours)", "Sync Interval", "$cur")
    if (-not $val) { return }
    $mins = 0
    if (-not ([int]::TryParse($val, [ref]$mins) -and $mins -ge 1)) {
        [System.Windows.Forms.MessageBox]::Show("Enter a whole number of minutes (1 or more).","Invalid","OK","Warning") | Out-Null; return
    }
    if ($cfg.PSObject.Properties.Name -contains 'SyncIntervalMinutes') { $cfg.SyncIntervalMinutes = $mins }
    else { $cfg | Add-Member -NotePropertyName SyncIntervalMinutes -NotePropertyValue $mins -Force }
    $configPath = Get-ConfigPath
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
    Set-SyncTask -Enable $true -IntervalMinutes $mins
    [System.Windows.Forms.MessageBox]::Show("Sync interval set to $mins minute(s). Background task updated.","Sync Interval","OK","Information") | Out-Null
})

$toolsMenu.DropDownItems.Add($healthCheckItem)
$toolsMenu.DropDownItems.Add($removeItem)
$toolsMenu.DropDownItems.Add("-")
$toolsMenu.DropDownItems.Add($exportItem)
$toolsMenu.DropDownItems.Add($importItem)
$toolsMenu.DropDownItems.Add("-")
$toolsMenu.DropDownItems.Add($rcMenu)
$toolsMenu.DropDownItems.Add("-")
$toolsMenu.DropDownItems.Add($logItem)
$toolsMenu.DropDownItems.Add($intervalItem)

$exclItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exclItem.Text = "Manage Exclusions..."
$exclItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$exclItem.ForeColor = [System.Drawing.Color]::White
$exclItem.Add_Click({ Show-Exclusions })
$toolsMenu.DropDownItems.Add($exclItem)

$menuStrip.Items.Add($toolsMenu)
$form.Controls.Add($menuStrip)
$form.MainMenuStrip = $menuStrip

# Label and TextBox for Source Folder
$labelSource = New-Object System.Windows.Forms.Label
$labelSource.Location = New-Object System.Drawing.Point(10,100)
$labelSource.Size = New-Object System.Drawing.Size(450,20)
$labelSource.Text = "Select folder to sync (Source folder):"
$form.Controls.Add($labelSource)

$textSource = New-Object System.Windows.Forms.TextBox
$textSource.Location = New-Object System.Drawing.Point(10,125)
$textSource.Size = New-Object System.Drawing.Size(350,22)
$form.Controls.Add($textSource)

$btnBrowseSource = New-Object System.Windows.Forms.Button
$btnBrowseSource.Location = New-Object System.Drawing.Point(370,123)
$btnBrowseSource.Size = New-Object System.Drawing.Size(90,25)
$btnBrowseSource.Text = "Browse..."
$form.Controls.Add($btnBrowseSource)

# Synced folders list (the root folders you linked) + per-folder auto-restore toggle + remove.
$labelFolders = New-Object System.Windows.Forms.Label
$labelFolders.Location = New-Object System.Drawing.Point(10,165)
$labelFolders.Size = New-Object System.Drawing.Size(490,20)
$labelFolders.Text = "Synced folders (select one, then Toggle auto-restore or Remove):"
$form.Controls.Add($labelFolders)

$folderList = New-Object System.Windows.Forms.ListView
$folderList.Location = New-Object System.Drawing.Point(10,190)
$folderList.Size = New-Object System.Drawing.Size(490,110)
$folderList.View = 'Details'
$folderList.FullRowSelect = $true
$folderList.MultiSelect = $false
$folderList.Columns.Add('Folder', 350) | Out-Null
$folderList.Columns.Add('Auto-Restore', 120) | Out-Null
$form.Controls.Add($folderList)
$folderList.Add_SelectedIndexChanged({
    if ($folderList.SelectedItems.Count -gt 0) {
        $idx = $folderList.SelectedItems[0].Index
        $cfgF = Get-JunctionConfig
        $pairsF = @($cfgF.Junctions)
        if ($idx -lt $pairsF.Count) { $textSource.Text = $pairsF[$idx].SourcePath }
    }
})

function Update-FolderList {
    $folderList.BeginUpdate()
    $folderList.Items.Clear()
    $cfg = Get-JunctionConfig
    if ($cfg.Junctions) {
        foreach ($j in $cfg.Junctions) {
            $leaf = Split-Path $j.SourcePath -Leaf
            $ar = if ($j.PSObject.Properties.Name -contains 'AutoRestore') { (ConvertTo-Bool $j.AutoRestore) } else { $true }
            $row = New-Object System.Windows.Forms.ListViewItem($leaf)
            $row.SubItems.Add($(if ($ar) { 'ON' } else { 'OFF' })) | Out-Null
            $folderList.Items.Add($row) | Out-Null
        }
    }
    $folderList.EndUpdate()
}
Update-FolderList

$btnToggle = New-Object System.Windows.Forms.Button
$btnToggle.Location = New-Object System.Drawing.Point(250,305)
$btnToggle.Size = New-Object System.Drawing.Size(150,26)
$btnToggle.Text = "Toggle Auto-Restore"
$btnToggle.Add_Click({
    if ($folderList.SelectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Select a folder first.","LRGEX","OK","Warning") | Out-Null; return }
    $idx = $folderList.SelectedItems[0].Index
    $cfg = Get-JunctionConfig
    $pairs = @($cfg.Junctions)
    if ($idx -ge $pairs.Count) { return }
    $cur = if ($pairs[$idx].PSObject.Properties.Name -contains 'AutoRestore') { (ConvertTo-Bool $pairs[$idx].AutoRestore) } else { $true }
    $newVal = -not $cur
    if ($pairs[$idx].PSObject.Properties.Name -contains 'AutoRestore') { $pairs[$idx].AutoRestore = $newVal }
    else { $pairs[$idx] | Add-Member -NotePropertyName 'AutoRestore' -NotePropertyValue $newVal -Force }
    $cfg.Junctions = $pairs
    $cfg | ConvertTo-Json -Depth 5 | Set-Content (Get-ConfigPath) -Encoding UTF8
    Update-FolderList
})
$form.Controls.Add($btnToggle)

$btnRemoveFolder = New-Object System.Windows.Forms.Button
$btnRemoveFolder.Location = New-Object System.Drawing.Point(410,305)
$btnRemoveFolder.Size = New-Object System.Drawing.Size(90,26)
$btnRemoveFolder.Text = "Remove"
$btnRemoveFolder.Add_Click({
    if ($folderList.SelectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Select a folder first.","LRGEX","OK","Warning") | Out-Null; return }
    $idx = $folderList.SelectedItems[0].Index
    $cfg = Get-JunctionConfig
    $pairs = @($cfg.Junctions)
    if ($idx -ge $pairs.Count) { return }
    $leaf = Split-Path $pairs[$idx].SourcePath -Leaf
    if ([System.Windows.Forms.MessageBox]::Show("Remove '$leaf' from the sync list?`n(The backup copy in your home folder is NOT deleted.)","Remove","YesNo","Question") -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $kept = @()
    for ($k = 0; $k -lt $pairs.Count; $k++) { if ($k -ne $idx) { $kept += $pairs[$k] } }
    $cfg.Junctions = $kept
    $cfg | ConvertTo-Json -Depth 5 | Set-Content (Get-ConfigPath) -Encoding UTF8
    Update-FolderList
})
$form.Controls.Add($btnRemoveFolder)

# Status label for messages
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10,335)
$statusLabel.Size = New-Object System.Drawing.Size(490,45)
$statusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
$statusLabel.AutoSize = $false
$statusLabel.BorderStyle = 'Fixed3D'
$form.Controls.Add($statusLabel)

# Button to Create Junction
$btnCreate = New-Object System.Windows.Forms.Button
$btnCreate.Location = New-Object System.Drawing.Point(120,388)
$btnCreate.Size = New-Object System.Drawing.Size(120,35)
$btnCreate.Text = "Link Folder"
$btnCreate.UseVisualStyleBackColor = $true
$form.Controls.Add($btnCreate)

# Button to Restore Junctions
$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Location = New-Object System.Drawing.Point(250,388)
$btnRestore.Size = New-Object System.Drawing.Size(120,35)
$btnRestore.Text = "Restore Saved"
$btnRestore.UseVisualStyleBackColor = $true
$form.Controls.Add($btnRestore)

# Scheduling status label
# (Auto-Restore-on-Login status label removed - see the health lamp / sync log.)

# (Info label removed - the health lamp + folder list convey status.)

# Browse Source folder
$btnBrowseSource.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select folder to sync (Source folder)"
    $cur = $textSource.Text.Trim('"').Trim("'").Trim()
    if ($cur -and (Test-Path $cur -PathType Container)) { $folderBrowser.SelectedPath = $cur }
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textSource.Text = $folderBrowser.SelectedPath
    }
})

# (Target picker removed - the home folder you picked is the single destination.)

# Create Junction Button Click Handler
$btnCreate.Add_Click({
    $sourcePath = $textSource.Text.Trim()
    $sourcePath = $sourcePath.Trim('"').Trim("'").Trim()

    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        $statusLabel.Text = "[ERROR] Please enter a source folder path."
        return
    }
    if (-not (Test-Path -Path $sourcePath -PathType Container)) {
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        $statusLabel.Text = "[ERROR] Source folder does not exist:`n'$sourcePath'"
        return
    }

    $leaf = Split-Path $sourcePath -Leaf

    # Already linked? -> just re-sync it, no auto-restore re-prompt.
    $cfg = Get-JunctionConfig
    if (@($cfg.Junctions | Where-Object { $_.SourcePath -eq $sourcePath }).Count -gt 0) {
        try {
            if (Sync-PairToCloud -SourcePath $sourcePath) {
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
                $statusLabel.Text = "[OK] '$leaf' is already linked - re-synced now."
            } else {
                $statusLabel.ForeColor = [System.Drawing.Color]::Red
                $statusLabel.Text = "[ERROR] Re-sync failed for '$leaf' (background sync will retry)."
            }
        } catch {
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            $statusLabel.Text = "[ERROR] $_"
        }
        return
    }

    # New folder -> ask auto-restore, then link.
    $cloudDest = Get-PairCloudPath -SourcePath $sourcePath
    $ar = ([System.Windows.Forms.MessageBox]::Show("Enable AUTO-RESTORE for '$leaf' after a PC format?`n`nYes = restored automatically after a format.`nNo = restore it manually.","Auto-restore for this folder?","YesNo","Question") -eq [System.Windows.Forms.DialogResult]::Yes)
    $arText = if ($ar) { "auto-restore ON" } else { "auto-restore OFF" }
    try {
        Save-JunctionConfig -sourcePath $sourcePath -autoRestore $ar
        Update-FolderList   # refresh the folder list
        if (Sync-PairToCloud -SourcePath $sourcePath) {
            Set-SyncTask -Enable $true
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
            $statusLabel.Text = "[OK] Folder linked and mirrored into your sync home:`n$cloudDest  <=  $sourcePath`n$arText. New files sync automatically every few minutes."
        } else {
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            $statusLabel.Text = "[ERROR] Folder registered but the first mirror failed:`n$sourcePath`nThe background sync will retry automatically."
        }
    } catch {
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        $statusLabel.Text = "[ERROR] Failed to link folder:`n$_"
    }
})

# Restore Button Click Handler
$btnRestore.Add_Click({
    Show-RestoreDialog
})

# --- Health lamp: live status of the continuous sync task (so you're never blind) ---
$healthLamp = New-Object System.Windows.Forms.Label
$healthLamp.Location = New-Object System.Drawing.Point(10,432)
$healthLamp.Size = New-Object System.Drawing.Size(490,26)
$healthLamp.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$healthLamp.TextAlign = 'MiddleLeft'
$healthLamp.BorderStyle = 'Fixed3D'
$form.Controls.Add($healthLamp)
function Update-HealthLamp {
    $h = Get-SyncHealth
    $healthLamp.Text = " $($h.Label)  -  $($h.Reason)"
    switch ($h.Status) {
        'GREEN' { $healthLamp.BackColor = [System.Drawing.Color]::FromArgb(0,160,0);   $healthLamp.ForeColor = [System.Drawing.Color]::White }
        'AMBER' { $healthLamp.BackColor = [System.Drawing.Color]::FromArgb(200,140,0); $healthLamp.ForeColor = [System.Drawing.Color]::White }
        default { $healthLamp.BackColor = [System.Drawing.Color]::FromArgb(200,30,30);  $healthLamp.ForeColor = [System.Drawing.Color]::White }
    }
}
$healthTimer = New-Object System.Windows.Forms.Timer
$healthTimer.Interval = 30000
$healthTimer.Add_Tick({ Update-HealthLamp })
Update-HealthLamp
$healthTimer.Start()

# Show the form
$form.Add_Shown({ Update-FolderList; $form.Activate() })
[void]$form.ShowDialog()
