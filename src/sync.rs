use crate::config;
use std::os::windows::process::CommandExt;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn is_dir_empty(path: &str) -> bool {
    match std::fs::read_dir(path) {
        Ok(mut entries) => entries.next().is_none(),
        Err(_) => true,
    }
}

/// Compact timestamp for snapshot folder names: YYYYMMDD_HHMMSS (local time)
fn compact_timestamp() -> String {
    use chrono::Local;
    Local::now().format("%Y%m%d_%H%M%S").to_string()
}

/// Parse a compact timestamp folder name back to Unix seconds (for age calculation)
fn parse_timestamp(name: &str) -> Option<u64> {
    if name.len() != 15 { return None; }
    let y: i64 = name[0..4].parse().ok()?;
    let mo: u32 = name[4..6].parse().ok()?;
    let d: u32 = name[6..8].parse().ok()?;
    let h: u32 = name[9..11].parse().ok()?;
    let mi: u32 = name[11..13].parse().ok()?;
    let s: u32 = name[13..15].parse().ok()?;
    let mut total_days: i64 = 0;
    for yr in 1970..y {
        total_days += if (yr%4==0 && yr%100!=0) || yr%400==0 {366} else {365};
    }
    let months = [31, if (y%4==0&&y%100!=0)||y%400==0 {29} else {28}, 31,30,31,30,31,31,30,31,30,31];
    for m in 0..(mo.saturating_sub(1) as usize) {
        total_days += months[m];
    }
    total_days += (d as i64) - 1;
    Some((total_days as u64) * 86400 + (h as u64) * 3600 + (mi as u64) * 60 + s as u64)
}

/// Recursively create a hardlink-based snapshot of the backup.
/// - Unchanged files: hardlink (near-zero space, both point to same disk blocks)
/// - Modified files: copy old version (hardlink would be corrupted by /MIR overwrite)
/// - Deleted files: hardlink (data survives when /MIR deletes the backup copy)
fn create_snapshot(backup: &Path, source: &Path, snapshot: &Path) {
    let _ = std::fs::create_dir_all(snapshot);
    let entries = match std::fs::read_dir(backup) {
        Ok(e) => e,
        Err(_) => { let _ = std::fs::remove_dir(snapshot); return; }
    };

    let mut has_content = false;
    for entry in entries.flatten() {
        let backup_path = entry.path();
        let name = entry.file_name();
        let source_path = source.join(&name);
        let snapshot_path = snapshot.join(&name);

        if backup_path.is_dir() {
            let _ = std::fs::create_dir_all(&snapshot_path);
            has_content = true;
            if source_path.is_dir() {
                create_snapshot(&backup_path, &source_path, &snapshot_path);
            } else {
                // Directory deleted from source — hardlink entire subtree
                hardlink_tree(&backup_path, &snapshot_path);
            }
        } else {
            has_content = true;
            if !source_path.exists() {
                // Deleted file — hardlink (survives /MIR purge)
                let _ = std::fs::hard_link(&backup_path, &snapshot_path);
            } else {
                let bm = std::fs::metadata(&backup_path).ok();
                let sm = std::fs::metadata(&source_path).ok();
                let modified = match (bm, sm) {
                    (Some(b), Some(s)) => {
                        b.len() != s.len() ||
                        b.modified().ok().zip(s.modified().ok()).map(|(x, y)| x != y).unwrap_or(false)
                    }
                    _ => false,
                };
                if modified {
                    // Copy old version (hardlink would be corrupted by /MIR overwrite)
                    let _ = std::fs::copy(&backup_path, &snapshot_path);
                } else {
                    // Unchanged — hardlink (near-zero space)
                    let _ = std::fs::hard_link(&backup_path, &snapshot_path);
                }
            }
        }
    }

    if !has_content {
        let _ = std::fs::remove_dir(snapshot);
    }
}

/// Recursively hardlink all files from src to dst (for deleted directories)
fn hardlink_tree(src: &Path, dst: &Path) {
    if let Ok(entries) = std::fs::read_dir(src) {
        for entry in entries.flatten() {
            let src_path = entry.path();
            let dst_path = dst.join(entry.file_name());
            if src_path.is_dir() {
                let _ = std::fs::create_dir_all(&dst_path);
                hardlink_tree(&src_path, &dst_path);
            } else {
                let _ = std::fs::hard_link(&src_path, &dst_path);
            }
        }
    }
}

