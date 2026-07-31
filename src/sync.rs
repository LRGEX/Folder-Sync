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

// ==================== COMPRESSION (tar + zstd) ====================

/// Compress a source directory to a .tar.zst file (ZSTD — fast, good ratio)
fn compress_folder(source: &Path, dest: &Path, excluded: &[String]) -> bool {
    let file = match std::fs::File::create(dest) {
        Ok(f) => f,
        Err(_) => return false,
    };
    let zstd_encoder = match zstd::Encoder::new(file, 3) {
        Ok(e) => e.auto_finish(),
        Err(_) => return false,
    };
    let mut builder = tar::Builder::new(zstd_encoder);
    builder.mode(tar::HeaderMode::Deterministic);

    let mut ok = true;
    add_to_tar(&mut builder, source, source, excluded, &mut ok);

    if ok {
        builder.finish().is_ok()
    } else {
        false
    }
}

fn add_to_tar<W: std::io::Write>(
    builder: &mut tar::Builder<W>,
    base: &Path,
    current: &Path,
    excluded: &[String],
    ok: &mut bool,
) {
    if let Ok(entries) = std::fs::read_dir(current) {
        for entry in entries.flatten() {
            if !*ok { return; }
            let name = entry.file_name().to_string_lossy().to_string();
            if excluded.iter().any(|e| e == &name) { continue; }

            let path = entry.path();

            if path.is_dir() {
                add_to_tar(builder, base, &path, excluded, ok);
            } else {
                if builder.append_path_with_name(&path, path.strip_prefix(base).unwrap_or(&path)).is_err() {
                    *ok = false;
                    return;
                }
            }
        }
    }
}

/// Decompress a .tar.zst file to a destination directory
fn decompress_archive(archive: &Path, dest: &Path) -> bool {
    let _ = std::fs::create_dir_all(dest);
    let file = match std::fs::File::open(archive) {
        Ok(f) => f,
        Err(_) => return false,
    };
    let decoder = match zstd::Decoder::new(file) {
        Ok(d) => d,
        Err(_) => return false,
    };
    let mut tar = tar::Archive::new(decoder);
    tar.unpack(dest).is_ok()
}

/// Compute total size AND file count, skipping excluded names
fn compute_stats(dir: &Path, excluded: &[String]) -> (u64, usize) {
    let mut total = 0u64;
    let mut count = 0usize;
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if excluded.iter().any(|e| e == &name) { continue; }
            let path = entry.path();
            if path.is_dir() {
                let (s, c) = compute_stats(&path, excluded);
                total += s;
                count += c;
            } else {
                total += entry.metadata().map(|m| m.len()).unwrap_or(0);
                count += 1;
            }
        }
    }
    (total, count)
}

/// Read stored source stats from sidecar file
fn read_stored_stats(sidecar: &Path) -> (u64, usize) {
    std::fs::read_to_string(sidecar)
        .ok()
        .and_then(|s| {
            let parts: Vec<&str> = s.trim().split(',').collect();
            if parts.len() == 2 {
                Some((parts[0].parse().ok()?, parts[1].parse().ok()?))
            } else {
                None
            }
        })
        .unwrap_or((u64::MAX, usize::MAX))
}

/// Write source stats to sidecar file
fn write_stored_stats(sidecar: &Path, size: u64, count: usize) {
    let _ = std::fs::write(sidecar, format!("{},{}", size, count));
}

// ==================== TIMESTAMPS ====================

fn compact_timestamp() -> String {
    use chrono::Local;
    Local::now().format("%Y%m%d_%H%M%S").to_string()
}

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

// ==================== VERSIONING ====================

/// Create a versioning snapshot by hardlinking the current .tar.zst backup
fn create_snapshot(backup_7z: &Path, versions_folder: &Path) {
    if !backup_7z.exists() { return; }
    let _ = std::fs::create_dir_all(versions_folder);
    let snapshot_dir = versions_folder.join(compact_timestamp());
    let _ = std::fs::create_dir_all(&snapshot_dir);
    let snapshot_7z = snapshot_dir.join(backup_7z.file_name().unwrap_or_default());
    // Hardlink the .tar.zst (near-zero space if unchanged)
    if std::fs::hard_link(backup_7z, &snapshot_7z).is_err() {
        let _ = std::fs::copy(backup_7z, &snapshot_7z);
    }
}

