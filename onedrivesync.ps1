# OneDrive Folder Sync via Junction Tool
# Automatically backed up in OneDrive for PC formatting protection
# Features: Create junctions, save configurations, restore after PC format

param(
    [switch]$AutoRestore
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

# Get raw OneDrive path - we want Documents folder, not OneDrive root!
function Get-OneDrivePathRaw {
    # Try environment variable first
    $od = $Env:OneDrive
    if ([string]::IsNullOrEmpty($od)) {
        # Fallback to registry
        try {
            $regPath = "HKCU:\Software\Microsoft\OneDrive"
            $od = (Get-ItemProperty -Path $regPath -ErrorAction Stop).UserFolder
        } catch {
            # If OneDrive is not installed, use local Documents folder
            $od = [Environment]::GetFolderPath("MyDocuments")
        }
    }
    
    # We want to use Documents subfolder for LRGEX-saves, not OneDrive root
    return Join-Path $od "Documents"
}

# Self-copy to LRGEX-saves and relaunch if not already there
function Test-AndRelocateScript {
    # Get current script path - handle different execution contexts
    $currentPath = $null
    
    # Method 1: Try $PSCommandPath (works when script is executed as file)
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $currentPath = $PSCommandPath
    }
    # Method 2: Try $MyInvocation.MyCommand.Path
    elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
        $currentPath = $MyInvocation.MyCommand.Path
    }
    # Method 3: Try call stack
    else {
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
    
    # Method 4: Fallback - search for the script in common locations
    if ([string]::IsNullOrEmpty($currentPath) -or !(Test-Path $currentPath)) {
        $scriptName = "onedrivesync.ps1"
        $searchPaths = @(
            "c:\Users\lrg4you\Desktop\LRGEX-saves\$scriptName",
            "c:\Users\lrg4you\OneDrive\Documents\LRGEX-saves\$scriptName",
            (Join-Path $pwd $scriptName),
            (Join-Path ([Environment]::GetFolderPath("Desktop")) "LRGEX-saves\$scriptName")
        )
        
        foreach ($path in $searchPaths) {
            if (Test-Path $path) {
                $currentPath = $path
                break
            }
        }
    }
    
    # If we still can't get the path, skip relocation
    if ([string]::IsNullOrEmpty($currentPath) -or !(Test-Path $currentPath)) {
        Write-Host "Could not determine current script path, skipping relocation" -ForegroundColor Yellow
        return
    }    
    $documentsPath = Get-OneDrivePathRaw  # Get Documents path (OneDrive\Documents)
    $targetFolder = Join-Path $documentsPath "LRGEX-saves"
    $targetPath = Join-Path $targetFolder "onedrivesync.ps1"
    
    # Check if we're already running from the target location
    if ($currentPath -ne $targetPath) {
        try {
            # Create LRGEX-saves folder if it doesn't exist
            if (-not (Test-Path $targetFolder)) {
                New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
            }
            
            # Copy script to target location
            Copy-Item -Path $currentPath -Destination $targetPath -Force
            
            # Unblock the copied file to avoid security warnings
            try {
                Unblock-File -Path $targetPath -ErrorAction SilentlyContinue
            } catch { }            # Verify copy was successful
            if (Test-Path $targetPath) {
                # Relaunch from new location with same parameters
                $arguments = @("-ExecutionPolicy", "Bypass", "-File", "`"$targetPath`"")
                if ($AutoRestore) { $arguments += "-AutoRestore" }
                
                # Check if we're already running as admin
                $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                
                try {
                    if ($isAdmin) {
                        # Already admin, start new PowerShell process normally
                        $process = Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru
                    } else {
                        # Not admin, request elevation
                        $process = Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
                    }
                    
                    # Wait a moment to ensure the new process starts
                    Start-Sleep -Milliseconds 500
                    
                    # Exit this instance
                    exit
                } catch {
                    # If Start-Process fails, try the fallback method
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = "PowerShell.exe"
                    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$targetPath`"" + $(if ($AutoRestore) { " -AutoRestore" })
                    
                    if ($isAdmin) {
                        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                        $psi.CreateNoWindow = $true
                    } else {
                        $psi.Verb = "runas"
                        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                        $psi.CreateNoWindow = $true
                    }
                    
                    [System.Diagnostics.Process]::Start($psi) | Out-Null
                    exit
                }
            }
        } catch {
            # If copy fails, continue with current location
        }
    }
}

# Call self-relocation check BEFORE admin check
Test-AndRelocateScript

