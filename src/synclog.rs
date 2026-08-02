use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

pub fn log_path() -> PathBuf {
    crate::config::data_dir().join("sync.log")
}

pub fn timestamp() -> String {
    use chrono::Local;
    Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

pub fn write(msg: &str) {
    let path = log_path();
    let line = format!("{} {}\r\n", timestamp(), msg);
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&path) {
        let _ = f.write_all(line.as_bytes());
    }
    if let Ok(data) = std::fs::read_to_string(&path) {
        let lines: Vec<&str> = data.lines().collect();
        if lines.len() > 2050 {
            let trimmed = lines[lines.len()-2000..].join("\r\n");
            let _ = std::fs::write(&path, trimmed);
        }
    }
}

pub fn write_progress(msg: &str) {
    let path = crate::config::data_dir().join("sync-progress.txt");
    let pid = std::process::id();
    let line = format!("{}|{}", pid, msg);
    let _ = std::fs::write(&path, line);
}

pub fn read_progress() -> String {
    let raw = std::fs::read_to_string(crate::config::data_dir().join("sync-progress.txt"))
        .unwrap_or_default();
    let raw = raw.trim();
    if raw.is_empty() { return String::new(); }

    // Format: PID|message — check BOTH PID liveness AND file mtime (PID reuse backstop)
    if let Some((pid_str, msg)) = raw.split_once('|') {
        if let Ok(pid) = pid_str.parse::<u32>() {
            let path = crate::config::data_dir().join("sync-progress.txt");
            // mtime backstop: clear if file untouched >10 min (defeats PID reuse)
            let stale = std::fs::metadata(&path)
                .ok()
                .and_then(|m| m.modified().ok())
                .map(|t| t.elapsed().unwrap_or_default().as_secs() > 600)
                .unwrap_or(true);
            if stale {
                let _ = std::fs::write(&path, "");
                return String::new();
            }
            if is_pid_alive(pid) {
                return msg.to_string();
            } else {
                let _ = std::fs::write(&path, "");
                return String::new();
            }
        }
    }
    String::new()
}

pub fn is_pid_alive(pid: u32) -> bool {
    use windows_sys::Win32::System::Threading::{OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION};
    use windows_sys::Win32::Foundation::CloseHandle;
    unsafe {
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if handle.is_null() { return false; }
        CloseHandle(handle);
        true
    }
}

pub fn read_tail(n: usize) -> String {
    match std::fs::read_to_string(log_path()) {
        Ok(data) => {
            let lines: Vec<&str> = data.lines().collect();
            let start = if lines.len() > n { lines.len() - n } else { 0 };
            lines[start..].join("\r\n")
        }
        Err(_) => "No sync log yet.".into(),
    }
}
