use crate::config;
use std::os::windows::process::CommandExt;
use std::path::Path;
use std::process::Command;

pub fn is_dir_empty(path: &str) -> bool {
    match std::fs::read_dir(path) {
        Ok(mut entries) => entries.next().is_none(),
        Err(_) => true,
    }
}

// ==================== COMPRESSION (tar + zstd) ====================

/// Compress a source directory to a .tar.zst file (ZSTD — fast, good ratio)
fn compress_folder(source: &Path, dest: &Path, excluded: &[String], total: usize) -> (bool, Vec<String>) {
    let file = match std::fs::File::create(dest) {
        Ok(f) => f,
        Err(_) => return (false, vec![]),
    };
    // Level 1 (fastest) + multi-threaded (all CPU cores)
    let encoder = match zstd::Encoder::new(file, 1) {
        Ok(e) => e,
        Err(_) => return (false, vec![]),
    };
    let zstd_encoder = encoder.auto_finish();
    let mut builder = tar::Builder::new(zstd_encoder);
    builder.mode(tar::HeaderMode::Deterministic);

    let mut processed = 0usize;
    let mut skipped: Vec<String> = Vec::new();
    let leaf = source.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    add_to_tar(&mut builder, source, source, excluded, &mut processed, &mut skipped, total, &leaf);

    let ok = builder.finish().is_ok();
    (ok, skipped)
}

fn add_to_tar<W: std::io::Write>(
    builder: &mut tar::Builder<W>,
    base: &Path,
    current: &Path,
    excluded: &[String],
    processed: &mut usize,
    skipped: &mut Vec<String>,
    total: usize,
    leaf: &str,
) {
    if let Ok(entries) = std::fs::read_dir(current) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if excluded.iter().any(|e| e == &name) { continue; }

            let path = entry.path();

            if path.is_dir() {
                add_to_tar(builder, base, &path, excluded, processed, skipped, total, leaf);
            } else {
                match builder.append_path_with_name(&path, path.strip_prefix(base).unwrap_or(&path)) {
                    Ok(_) => {
                        *processed += 1;
                        if *processed % 500 == 0 {
                            let pct = (*processed as f64 / total as f64 * 100.0) as usize;
                            crate::synclog::write_progress(&format!("Compressing {}: {}% ({} files)", leaf, pct, processed));
                        }
                    }
                    Err(_) => {
                        // Never silent — log each skipped file so the user knows exactly what was missed
                        let rel = path.strip_prefix(base).unwrap_or(&path).to_string_lossy().to_string();
                        crate::synclog::write(&format!("  [SKIP] {} (locked/unreadable)", rel));
                        skipped.push(rel);
                    }
                }
            }
        }
    }
}

