use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "PascalCase")]
pub struct Junction {
    #[serde(default)]
    pub source_path: String,
    #[serde(default)]
    pub auto_restore: bool,
    #[serde(default)]
    pub created: String,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "PascalCase")]
pub struct Config {
    #[serde(default, rename = "Junctions")]
    pub junctions: Vec<Junction>,
    #[serde(default = "default_interval", rename = "SyncIntervalMinutes")]
    pub sync_interval_minutes: i32,
    #[serde(default, rename = "ExcludedNames")]
    pub excluded_names: Vec<String>,
    #[serde(default = "default_trash_retention", rename = "TrashRetentionDays")]
    pub trash_retention_days: i32,
}

fn default_interval() -> i32 { 120 }
fn default_trash_retention() -> i32 { 90 }

impl Default for Config {
    fn default() -> Self {
        Config {
            junctions: vec![],
            sync_interval_minutes: 120,
            excluded_names: vec![],
            trash_retention_days: 90,
        }
    }
}

pub fn script_dir() -> PathBuf {
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    exe.parent().unwrap_or(std::path::Path::new(".")).to_path_buf()
}

pub fn config_path() -> PathBuf {
    script_dir().join("junction-config.json")
}

pub fn load_config() -> Config {
    let path = config_path();
    match std::fs::read_to_string(&path) {
        Ok(data) => {
            let data = data.strip_prefix('\u{feff}').unwrap_or(&data);
            serde_json::from_str(data).unwrap_or_default()
        }
        Err(_) => Config::default(),
    }
}

pub fn save_config(cfg: &Config) {
    let path = config_path();
    if let Ok(data) = serde_json::to_string_pretty(cfg) {
        let _ = std::fs::write(&path, data);
    }
}

pub fn is_home() -> bool {
    script_dir().join(".lrgex-home").exists()
}

const REG_PATH: &str = "SOFTWARE\\LRGEX\\FolderSync";

/// Canonical home path — stored in registry, ONE source of truth.
/// register_sync_task uses THIS, never current_exe().
pub fn canonical_home() -> Option<PathBuf> {
    winreg::RegKey::predef(winreg::enums::HKEY_CURRENT_USER)
        .open_subkey(REG_PATH)
        .ok()
        .and_then(|k| k.get_value::<String, _>("HomePath").ok())
        .map(PathBuf::from)
}

/// Set canonical home in registry (called once during first-run setup)
pub fn set_canonical_home(path: &Path) {
    if let Ok(key) = winreg::RegKey::predef(winreg::enums::HKEY_CURRENT_USER)
        .create_subkey(REG_PATH) {
        let _ = key.0.set_value("HomePath", &path.to_string_lossy().to_string());
    }
}

/// Delete canonical home from registry (called during uninstall)
pub fn clear_canonical_home() {
    if let Ok(parent) = winreg::RegKey::predef(winreg::enums::HKEY_CURRENT_USER)
        .open_subkey_with_flags("SOFTWARE\\LRGEX", winreg::enums::KEY_WRITE) {
        let _ = parent.delete_subkey_all("FolderSync");
    }
}

pub fn pair_cloud_path(source: &str) -> PathBuf {
    let leaf = std::path::Path::new(source)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    script_dir().join(&leaf)
}

pub fn trash_base() -> PathBuf {
    script_dir().join("_versions")
}

/// One-time setup: migrate old _trash → _versions, set hidden attribute.
/// Call ONCE at startup, not in hot paths.
pub fn ensure_versions_setup() {
    let versions = trash_base();
    if !versions.exists() {
        let old = script_dir().join("_trash");
        if old.exists() {
            let _ = std::fs::rename(&old, &versions);
        }
    }
    if versions.exists() {
        // Skip attrib spawn if already hidden+system (0x2=hidden, 0x4=system)
        use std::os::windows::fs::MetadataExt;
        let already_set = std::fs::metadata(&versions)
            .map(|m| m.file_attributes() & 0x6 == 0x6)
            .unwrap_or(false);
        if !already_set {
            use std::os::windows::process::CommandExt;
            let _ = std::process::Command::new("attrib")
                .args(["+H", "+S", versions.to_str().unwrap_or("")])
                .creation_flags(0x08000000u32)
                .spawn();
        }
    }
}

pub fn trash_path_for(leaf: &str) -> PathBuf {
    trash_base().join(leaf)
}

/// Backup directory: home/backup/<folder-name>/
pub fn backup_dir_for(leaf: &str) -> PathBuf {
    script_dir().join("backup").join(leaf)
}

/// Backup file path: home/backup/<folder-name>/<folder-name>.tar.zst
pub fn backup_file_for(leaf: &str) -> PathBuf {
    backup_dir_for(leaf).join(format!("{}.tar.zst", leaf))
}

/// Sidecar path: home/backup/<folder-name>/<folder-name>.tar.zst.size
pub fn sidecar_for(leaf: &str) -> PathBuf {
    backup_dir_for(leaf).join(format!("{}.tar.zst.size", leaf))
}
