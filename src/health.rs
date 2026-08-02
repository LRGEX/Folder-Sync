use serde::{Serialize, Deserialize};
use std::path::PathBuf;
use std::os::windows::process::CommandExt;

#[derive(Serialize, Deserialize)]
pub struct SyncStatus {
    pub last_sync: String,
    pub ok: i32,
    pub fail: i32,
    pub restored: i32,
    pub restored_names: String,
}

pub struct HealthResult {
    pub status: String,
    pub label: String,
    pub reason: String,
}

pub fn status_path() -> PathBuf {
    crate::config::data_dir().join("sync-status.json")
}

pub fn write_status(ok: i32, fail: i32, restored: i32, names: &[String]) {
    let s = SyncStatus {
        last_sync: crate::synclog::timestamp(),
        ok, fail, restored,
        restored_names: names.join(", "),
    };
    if let Ok(data) = serde_json::to_string(&s) {
        let _ = std::fs::write(status_path(), data);
    }
}

pub fn task_exists() -> bool {
    let output = std::process::Command::new("schtasks.exe")
        .args(&["/Query", "/TN", "LRGEX-FolderSync-Rust", "/FO", "LIST"])
        .creation_flags(0x08000000u32)
        .output();
    match output {
        Ok(out) => out.status.success(),
        Err(_) => false,
    }
}

/// Is the task currently running?
fn task_running() -> bool {
    let output = std::process::Command::new("schtasks.exe")
        .args(&["/Query", "/TN", "LRGEX-FolderSync-Rust", "/FO", "LIST", "/V"])
        .creation_flags(0x08000000u32)
        .output();
    if let Ok(out) = output {
        if !out.status.success() { return false; }
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            let t = line.trim();
            if t.to_lowercase().starts_with("status:") {
                return t.contains("Running");
            }
        }
    }
    false
}

pub fn get_health() -> HealthResult {
    // 1. Task not registered = RED (sync will not run automatically)
    if !task_exists() {
        return HealthResult {
            status: "RED".into(),
            label: "SYNC OFF".into(),
            reason: "Task not registered - it will be recreated on next launch".into(),
        };
    }

    // 2. Task running right now = AMBER
    if task_running() {
        return HealthResult {
            status: "AMBER".into(),
            label: "SYNCING".into(),
            reason: "Running now".into(),
        };
    }

    // 3. Read last sync status
    match std::fs::read_to_string(status_path()) {
        Ok(data) => {
            if let Ok(s) = serde_json::from_str::<SyncStatus>(&data) {
                if s.fail > 0 {
                    return HealthResult {
                        status: "RED".into(),
                        label: "SYNC HAD FAILURES".into(),
                        reason: format!("{} folder(s) failed", s.fail),
                    };
                }
                if s.restored > 0 {
                    return HealthResult {
                        status: "GREEN".into(),
                        label: format!("RESTORED {}", s.restored).into(),
                        reason: format!("auto-restored: {}", s.restored_names),
                    };
                }
                return HealthResult {
                    status: "GREEN".into(),
                    label: "SYNC OK".into(),
                    reason: format!("{} folder(s) OK - last: {}", s.ok, s.last_sync),
                };
            }
        }
        Err(_) => {}
    }

    // 4. Task registered but hasn't run yet = AMBER (not green!)
    HealthResult {
        status: "AMBER".into(),
        label: "WAITING".into(),
        reason: "Task registered, waiting for first sync cycle".into(),
    }
}