# Check if running as administrator, if not, restart as admin
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
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
                $scriptName = "onedrivesync.ps1"
                $searchPaths = @(
                    "c:\Users\lrg4you\Desktop\LRGEX-saves\$scriptName",
                    "c:\Users\lrg4you\OneDrive\Documents\LRGEX-saves\$scriptName",
                    (Join-Path $pwd $scriptName),
                    (Join-Path ([Environment]::GetFolderPath("Desktop")) "LRGEX-saves\$scriptName")
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

function Get-WebAsset {
    param(
        [string]$Url,
        [string]$LocalFileName,
        [int]$MaxAgeHours = 24
    )
      try {
        $oneDriveRoot = Get-OneDrivePath
        $cacheDir = Join-Path $oneDriveRoot "LRGEX-saves\.cache"
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
            $webClient.Headers.Add("User-Agent", "LRGEX OneDrive Junction Sync Tool")
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
        $Form.Size = New-Object System.Drawing.Size(520, 480)
        
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
            $logoLabel.Location = New-Object System.Drawing.Point(140, 15)
            $logoLabel.Size = New-Object System.Drawing.Size(340, 30)
            $logoLabel.Text = "OneDrive Junction Sync Tool"
            $logoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
            $logoLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
            $logoPanel.Controls.Add($logoLabel)
        } else {            # Fallback text-only logo if web download fails
            $logoLabel = New-Object System.Windows.Forms.Label
            $logoLabel.Location = New-Object System.Drawing.Point(10, 10)
            $logoLabel.Size = New-Object System.Drawing.Size(470, 40)
            $logoLabel.Text = "LRGEX OneDrive Junction Sync Tool"
            $logoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
            $logoLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
            $logoLabel.TextAlign = 'MiddleCenter'
            $logoPanel.Controls.Add($logoLabel)}
        
    } catch {
        # If logo panel creation fails, continue without it
    }
}

function Get-OneDrivePath {
    # Return Documents path where LRGEX-saves should be located
    return Get-OneDrivePathRaw
}

function Get-ConfigPath {
    $oneDriveRoot = Get-OneDrivePath
    return Join-Path $oneDriveRoot "LRGEX-saves\junction-config.json"
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

# If auto-restore is requested, run silently and exit
if ($AutoRestore) {
    $config = Get-JunctionConfig
    if ($config.Junctions.Count -gt 0) {
        # Smart check: Only restore if junctions are actually missing or broken
        $needsRestore = $false
        $oneDriveRoot = Get-OneDrivePath
          foreach ($junction in $config.Junctions) {
            $sourcePath = $junction.SourcePath
            $targetRelPath = $junction.TargetRelativePath
            $fullTargetFolder = Join-Path $oneDriveRoot $targetRelPath
            $linkName = Split-Path -Path $sourcePath -Leaf
            $junctionPath = Join-Path $fullTargetFolder $linkName
            
            # Check if junction is missing or broken
            if (-not (Test-Path $junctionPath)) {
                $needsRestore = $true
                break
            }            # Check if junction points to wrong location
            try {
                $dirInfo = Get-Item $junctionPath -Force
                if ($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $fsutil = cmd /c "fsutil reparsepoint query `"$junctionPath`"" 2>$null
                    # Ensure fsutil output exists and is not null/empty before regex matching
                    if ($fsutil -and ($fsutil | Out-String).Trim() -ne "") {
                        $fsutilText = $fsutil | Out-String
                        if ($fsutilText -match "Print Name:\s*(.+)") {
                            $existingTarget = $matches[1].Trim()
                            if ($existingTarget -ne $sourcePath) {
                                $needsRestore = $true
                                break
                            }
                        } else {
                            $needsRestore = $true
                            break
                        }
                    } else {
                        $needsRestore = $true
                        break
                    }
                } else {
                    # Path exists but is not a junction
                    $needsRestore = $true
                    break
                }
            } catch {
                $needsRestore = $true
                break
            }
        }
          # Only restore if actually needed
        if ($needsRestore) {
            foreach ($junction in $config.Junctions) {
                try {
                    $sourcePath = $junction.SourcePath
                    $targetRelPath = $junction.TargetRelativePath
                    
                    # Create source folder if it doesn't exist
                    if (-not (Test-Path $sourcePath)) {
                        New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
                    }
                    
                    # Create target folder in OneDrive if needed
                    $fullTargetFolder = Join-Path $oneDriveRoot $targetRelPath
                    if (-not (Test-Path $fullTargetFolder)) {
                        New-Item -Path $fullTargetFolder -ItemType Directory -Force | Out-Null
                    }
                    
                    # Create junction
                    $linkName = Split-Path -Path $sourcePath -Leaf
                    $junctionPath = Join-Path $fullTargetFolder $linkName                    # Only create if it doesn't exist or is invalid
                    $needsCreation = $true
                    if (Test-Path $junctionPath) {
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
                                            $needsCreation = $false
                                        }
                                    }
                                }
                            }
                        } catch { }
                    }
                    
                    if ($needsCreation) {
                        if (Test-Path $junctionPath) {
                            Remove-Item $junctionPath -Force -Recurse -ErrorAction SilentlyContinue
                        }
                        cmd /c "mklink /J `"$junctionPath`" `"$sourcePath`"" 2>$null | Out-Null
                    }
                } catch { }
            }
        }
        # If no restore was needed, exit silently without doing anything
    }
    exit
}