/// Decompress a .tar.zst file to a destination directory
/// Atomic extraction: decompress to a TEMP dir first.
/// Only on FULL success: merge into destination (overwrite existing).
/// On ANY failure: discard temp, destination completely untouched.
/// This guarantees no partial restores — ever.
pub fn decompress_archive(archive: &Path, dest: &Path) -> (bool, String) {
    let _ = std::fs::create_dir_all(dest);

    // Temp dir in the SAME parent (so rename is fast, same filesystem)
    let temp_dir = dest.parent().unwrap_or(std::path::Path::new("."))
        .join(format!(".lrgex_restore_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&temp_dir);
    let _ = std::fs::create_dir_all(&temp_dir);

    let file = match std::fs::File::open(archive) {
        Ok(f) => f,
        Err(e) => { let _ = std::fs::remove_dir_all(&temp_dir); return (false, format!("cannot open archive: {}", e)); }
    };
    let decoder = match zstd::Decoder::new(file) {
        Ok(d) => d,
        Err(e) => { let _ = std::fs::remove_dir_all(&temp_dir); return (false, format!("corrupt archive (zstd): {}", e)); }
    };
    let mut tar = tar::Archive::new(decoder);

    match tar.unpack(&temp_dir) {
        Ok(_) => {
            // Full success — atomic rename-swap:
            // 1. Rename dest → dest.lrgex_bak
            // 2. Rename temp → dest
            // 3. Remove dest.lrgex_bak
            // If step 2 fails, roll back. Destination is never half-written.
            let backup_name = dest.with_extension("lrgex_bak");
            let _ = std::fs::remove_dir_all(&backup_name);

            if dest.exists() {
                if std::fs::rename(dest, &backup_name).is_err() {
                    let _ = std::fs::remove_dir_all(&temp_dir);
                    return (false, "cannot swap destination (locked?)".into());
                }
            }

            if let Err(e) = std::fs::rename(&temp_dir, dest) {
                // Roll back: restore original destination
                if backup_name.exists() {
                    let _ = std::fs::rename(&backup_name, dest);
                }
                let _ = std::fs::remove_dir_all(&temp_dir);
                return (false, format!("swap failed: {}", e));
            }

            // Success — clean up old data
            let _ = std::fs::remove_dir_all(&backup_name);
            (true, String::new())
        }
        Err(e) => {
            // FAILURE — discard temp, destination COMPLETELY UNTOUCHED
            let _ = std::fs::remove_dir_all(&temp_dir);
            (false, format!("extract failed: {}", e))
        }
    }
}

/// Compute total size AND file count, skipping excluded names
fn compute_stats(dir: &Path, excluded: &[String]) -> (u64, usize) {
    let leaf = dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    crate::synclog::write_progress(&format!("Scanning {}...", leaf));
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
/// Keep only the N newest snapshots, delete the rest
fn clean_versions(versions_folder: &Path, max_versions: usize) {
    if let Ok(entries) = std::fs::read_dir(versions_folder) {
        let mut snapshots: Vec<_> = entries
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().len() == 15)
            .collect();
        snapshots.sort_by(|a, b| b.file_name().cmp(&a.file_name()));
        for entry in snapshots.iter().skip(max_versions) {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
}

// ==================== SYNC ENGINE ====================

pub fn sync_pair_to_cloud(source: &str, excluded: &[String], max_versions: i32, force: bool) -> (bool, String) {
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
        let _ = compress_folder(&old_backup_folder, &backup_7z, excluded, 0); // (bool, Vec) — ignore result for migration
        let _ = std::fs::remove_dir_all(&old_backup_folder);
    }

    // Change detection: compare current source stats with stored stats
    let (current_size, current_count) = compute_stats(Path::new(source), excluded);
    let (stored_size, stored_count) = read_stored_stats(&sidecar);

    if force || current_size != stored_size || current_count != stored_count || !backup_7z.exists() {
        let mut snapshotted = false;
        // Something changed — create snapshot of old backup, then re-compress
        if backup_7z.exists() {
            create_snapshot(&backup_7z, &versions_folder);
            snapshotted = true;
        }
        clean_versions(&versions_folder, max_versions as usize);

        // Compress source to temp, then move (atomic-ish)
        // PID-unique temp name prevents corruption if two processes ever collide
        let temp_7z = std::env::temp_dir().join(format!("lrgex_{}_{}.tar.zst.tmp", std::process::id(), leaf));
        let (compress_ok, skipped) = compress_folder(Path::new(source), &temp_7z, excluded, current_count);
        if compress_ok {
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

        let size_mb = current_size as f64 / 1_048_576.0;
        let skip_msg = if skipped.is_empty() {
            String::new()
        } else {
            format!(" {} file(s) skipped (locked). Archive may be incomplete.", skipped.len())
        };
        let msg = if snapshotted {
            format!("Backed up {} files ({:.1} MB). Previous version archived.{}", current_count, size_mb, skip_msg)
        } else {
            format!("Backed up {} files ({:.1} MB).{}", current_count, size_mb, skip_msg)
        };
        return (true, msg);
    }

    (true, "No changes \u{2014} up to date.".into())
}

/// Pre-check ALL folders before restoring ANY. Returns list of failures (path, reason).
/// If ANY failure exists, the caller must abort the entire restore — no partial restores.
pub fn pre_check_restore(paths: &[String]) -> Vec<(String, String)> {
    let mut failures = Vec::new();
    use std::io::Read;

    for path in paths {
        let leaf = std::path::Path::new(path).file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        let backup = config::backup_file_for(&leaf);

        // 1. Backup archive exists?
        if !backup.exists() {
            failures.push((leaf, "backup missing".into()));
            continue;
        }

        // 2. Archive is valid zstd? (check magic bytes: 28 b5 2f fd)
        let mut header = [0u8; 4];
        let valid_zstd = std::fs::File::open(&backup)
            .and_then(|mut f| f.read_exact(&mut header).map(|_| f))
            .map(|_| header == [0x28, 0xb5, 0x2f, 0xfd])
            .unwrap_or(false);
        if !valid_zstd {
            failures.push((leaf, "backup archive is corrupt or incomplete".into()));
            continue;
        }

        // 3. Destination is writable?
        let dest = std::path::Path::new(path);
        let can_write = if dest.exists() {
            let test = dest.join(".lrgex_write_test");
            match std::fs::File::create(&test) {
                Ok(_) => { let _ = std::fs::remove_file(&test); true }
                Err(_) => false,
            }
        } else {
            std::fs::create_dir_all(dest).is_ok()
        };
        if !can_write {
            failures.push((leaf, "permission denied \u{2014} run app as administrator".into()));
            continue;
        }
    }

    failures
}

pub fn restore_pair_from_cloud(source: &str) -> (bool, String) {
    let leaf = Path::new(source).file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();

    let backup_7z = config::backup_file_for(&leaf);

    // Try .tar.zst first (new format)
    if backup_7z.exists() {
        let (ok, msg) = decompress_archive(&backup_7z, Path::new(source));
        if ok {
            return (true, String::new());
        }
        return (false, if msg.is_empty() { "decompression failed".into() } else { msg });
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
                // Set migration marker so future syncs check for new game-created ID folders
                set_migration_pending();
                // Also try migration now (game might have already created new ID)
                let mig = migrate_save_ids(Path::new(&j.source_path));
                for m in &mig { crate::synclog::write(&format!("  [MIGRATE] {}", m)); }
            } else {
                fail += 1;
                crate::synclog::write(&format!("  [FAIL] {}  -  restore failed", leaf));
            }
        } else {
            crate::synclog::write_progress(&format!("Compressing {}...", leaf));
            let (success, reason) = sync_pair_to_cloud(&j.source_path, &cfg.excluded_names, cfg.max_versions, false);
            crate::synclog::write_progress("");
            if success {
                ok += 1;
                crate::synclog::write(&format!("  [ OK ] {}", leaf));
                // Only scan for migration if a restore happened recently (post-restore gate)
                if migration_pending() {
                    let mig = migrate_save_ids(Path::new(&j.source_path));
                    for m in &mig { crate::synclog::write(&format!("  [MIGRATE] {}", m)); }
                }
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
                let (ok, msg) = decompress_archive(&path, Path::new(source));
                if ok {
                    return (true, String::new());
                }
                return (false, if msg.is_empty() { "decompression failed".into() } else { msg });
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

/// List files inside a .tar.zst archive (without extracting)

// ==================== SCHEDULED TASK ====================

/// Register (or update) the Windows Scheduled Task.
/// Uses CANONICAL HOME from registry — never current_exe().
/// This prevents stray copies from retargeting the task.

/// Delete old VBS-based scheduled tasks from the PowerShell version.
/// Prevents "cannot find sync-runner.vbs" errors for users upgrading from old version.
pub fn cleanup_old_tasks() {
    use std::process::Command;
    if let Ok(out) = Command::new("schtasks.exe")
        .args(["/Query", "/FO", "CSV", "/V"])
        .creation_flags(0x08000000u32)
        .output()
    {
        let csv = String::from_utf8_lossy(&out.stdout);
        for line in csv.lines() {
            let lower = line.to_lowercase();
            if (lower.contains("sync-runner.vbs") || (lower.contains("lrgex") && lower.contains(".vbs")))
                && !lower.contains("lrgex-foldersync-rust")
            {
                if let Some(name) = line.split('"').nth(1) {
                    let _ = Command::new("schtasks.exe")
                        .args(["/Delete", "/TN", name, "/F"])
                        .creation_flags(0x08000000u32)
                        .output();
                    crate::synclog::write(&format!("  [CLEANUP] Deleted old task: {}", name));
                }
            }
        }
    }
}
pub fn register_sync_task(interval_minutes: i32) -> bool {
    let home = match config::canonical_home() {
        Some(h) => h,
        None => return false,
    };
    let exe = home.join("LRGEXSync.exe");
    let task_cmd = format!("\"{}\" -sync", exe.to_string_lossy());

    // schtasks /SC MINUTE max is 1439, /SC HOURLY max is 23.
    // Pick the right schedule type based on interval size.
    let (schedule, modifier) = if interval_minutes >= 1440 {
        // 24+ hours: MINUTE max is 1439, use DAILY instead
        let days = (interval_minutes / 1440).max(1);
        ("DAILY", days.to_string())
    } else {
        // Under 24 hours: MINUTE with exact precision
        ("MINUTE", interval_minutes.to_string())
    };

    match Command::new("schtasks.exe")
        .args([
            "/Create",
            "/TN", "LRGEX-FolderSync-Rust",
            "/TR", &task_cmd,
            "/SC", schedule,
            "/MO", &modifier,
            "/F",
        ])
        .creation_flags(0x08000000u32)
        .output()
    {
        Ok(out) => out.status.success(),
        Err(_) => false,
    }
}
// ==================== SAVE-ID MIGRATION ====================

/// Directories that never contain game saves. Skipped during scanning to avoid
/// false positives (e.g. node_modules/es-abstract/2015/) and wasted traversal.
const SKIP_DIRS: &[&str] = &[
    "node_modules", ".git", "target", "build", "__pycache__",
    ".venv", "venv", "dist", ".cache", ".npm", ".cargo",
    "dependencies", "packages", "system32", "winsxs",
];

/// Returns true if a directory name should be skipped during scanning.
fn should_skip(name: &str) -> bool {
    let lower = name.to_lowercase();
    SKIP_DIRS.iter().any(|s| *s == lower)
}

/// Marker file: set after restore so syncs know to check for new game ID folders.
/// Auto-expires after 7 days. Cleared after successful migration.
pub fn set_migration_pending() {
    let _ = std::fs::write(config::script_dir().join(".migration-pending"), "");
}

pub fn clear_migration_pending() {
    let _ = std::fs::remove_file(config::script_dir().join(".migration-pending"));
}

fn migration_pending() -> bool {
    let marker = config::script_dir().join(".migration-pending");
    if !marker.exists() { return false; }
    if let Ok(meta) = std::fs::metadata(&marker) {
        if let Ok(mtime) = meta.modified() {
            if mtime.elapsed().unwrap_or_default().as_secs() < 7 * 86400 {
                return true;
            }
        }
    }
    let _ = std::fs::remove_file(&marker); // Expired — clean up
    false
}

/// Cheap check (file existence only) for the health timer.
/// Avoids spawning a thread every 30s when no restore has happened.
pub fn migration_marker_exists() -> bool {
    config::script_dir().join(".migration-pending").exists()
}

/// Shallow-ish check: does this folder contain game saves at any reasonable depth?
/// Recurses up to 4 levels into non-numeric subdirs, stops at first match.
/// Used for the UI lamp indicator. Diagnostic: if lamp is off but saves exist,
/// the detection patterns need updating.
pub fn is_game_folder(path: &str) -> bool {
    let mut visited = 0usize;
    check_game_at_depth(std::path::Path::new(path), 0, &mut visited)
}

fn check_game_at_depth(dir: &Path, depth: usize, visited: &mut usize) -> bool {
    if depth > 4 { return false; }
    // Cap: bail after 300 dirs visited. Real game saves are found within
    // the first few dozen dirs. This bounds the worst case for large trees.
    if *visited > 300 { return false; }
    *visited += 1;

    let save_dirs = ["savedata", "save", "saves", "SaveGames", "SaveData",
                     "remote", "profiles", "slot", "slots",
                     "saved games", "savegame", "saved"];

    if let Ok(entries) = std::fs::read_dir(dir) {
        let mut numeric_dirs: Vec<std::path::PathBuf> = Vec::new();
        let mut other_dirs: Vec<std::path::PathBuf> = Vec::new();

        for entry in entries.flatten() {
            if !entry.path().is_dir() { continue; }
            let name = entry.file_name().to_string_lossy().to_string();
            // Skip known non-game directories (node_modules, .git, target, etc.)
            if should_skip(&name) { continue; }
            if name.chars().all(|c| c.is_ascii_digit()) {
                numeric_dirs.push(entry.path());
            } else {
                other_dirs.push(entry.path());
            }
        }

        // Check if any numeric dir has a recognized save subdir with files
        for nd in &numeric_dirs {
            for sd in &save_dirs {
                let p = nd.join(sd);
                if p.is_dir() {
                    if let Ok(files) = std::fs::read_dir(&p) {
                        if files.flatten().next().is_some() { return true; }
                    }
                }
            }
            // Also check depth 2: numeric/<appID>/remote (Steam pattern)
            if let Ok(sub) = std::fs::read_dir(nd) {
                for s in sub.flatten() {
                    if s.path().is_dir() {
                        let remote = s.path().join("remote");
                        if remote.is_dir() {
                            if let Ok(files) = std::fs::read_dir(&remote) {
                                if files.flatten().next().is_some() { return true; }
                            }
                        }
                    }
                }
            }
        }

        // Recurse into non-numeric subdirs (stop at first match)
        for od in &other_dirs {
            if check_game_at_depth(od, depth + 1, visited) { return true; }
        }
    }
    false
}

pub fn migrate_save_ids(folder: &Path) -> Vec<String> {
    let mut migrations = Vec::new();
    scan_for_id_folders(folder, &mut migrations);
    migrations
}

/// Lightweight check for GUI startup: only runs if marker exists.
/// Returns migration messages (empty = nothing to do or no marker).
/// Mutex prevents concurrent migration runs (scheduled sync, post-launch check,
/// health timer can all fire at once after a restore).
static MIGRATION_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

pub fn run_migration_check() -> Vec<String> {
    // Only one migration run at a time — skip if another thread is already migrating
    let _lock = match MIGRATION_LOCK.try_lock() {
        Ok(guard) => guard,
        Err(_) => return vec![],
    };
    if !migration_pending() { return vec![]; }
    let cfg = config::load_config();
    let mut all = Vec::new();
    for j in &cfg.junctions {
        let mig = migrate_save_ids(Path::new(&j.source_path));
        for m in &mig { all.push(m.clone()); }
    }
    // Only clear marker if a real migration happened (not REFUSED, not empty).
    // This way: first launch (games not installed yet) → marker stays →
    // next launch (after games installed) → migration runs → marker cleared.
    // Tradeoff: repeated scans on each launch until migration succeeds or
    // 7-day expiry. Acceptable — runs on background thread, scans are lightweight.
    let has_real_migration = all.iter().any(|m| !m.starts_with("REFUSED"));
    if has_real_migration {
        clear_migration_pending();
    }
    all
}

/// Universal scan: walk the tree looking for ANY directory that has 2+ numeric
/// subdirectories. Works for users\<ID>, userdata\<ID>, <game-name>\<ID>, etc.
/// Does NOT recurse into numeric subdirs (they're leaf ID folders, not nesting levels).
/// Safety: source must have savedata\/remote\ with files, target must be empty (≤5 files).
fn scan_for_id_folders(dir: &Path, migrations: &mut Vec<String>) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        let mut numeric_subdirs: Vec<(std::path::PathBuf, String)> = Vec::new();
        let mut other_subdirs: Vec<std::path::PathBuf> = Vec::new();

        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() { continue; }
            let name = entry.file_name().to_string_lossy().to_string();

            // Skip known non-game directories (node_modules, .git, target, etc.)
            if should_skip(&name) { continue; }

            if name.chars().all(|c| c.is_ascii_digit()) {
                numeric_subdirs.push((path, name)); // Leaf ID folder — don't recurse
            } else {
                other_subdirs.push(path); // Non-numeric — safe to recurse
            }
        }

        // If this directory has 2+ numeric subdirs, check for migration
        if numeric_subdirs.len() >= 2 {
            try_migrate(dir, &numeric_subdirs, migrations);
        }

        // Only recurse into non-numeric subdirs
        for path in &other_subdirs {
            scan_for_id_folders(path, migrations);
        }
    }
}

fn try_migrate(parent: &Path, numeric: &[(std::path::PathBuf, String)], migrations: &mut Vec<String>) {
    // Classify each numeric folder
    let mut classified: Vec<(&std::path::PathBuf, &String, SaveState, usize, u64, std::time::SystemTime)> = Vec::new();

    for (id_path, id_name) in numeric {
        let (state, save_count, save_bytes, mtime) = classify_folder(id_path);
        classified.push((id_path, id_name, state, save_count, save_bytes, mtime));
    }

    // Three-state: if ANY folder is Unknown → refuse migration entirely
    let unknown_names: Vec<&str> = classified.iter()
        .filter(|(_, _, s, _, _, _)| *s == SaveState::Unknown)
        .map(|(_, name, _, _, _, _)| name.as_str())
        .collect();
    if !unknown_names.is_empty() {
        migrations.push(format!("REFUSED — ambiguous folder(s): {}", unknown_names.join(", ")));
        return;
    }

    let sources: Vec<_> = classified.iter().filter(|(_, _, s, _, _, _)| *s == SaveState::HasSaveData).collect();
    let targets: Vec<_> = classified.iter().filter(|(_, _, s, _, _, _)| *s == SaveState::FreshInstall).collect();

    if sources.is_empty() || targets.is_empty() { return; }

    // Rank sources: save_count DESC → save_bytes DESC → mtime DESC → name ASC
    let source = sources.iter().max_by(|a, b| {
        a.3.cmp(&b.3)              // save_count: more = better
            .then_with(|| a.4.cmp(&b.4))  // save_bytes: more = better
            .then_with(|| a.5.cmp(&b.5))  // mtime: newer = better
    }).unwrap();

    for (_, tgt_name, _, _, _, _) in &targets {
        let target = parent.join(tgt_name);
        copy_dir_merge(source.0, &target);
        let msg = format!("{}: {} → {}", parent.file_name()
            .map(|n| n.to_string_lossy().to_string()).unwrap_or_default(), source.1, tgt_name);
        migrations.push(msg);
    }
}

/// Three-state classification: HasSaveData / FreshInstall / Unknown.
/// If ANY folder in a group is Unknown → refuse migration entirely (conservative).
#[derive(Clone, Copy, PartialEq)]
enum SaveState {
    HasSaveData,
    FreshInstall,
    Unknown,
}

/// Score a folder for save data presence. Returns (state, save_file_count, save_bytes, mtime).
/// Score >= 100 = HasSaveData, score == 0 = FreshInstall, 0 < score < 100 = Unknown.
fn classify_folder(dir: &Path) -> (SaveState, usize, u64, std::time::SystemTime) {
    let mut score = 0i32;

    // STRONG signal (+100): recognized save directory with files
    let save_dirs = ["savedata", "save", "saves", "SaveGames", "SaveData",
                     "remote", "profiles", "slot", "slots",
                     "saved games", "savegame", "saved"];
    for sd in &save_dirs {
        let p = dir.join(sd);
        if p.is_dir() && dir_has_files_recursive(&p) {
            score += 100;
            break;
        }
    }

    // STRONG signal (+100): userdata/<userID>/<appID>/remote pattern (depth 2)
    if score < 100 {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    let remote = entry.path().join("remote");
                    if remote.is_dir() && dir_has_files_recursive(&remote) {
                        score += 100;
                        break;
                    }
                }
            }
        }
    }

    // MEDIUM signal (+50): specific save filenames anywhere in tree
    // (SAVEFILE*, autosave*, checkpoint* — these are strong save names)
    if score < 100 && has_specific_save_names(dir) {
        score += 50;
    }

    // WEAK signal (+30): save extensions (*.sav, *.save, *.slot)
    if score < 100 && has_save_extensions(dir) {
        score += 30;
    }

    // WEAK signal (+20): 6+ files with no recognized patterns (might be unrecognized format)
    if score == 0 {
        let (total_files, _) = count_files_recursive(dir);
        if total_files >= 6 {
            score += 20;
        }
    }

    let state = if score >= 100 {
        SaveState::HasSaveData
    } else if score == 0 {
        SaveState::FreshInstall
    } else {
        SaveState::Unknown
    };

    let (save_count, save_bytes, mtime) = compute_save_stats(dir);
    (state, save_count, save_bytes, mtime)
}