/// Delete trash snapshot folders older than retention_days
fn clean_trash(trash_folder: &Path, retention_days: i32) {
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs()).unwrap_or(0);
    let cutoff = now_secs.saturating_sub((retention_days as u64) * 86400);
    if let Ok(entries) = std::fs::read_dir(trash_folder) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if let Some(ts) = parse_timestamp(&name) {
                if ts < cutoff {
                    let _ = std::fs::remove_dir_all(entry.path());
                }
            }
        }
    }
}

/// Check if source and backup differ (per-file: count, size, OR mtime). Early exit on first difference.
fn folders_differ(source: &Path, backup: &Path) -> bool {
    fn compare(src: &Path, bak: &Path) -> bool {
        let (src_entries, bak_entries) = match (std::fs::read_dir(src), std::fs::read_dir(bak)) {
            (Ok(s), Ok(b)) => (s, b),
            _ => return true, // one side can't be read = differ
        };
        let bak_map: std::collections::HashMap<std::ffi::OsString, std::path::PathBuf> =
            bak_entries.flatten().map(|e| (e.file_name(), e.path())).collect();
        let src_names: std::collections::HashSet<std::ffi::OsString> =
            src_entries.flatten().map(|e| e.file_name()).collect();
        // Files in backup not in source = deleted = differ
        for name in bak_map.keys() {
            if !src_names.contains(name) { return true; }
        }
        for entry in std::fs::read_dir(src).unwrap().flatten() {
            let name = entry.file_name();
            let src_path = entry.path();
            let bak_path = bak_map.get(&name);
            match bak_path {
                None => return true, // new file in source
                Some(bp) => {
                    if src_path.is_dir() {
                        if bp.is_dir() {
                            if compare(&src_path, bp) { return true; }
                        } else { return true; }
                    } else if bp.is_dir() {
                        return true;
                    } else {
                        // Both are files — compare size + mtime
                        let sm = std::fs::metadata(&src_path).ok();
                        let bm = std::fs::metadata(bp).ok();
                        match (sm, bm) {
                            (Some(s), Some(b)) => {
                                if s.len() != b.len() { return true; }
                                if s.modified().ok().zip(b.modified().ok()).map(|(x,y)| x != y).unwrap_or(true) { return true; }
                            }
                            _ => return true,
                        }
                    }
                }
            }
        }
        false
    }
    compare(source, backup)
}

pub fn sync_pair_to_cloud(source: &str, excluded: &[String], trash_retention_days: i32) -> (bool, String) {
    if source.is_empty() || !Path::new(source).exists() {
        return (false, "source does not exist".into());
    }
    let cloud = config::pair_cloud_path(source);
    if let Some(parent) = cloud.parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    let leaf = Path::new(source).file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();

    // Only create snapshot if backup exists AND something changed (per-file comparison)
    if cloud.exists() {
        if folders_differ(Path::new(source), &cloud) {
            // Something changed — create hardlink snapshot BEFORE /MIR
            let trash_folder = config::trash_path_for(&leaf);
            let _ = std::fs::create_dir_all(&trash_folder);
            let snapshot = trash_folder.join(compact_timestamp());
            create_snapshot(&cloud, Path::new(source), &snapshot);
            clean_trash(&trash_folder, trash_retention_days);
        }
    }

    // Run robocopy /MIR (exclude _versions)
    let trash_dir = config::script_dir().join("_versions");
    let mut args: Vec<String> = vec![
        source.into(),
        cloud.to_string_lossy().to_string(),
        "/MIR".into(), "/XJ".into(), "/NFL".into(), "/NDL".into(),
        "/NJH".into(), "/NJS".into(), "/NP".into(), "/R:5".into(), "/W:5".into(),
        "/XD".into(), trash_dir.to_string_lossy().to_string(),
    ];
    if !excluded.is_empty() {
        args.push("/XD".into());
        args.extend(excluded.iter().cloned());
    }

    let output = Command::new("robocopy.exe").args(&args)
        .creation_flags(0x08000000).output();
    match output {
        Ok(out) => {
            let code = out.status.code().unwrap_or(16);
            if code < 8 { (true, String::new()) }
            else { (false, format!("robocopy exit {}", code)) }
        }
        Err(e) => (false, e.to_string()),
    }
}