function Save-JunctionConfig {
    param($sourcePath, $targetRelPath)
    
    $configPath = Get-ConfigPath
    $config = Get-JunctionConfig
    
    # Add new junction to config (avoid duplicates)
    $newJunction = @{
        SourcePath = $sourcePath
        TargetRelativePath = $targetRelPath
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
        $targetRelPath = $junction.TargetRelativePath
        $oneDriveRoot = Get-OneDrivePath
        $fullTargetFolder = Join-Path $oneDriveRoot $targetRelPath
        $linkName = Split-Path -Path $sourcePath -Leaf
        $junctionPath = Join-Path $fullTargetFolder $linkName
        
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
      $taskName = "OneDriveJunctionRestore"
    
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
        
        # Fallback search for LRGEX-saves location
        if ([string]::IsNullOrEmpty($scriptPath)) {
            $documentsPath = Get-OneDrivePathRaw
            $lrgexPath = Join-Path $documentsPath "LRGEX-saves\onedrivesync.ps1"
            if (Test-Path $lrgexPath) {
                $scriptPath = $lrgexPath
            }
        }
    }
      try {
        if ($Enable) {
            # Create scheduled task for startup with smart conditions
            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -File `"$scriptPath`" -AutoRestore"
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            
            # Smart settings: Don't run too frequently, allow battery operation
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Hours 1) -RestartCount 3
            
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            [System.Windows.Forms.MessageBox]::Show("Smart auto-restore enabled!`nSetting saved to JSON config (syncs via OneDrive).`nJunctions will only be restored when actually needed (missing/broken).","Auto-Restore Enabled","OK","Information")
        } else {
            # Remove scheduled task
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show("Auto-restore disabled successfully!`nSetting saved to JSON config (syncs via OneDrive).","Auto-Restore Disabled","OK","Information")
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to configure auto-restore:`n$_","Auto-Restore Error","OK","Error")
    }
}

function Test-AutoRestoreSettings {
    # Check JSON config first (primary source of truth)
    $config = Get-JunctionConfig
    return $config.AutoRestoreEnabled
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
        $displayText = "$($junction.SourcePath) → $($junction.TargetRelativePath)"
        $checkedList.Items.Add($displayText, $false)  # Default to unchecked for safety
    }
    $removeForm.Controls.Add($checkedList)
    
    # Warning label
    $warningLabel = New-Object System.Windows.Forms.Label
    $warningLabel.Location = New-Object System.Drawing.Point(10,305)
    $warningLabel.Size = New-Object System.Drawing.Size(570,40)
    $warningLabel.Text = "⚠️ WARNING: This will permanently delete the junction links. The original source folders will remain safe, but you'll need to recreate junctions if you want them back."
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
          $oneDriveRoot = Get-OneDrivePath
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
                    $fullTargetFolder = Join-Path $oneDriveRoot $targetRelPath
                    $linkName = Split-Path -Path $sourcePath -Leaf
                    $junctionPath = Join-Path $fullTargetFolder $linkName
                    
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
        $displayText = "$($junction.SourcePath) → $($junction.TargetRelativePath)"
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
        
        $oneDriveRoot = Get-OneDrivePath
        $restored = 0
        $skipped = 0
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
                    # Create source folder if it doesn't exist
                    if (-not (Test-Path $sourcePath)) {
                        New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
                    }
                      # Create target folder in OneDrive if needed
                    $fullTargetFolder = Join-Path $oneDriveRoot $targetRelPath
                    if (-not (Test-Path $fullTargetFolder)) {
                        New-Item -Path $fullTargetFolder -ItemType Directory -Force | Out-Null
                    }
                    
                    # Create junction
                    $linkName = Split-Path -Path $sourcePath -Leaf
                    $junctionPath = Join-Path $fullTargetFolder $linkName
                    
                    # Check if junction already exists and is valid
                    if (Test-Path $junctionPath) {
                        # Check if it's actually a junction pointing to the right place
                        $existingTarget = $null
                        try {
                            $dirInfo = Get-Item $junctionPath -Force                            if ($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                                # It's a junction/reparse point, check if it points to our source
                                $fsutil = cmd /c "fsutil reparsepoint query `"$junctionPath`"" 2>$null
                                # Ensure fsutil output exists and is not null/empty before regex matching
                                if ($fsutil -and ($fsutil | Out-String).Trim() -ne "") {
                                    $fsutilText = $fsutil | Out-String
                                    if ($fsutilText -match "Print Name:\s*(.+)") {
                                        $existingTarget = $matches[1].Trim()
                                    }
                                }
                            }
                        } catch {
                            # Error checking junction, treat as invalid
                        }
                        
                        if ($existingTarget -eq $sourcePath) {
                            # Junction already exists and points to correct location
                            $skipped++
                            continue
                        } else {
                            # Junction exists but points elsewhere - remove it first
                            try {
                                Remove-Item $junctionPath -Force -Recurse                            } catch {
                                $errors++
                                continue
                            }
                        }
                    }
                    
                    # Create new junction
                    $cmd = "cmd /c mklink /J `"$junctionPath`" `"$sourcePath`""
                    Invoke-Expression $cmd 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
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
        if ($restored -gt 0) { $message += "`n[OK] Created: $restored junctions" }
        if ($skipped -gt 0) { $message += "`n[SKIP] Skipped: $skipped (already exist)" }
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

