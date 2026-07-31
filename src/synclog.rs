use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

pub fn log_path() -> PathBuf {
    crate::config::script_dir().join("sync.log")
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
    let path = crate::config::script_dir().join("sync-progress.txt");
    let _ = std::fs::write(&path, msg);
}

pub fn read_progress() -> String {
    std::fs::read_to_string(crate::config::script_dir().join("sync-progress.txt"))
        .unwrap_or_default()
        .trim()
        .to_string()
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