pub fn restore_pair_from_cloud(source: &str) -> (bool, String) {
    let cloud = config::pair_cloud_path(source);
    if !cloud.exists() { return (false, "backup missing".into()); }
    let _ = std::fs::create_dir_all(source);
    let args: Vec<String> = vec![
        cloud.to_string_lossy().to_string(), source.into(),
        "/E".into(), "/XJ".into(), "/NFL".into(), "/NDL".into(),
        "/NJH".into(), "/NJS".into(), "/NP".into(), "/R:5".into(), "/W:5".into(),
    ];
    let output = Command::new("robocopy.exe").args(&args)
        .creation_flags(0x08000000).output();
    match output {
        Ok(out) => {
            let code = out.status.code().unwrap_or(16);
            if code < 8 { (true, String::new()) }
            else { (false, format!("robocopy exit {}", code)) }
        }
        Err(e) => (false, e.to_string()),
    }
}

/// Restore an entire snapshot to the source location
pub fn restore_snapshot(snapshot: &Path, source: &str) -> (bool, String) {
    let _ = std::fs::create_dir_all(source);
    let args: Vec<String> = vec![
        snapshot.to_string_lossy().to_string(), source.into(),
        "/E".into(), "/XJ".into(), "/NFL".into(), "/NDL".into(),
        "/NJH".into(), "/NJS".into(), "/NP".into(), "/R:5".into(), "/W:5".into(),
    ];
    let output = Command::new("robocopy.exe").args(&args)
        .creation_flags(0x08000000).output();
    match output {
        Ok(out) => {
            let code = out.status.code().unwrap_or(16);
            if code < 8 { (true, String::new()) }
            else { (false, format!("robocopy exit {}", code)) }
        }
        Err(e) => (false, e.to_string()),
    }
}

pub fn sync_all_pairs() {
    let cfg = config::load_config();
    let mut ok = 0i32;
    let mut fail = 0i32;
    let mut restored = 0i32;
    let mut restored_names: Vec<String> = vec![];

    crate::synclog::write("------------------------------------------------------------");
    crate::synclog::write("Sync cycle");

    for j in &cfg.junctions {
        let leaf = Path::new(&j.source_path).file_name()
            .map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        let missing = !Path::new(&j.source_path).exists() || is_dir_empty(&j.source_path);

        if missing && j.auto_restore {
            let (success, _) = restore_pair_from_cloud(&j.source_path);
            if success {
                restored += 1;
                restored_names.push(leaf.clone());
                crate::synclog::write(&format!("  [RESTORE] {}  -  was missing, restored", leaf));
            } else {
                fail += 1;
                crate::synclog::write(&format!("  [FAIL] {}  -  restore failed", leaf));
            }
        } else {
            let (success, reason) = sync_pair_to_cloud(&j.source_path, &cfg.excluded_names, cfg.trash_retention_days);
            if success {
                ok += 1;
                crate::synclog::write(&format!("  [ OK ] {}", leaf));
            } else {
                fail += 1;
                crate::synclog::write(&format!("  [FAIL] {}  -  {}", leaf, reason));
            }
        }
    }

    crate::synclog::write(&format!("Done: {} mirrored, {} restored, {} failed.", ok, restored, fail));
    crate::health::write_status(ok + restored, fail, restored, &restored_names);
}

/// Register (or update) the Windows Scheduled Task that runs sync cycles automatically.
pub fn register_sync_task(interval_minutes: i32) -> bool {
    let exe = match std::env::current_exe() {
        Ok(p) => p.to_string_lossy().to_string(),
        Err(_) => return false,
    };
    let task_cmd = format!("\"{}\" -sync", exe);
    match Command::new("schtasks.exe")
        .args([
            "/Create",
            "/TN", "LRGEX-FolderSync-Rust",
            "/TR", &task_cmd,
            "/SC", "MINUTE",
            "/MO", &interval_minutes.to_string(),
            "/F",
        ])
        .creation_flags(0x08000000u32)
        .output()
    {
        Ok(out) => out.status.success(),
        Err(_) => false,
    }
}