# Create Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "LRGEX OneDrive Folder Sync"
$form.Size = New-Object System.Drawing.Size(520,480)
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

$schedulingMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$schedulingMenu.Text = "Auto-Restore"
$schedulingMenu.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$schedulingMenu.ForeColor = [System.Drawing.Color]::White

$enableSchedulingItem = New-Object System.Windows.Forms.ToolStripMenuItem
$enableSchedulingItem.Text = "Enable Auto-Restore on Login"
$enableSchedulingItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$enableSchedulingItem.ForeColor = [System.Drawing.Color]::White
$enableSchedulingItem.Add_Click({ Set-AutoRestoreSettings -Enable $true })

$disableSchedulingItem = New-Object System.Windows.Forms.ToolStripMenuItem
$disableSchedulingItem.Text = "Disable Auto-Restore on Login"
$disableSchedulingItem.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$disableSchedulingItem.ForeColor = [System.Drawing.Color]::White
$disableSchedulingItem.Add_Click({ Set-AutoRestoreSettings -Enable $false })

$schedulingMenu.DropDownItems.Add($enableSchedulingItem)
$schedulingMenu.DropDownItems.Add($disableSchedulingItem)

$toolsMenu.DropDownItems.Add($healthCheckItem)
$toolsMenu.DropDownItems.Add($removeItem)
$toolsMenu.DropDownItems.Add("-")
$toolsMenu.DropDownItems.Add($exportItem)
$toolsMenu.DropDownItems.Add($importItem)
$toolsMenu.DropDownItems.Add("-")
$toolsMenu.DropDownItems.Add($schedulingMenu)

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

# Label and TextBox for Target Folder (relative to OneDrive root)
$labelTarget = New-Object System.Windows.Forms.Label
$labelTarget.Location = New-Object System.Drawing.Point(10,165)
$labelTarget.Size = New-Object System.Drawing.Size(450,20)
$labelTarget.Text = "Select target folder inside OneDrive (relative path):"
$form.Controls.Add($labelTarget)

$textTarget = New-Object System.Windows.Forms.TextBox
$textTarget.Location = New-Object System.Drawing.Point(10,190)
$textTarget.Size = New-Object System.Drawing.Size(350,22)
# Pre-populate with LRGEX-saves as default
$textTarget.Text = "LRGEX-saves"
$form.Controls.Add($textTarget)

$btnBrowseTarget = New-Object System.Windows.Forms.Button
$btnBrowseTarget.Location = New-Object System.Drawing.Point(370,188)
$btnBrowseTarget.Size = New-Object System.Drawing.Size(90,25)
$btnBrowseTarget.Text = "Browse..."
$form.Controls.Add($btnBrowseTarget)

# Status label for messages
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10,230)
$statusLabel.Size = New-Object System.Drawing.Size(490,45)
$statusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
$statusLabel.AutoSize = $false
$statusLabel.BorderStyle = 'Fixed3D'
$form.Controls.Add($statusLabel)

# Button to Create Junction
$btnCreate = New-Object System.Windows.Forms.Button
$btnCreate.Location = New-Object System.Drawing.Point(120,295)
$btnCreate.Size = New-Object System.Drawing.Size(120,35)
$btnCreate.Text = "Create Junction"
$btnCreate.UseVisualStyleBackColor = $true
$form.Controls.Add($btnCreate)

