use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

pub fn log_path() -> PathBuf {
    crate::config::script_dir().join("sync.log")
}

pub fn timestamp() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs()).unwrap_or(0);
    let days = (secs / 86400) as i64;
    let rem = secs % 86400;
    let h = (rem / 3600) as u32;
    let mi = ((rem % 3600) / 60) as u32;
    let s = (rem % 60) as u32;
    let mut y = 1970i64;
    let mut d = days;
    loop {
        let dy = if (y%4==0 && y%100!=0) || y%400==0 {366} else {365};
        if d < dy { break; }
        d -= dy;
        y += 1;
    }
    let months = [31, if (y%4==0&&y%100!=0)||y%400==0 {29} else {28}, 31,30,31,30,31,31,30,31,30,31];
    let mut mo = 0;
    for &dm in &months { if d < dm { break; } d -= dm; mo += 1; }
    format!("{:04}-{:02}-{:02} {:02}:{:02}:{:02}", y, mo+1, d+1, h, mi, s)
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