/// Check for specific save filenames (SAVEFILE*, autosave*, checkpoint*).
fn has_specific_save_names(dir: &Path) -> bool {
    fn check(d: &Path) -> bool {
        if let Ok(entries) = std::fs::read_dir(d) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    if check(&path) { return true; }
                } else {
                    let name = entry.file_name().to_string_lossy().to_lowercase();
                    if name.starts_with("savefile")
                        || name.starts_with("autosave")
                        || name.starts_with("checkpoint") {
                        return true;
                    }
                }
            }
        }
        false
    }
    check(dir)
}

/// Check for save extensions (*.sav, *.save, *.slot).
fn has_save_extensions(dir: &Path) -> bool {
    fn check(d: &Path) -> bool {
        if let Ok(entries) = std::fs::read_dir(d) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    if check(&path) { return true; }
                } else {
                    let name = entry.file_name().to_string_lossy().to_lowercase();
                    if name.ends_with(".sav")
                        || name.ends_with(".save")
                        || name.ends_with(".slot") {
                        return true;
                    }
                }
            }
        }
        false
    }
    check(dir)
}

/// Compute total file count, total bytes, and newest mtime for ranking.
fn compute_save_stats(dir: &Path) -> (usize, u64, std::time::SystemTime) {
    let mut count = 0usize;
    let mut bytes = 0u64;
    let mut newest = std::time::UNIX_EPOCH;
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                let (c, b, m) = compute_save_stats(&path);
                count += c;
                bytes += b;
                if m > newest { newest = m; }
            } else {
                count += 1;
                if let Ok(meta) = entry.metadata() {
                    bytes += meta.len();
                    if let Ok(m) = meta.modified() {
                        if m > newest { newest = m; }
                    }
                }
            }
        }
    }
    (count, bytes, newest)
}