# Button to Restore Junctions
$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Location = New-Object System.Drawing.Point(250,295)
$btnRestore.Size = New-Object System.Drawing.Size(120,35)
$btnRestore.Text = "Restore Saved"
$btnRestore.UseVisualStyleBackColor = $true
$form.Controls.Add($btnRestore)

# Scheduling status label
$schedulingStatus = New-Object System.Windows.Forms.Label
$schedulingStatus.Location = New-Object System.Drawing.Point(10,355)
$schedulingStatus.Size = New-Object System.Drawing.Size(490,20)
$schedulingStatus.ForeColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$schedulingStatus.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 8, [System.Drawing.FontStyle]::Italic)
if (Test-AutoRestoreSettings) {
    $schedulingStatus.Text = "[ENABLED] Auto-restore on login: ENABLED (smart detection)"
} else {
    $schedulingStatus.Text = "[DISABLED] Auto-restore on login: DISABLED"
}
$form.Controls.Add($schedulingStatus)

# Info label
$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Location = New-Object System.Drawing.Point(10,375)
$infoLabel.Size = New-Object System.Drawing.Size(490,60)
$infoLabel.Text = "Tip: All settings are saved in JSON config (syncs via OneDrive).`nAfter PC formatting, use 'Restore Saved' to recreate all junctions.`nUse Tools menu for health checks, removal, backup/restore configs, and auto-restore."
$infoLabel.ForeColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$form.Controls.Add($infoLabel)

# Get OneDrive root folder
$oneDriveRoot = Get-OneDrivePath

# Browse Source folder
$btnBrowseSource.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select folder to sync (Source folder)"
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textSource.Text = $folderBrowser.SelectedPath
    }
})

# Browse Target folder inside OneDrive
$btnBrowseTarget.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select target folder inside OneDrive (relative)"
    $folderBrowser.SelectedPath = $oneDriveRoot
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # Get relative path by removing OneDrive root prefix
        $sel = $folderBrowser.SelectedPath
        if ($sel.StartsWith($oneDriveRoot)) {
            $relativePath = $sel.Substring($oneDriveRoot.Length).TrimStart('\')
            $textTarget.Text = $relativePath
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please select a folder inside your OneDrive folder.","Invalid Selection","OK","Warning")
        }
    }
})

# Create Junction Button Click Handler
$btnCreate.Add_Click({
    $sourcePath = $textSource.Text.Trim()
    $targetRelPath = $textTarget.Text.Trim()

    # Remove quotes if present in the path and normalize
    $sourcePath = $sourcePath.Trim('"').Trim("'").Trim()
    
    # Debug: Show what path we're actually testing
    Write-Host "Testing path: '$sourcePath'"
    
    # Validate source path
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

    # Compose full target folder path inside OneDrive
    $fullTargetFolder = Join-Path $oneDriveRoot $targetRelPath

    # Ensure OneDrive folder exists
    if (-not (Test-Path -Path $oneDriveRoot -PathType Container)) {
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        $statusLabel.Text = "[ERROR] OneDrive folder not found. Is OneDrive installed and running?"
        return
    }

    # Create target folder if missing
    if (-not (Test-Path -Path $fullTargetFolder -PathType Container)) {
        try {
            New-Item -Path $fullTargetFolder -ItemType Directory -Force | Out-Null
        } catch {
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            $statusLabel.Text = "[ERROR] Failed to create target folder:`n$_"
            return
        }
    }

    # Junction link path inside target folder, named as source folder's leaf
    $linkName = Split-Path -Path $sourcePath -Leaf
    $junctionPath = Join-Path $fullTargetFolder $linkName

    # Check if junction already exists
    if (Test-Path -Path $junctionPath) {
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        $statusLabel.Text = "[ERROR] Junction already exists at:`n$junctionPath"
        return    }

    # Create junction via mklink /J
    try {
        # mklink requires cmd.exe to run
        $cmd = "cmd /c mklink /J `"$junctionPath`" `"$sourcePath`""
        Invoke-Expression $cmd | Out-Null
        $statusLabel.ForeColor = [System.Drawing.Color]::Green
        $statusLabel.Text = "[OK] Junction created successfully:`n$junctionPath -> $sourcePath"
        
        # Save junction configuration for future restore
        Save-JunctionConfig -sourcePath $sourcePath -targetRelPath $targetRelPath
    } catch {
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        $statusLabel.Text = "[ERROR] Failed to create junction:`n$_"
    }
})

# Restore Button Click Handler
$btnRestore.Add_Click({
    Show-RestoreDialog
})

# Show the form
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()
