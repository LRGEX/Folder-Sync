

<div align="center">
<img src="https://download.lrgex.com/Dark%20Full%20Logo.png" alt="LRGEX Logo" width="300">

# OneDrive Junction Sync Tool
</div>
## Overview

The LRGEX OneDrive Junction Sync Tool is a professional PowerShell application that creates NTFS junction points to sync local folders with OneDrive. This tool provides automatic backup protection for important directories by creating junction links that redirect folder contents to OneDrive while maintaining their original paths.

## Key Features

- **Professional Windows Forms GUI** with LRGEX branding and dark theme
- **NTFS Junction Management** - Create and manage folder junctions seamlessly
- **OneDrive Integration** - Automatically syncs junctioned folders to the cloud
- **Smart Auto-Restore** - Recreates junctions after PC formatting or fresh installs
- **Configuration Backup** - All settings saved in JSON format and synced via OneDrive
- **Junction Health Monitoring** - Built-in tools to verify junction integrity
- **UAC Privilege Management** - Automatic elevation when administrator rights are required
- **Web-Based Asset Loading** - Downloads logos and icons with intelligent caching

## How It Works

1. **Select Source Folder** - Choose any local folder you want to backup
2. **Choose Target Location** - Specify where in OneDrive to store the junction
3. **Create Junction** - The tool creates an NTFS junction point that redirects the folder contents
4. **Automatic Sync** - OneDrive automatically syncs the junctioned content to the cloud
5. **Easy Restore** - After PC formatting, use "Restore Saved" to recreate all junctions

## Use Cases

- **User Profile Folders** - Backup Documents, Desktop, Downloads automatically
- **Application Data** - Sync game saves, application settings, and user data
- **Development Projects** - Keep source code and project files backed up
- **Creative Assets** - Sync video projects, design files, and media libraries
- **System Configuration** - Backup important system configuration folders

## Installation & Usage

1. **Download** the `onedrivesync.ps1` script
2. **Run as Administrator** - The tool will automatically request elevation if needed
3. **First Launch** - The GUI will appear with LRGEX branding
4. **Create Junctions** - Use the interface to set up folder synchronization
5. **Enable Auto-Restore** - Configure automatic junction restoration via the Tools menu

## Technical Features

### Professional GUI Components
- Custom dark theme with LRGEX color standards (RGB 45,45,45)
- Web-based logo and icon loading with 24-hour cache refresh
- Professional menu system with custom C# renderer
- Real-time status updates and progress tracking
- Error handling with user-friendly dialog boxes

### Smart Junction Management
- Automatic source folder creation if missing
- Junction health monitoring and validation
- Bulk restore capabilities for multiple junctions
- Safe removal with confirmation dialogs
- Configuration import/export functionality

### Auto-Restore System
- Windows Task Scheduler integration
- Smart detection - only restores when junctions are actually missing
- JSON configuration sync via OneDrive
- Battery-friendly execution settings
- Silent background operation

## Configuration

All settings are stored in `junction-config.json` which includes:
- Junction definitions with source and target paths
- Auto-restore preferences
- Creation timestamps for tracking

This configuration file is automatically synced via OneDrive, ensuring your junction setup survives PC formatting and is available on multiple machines.

## Advanced Tools

Access via the **Tools** menu:
- **Junction Health Check** - Verify all junctions are working correctly
- **Remove Junctions** - Safely delete junction links while preserving source folders
- **Export/Import Configuration** - Backup and restore junction setups
- **Auto-Restore Settings** - Configure automatic junction restoration

## System Requirements

- Windows 10/11 with NTFS file system
- OneDrive installed and configured
- PowerShell 5.1 or later
- Administrator privileges (automatically requested)

## Safety Features

- **Non-Destructive** - Source folders are never modified or deleted
- **Validation Checks** - Prevents creation of invalid or conflicting junctions
- **Backup Integration** - All junction data is preserved in OneDrive
- **Error Recovery** - Graceful handling of permission and access issues


---

**Version:** 3.0  
**Last Updated:** June 14, 2025  
**Developer:** LRGEX  
**License:** Proprietary