fn dir_has_files_recursive(dir: &Path) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if dir_has_files_recursive(&path) { return true; }
            } else {
                return true; // Found at least one file
            }
        }
    }
    false
}

fn count_files_recursive(dir: &Path) -> (usize, std::time::SystemTime) {
    let mut count = 0usize;
    let mut newest = std::time::UNIX_EPOCH;
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                let (sub_count, sub_mtime) = count_files_recursive(&path);
                count += sub_count;
                if sub_mtime > newest { newest = sub_mtime; }
            } else {
                count += 1;
                if let Ok(m) = entry.metadata().and_then(|m| m.modified()) {
                    if m > newest { newest = m; }
                }
            }
        }
    }
    (count, newest)
}

fn copy_dir_merge(source: &Path, target: &Path) {
    if let Ok(entries) = std::fs::read_dir(source) {
        for entry in entries.flatten() {
            let src_path = entry.path();
            let name = entry.file_name();
            let tgt_path = target.join(&name);

            if src_path.is_dir() {
                if !tgt_path.exists() {
                    let _ = std::fs::create_dir_all(&tgt_path);
                }
                copy_dir_merge(&src_path, &tgt_path);
            } else {
                // Never overwrite — preserves game's fresh screeninfo.cfg etc.
                if !tgt_path.exists() {
                    let _ = std::fs::copy(&src_path, &tgt_path);
                }
            }
        }
    }
}