/// Delete old versioning snapshots
fn clean_versions(versions_folder: &Path, retention_days: i32) {
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs()).unwrap_or(0);
    let cutoff = now_secs.saturating_sub((retention_days as u64) * 86400);
    if let Ok(entries) = std::fs::read_dir(versions_folder) {
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

// ==================== SYNC ENGINE ====================

pub fn sync_pair_to_cloud(source: &str, excluded: &[String], retention_days: i32) -> (bool, String) {
    if source.is_empty() || !Path::new(source).exists() {
        return (false, "source does not exist".into());
    }

    let leaf = Path::new(source).file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();

    // Backup paths
    let backup_7z = config::backup_file_for(&leaf);
    let sidecar = config::sidecar_for(&leaf);
    let backup_dir = config::backup_dir_for(&leaf);
    let _ = std::fs::create_dir_all(&backup_dir);
    let versions_folder = config::trash_path_for(&leaf);

    // Migration: old root-level backup → delete (will re-compress to backup/ on next sync)
    let old_root_backup = config::script_dir().join(format!("{}.tar.zst", leaf));
    let old_root_sidecar = config::script_dir().join(format!("{}.tar.zst.size", leaf));
    if old_root_backup.exists() {
        let _ = std::fs::remove_file(&old_root_backup);
        let _ = std::fs::remove_file(&old_root_sidecar);
    }

    // Migration: if old raw backup folder exists, compress it
    let old_backup_folder = config::script_dir().join(&leaf);
    if old_backup_folder.is_dir() && !backup_7z.exists() {
        let _ = compress_folder(&old_backup_folder, &backup_7z, excluded);
        let _ = std::fs::remove_dir_all(&old_backup_folder);
    }

    // Change detection: compare current source stats with stored stats
    let (current_size, current_count) = compute_stats(Path::new(source), excluded);
    let (stored_size, stored_count) = read_stored_stats(&sidecar);

    if current_size != stored_size || current_count != stored_count || !backup_7z.exists() {
        // Something changed — create snapshot of old backup, then re-compress
        if backup_7z.exists() {
            create_snapshot(&backup_7z, &versions_folder);
        }
        clean_versions(&versions_folder, retention_days);

        // Compress source to temp, then move (atomic-ish)
        let temp_7z = backup_dir.join(format!("{}.tar.zst.tmp", leaf));
        if compress_folder(Path::new(source), &temp_7z, excluded) {
            let _ = std::fs::remove_file(&backup_7z);
            if std::fs::rename(&temp_7z, &backup_7z).is_ok() {
                write_stored_stats(&sidecar, current_size, current_count);
            } else {
                // Rename failed (OneDrive lock?) — try copy + delete
                if std::fs::copy(&temp_7z, &backup_7z).is_ok() {
                    let _ = std::fs::remove_file(&temp_7z);
                    write_stored_stats(&sidecar, current_size, current_count);
                } else {
                    let _ = std::fs::remove_file(&temp_7z);
                    return (false, "rename failed".into());
                }
            }
        } else {
            let _ = std::fs::remove_file(&temp_7z);
            return (false, "compression failed".into());
        }
    }

    (true, String::new())
}

pub fn restore_pair_from_cloud(source: &str) -> (bool, String) {
    let leaf = Path::new(source).file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();

    let backup_7z = config::backup_file_for(&leaf);

    // Try .tar.zst first (new format)
    if backup_7z.exists() {
        if decompress_archive(&backup_7z, Path::new(source)) {
            return (true, String::new());
        }
        return (false, "decompression failed".into());
    }

    // Fallback: old raw folder format
    let old_backup = config::script_dir().join(&leaf);
    if old_backup.exists() {
        let _ = std::fs::create_dir_all(source);
        let args: Vec<String> = vec![
            old_backup.to_string_lossy().to_string(), source.into(),
            "/E".into(), "/XJ".into(), "/NFL".into(), "/NDL".into(),
            "/NJH".into(), "/NJS".into(), "/NP".into(), "/R:5".into(), "/W:5".into(),
        ];
        let output = Command::new("robocopy.exe").args(&args)
            .creation_flags(0x08000000).output();
        return match output {
            Ok(out) => {
                let code = out.status.code().unwrap_or(16);
                if code < 8 { (true, String::new()) }
                else { (false, format!("robocopy exit {}", code)) }
            }
            Err(e) => (false, e.to_string()),
        };
    }

    (false, "backup missing".into())
}

pub fn sync_all_pairs() {
    let cfg = config::load_config();
    let mut ok = 0i32;
    let mut fail = 0i32;
    let mut restored = 0i32;
    let mut restored_names: Vec<String> = vec![];

    crate::synclog::write("------------------------------------------------------------");
    crate::synclog::write("Sync cycle");
    crate::synclog::write_progress("");

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
            crate::synclog::write_progress(&format!("Compressing {}...", leaf));
            let (success, reason) = sync_pair_to_cloud(&j.source_path, &cfg.excluded_names, cfg.trash_retention_days);
            crate::synclog::write_progress("");
            if success {
                ok += 1;
                crate::synclog::write(&format!("  [ OK ] {}", leaf));
            } else {
                fail += 1;
                crate::synclog::write(&format!("  [FAIL] {}  -  {}", leaf, reason));
            }
        }
    }

    crate::synclog::write(&format!("Done: {} compressed, {} restored, {} failed.", ok, restored, fail));
    crate::health::write_status(ok + restored, fail, restored, &restored_names);
}

// ==================== RESTORE FROM SNAPSHOT ====================

/// Restore a specific snapshot version to the source location
pub fn restore_snapshot(snapshot_dir: &Path, source: &str) -> (bool, String) {
    // Look for .tar.zst file in the snapshot directory
    if let Ok(entries) = std::fs::read_dir(snapshot_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "zst").unwrap_or(false) {
                let _ = std::fs::create_dir_all(source);
                if decompress_archive(&path, Path::new(source)) {
                    return (true, String::new());
                }
                return (false, "decompression failed".into());
            }
        }
    }
    // Fallback: old-style raw files snapshot
    let args: Vec<String> = vec![
        snapshot_dir.to_string_lossy().to_string(), source.into(),
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

// ==================== SCHEDULED TASK ====================

/// Register (or update) the Windows Scheduled Task.
/// Uses CANONICAL HOME from registry — never current_exe().
/// This prevents stray copies from retargeting the task.
pub fn register_sync_task(interval_minutes: i32) -> bool {
    let home = match config::canonical_home() {
        Some(h) => h,
        None => return false, // not registered yet — can't register task
    };
    let exe = home.join("folder_sync.exe");
    let task_cmd = format!("\"{}\" -sync", exe.to_string_lossy());

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
