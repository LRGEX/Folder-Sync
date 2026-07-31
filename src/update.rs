use serde::Deserialize;
use std::io::Read;

const MANIFEST_URL: &str = "https://download.lrgex.com/app/rst/folder-sync/latest.json";

#[derive(Deserialize)]
struct Manifest {
    version: String,
    platforms: Platforms,
}

#[derive(Deserialize)]
struct Platforms {
    #[serde(rename = "windows-x86_64")]
    windows: Platform,
}

#[derive(Deserialize)]
struct Platform {
    url: String,
}

pub fn check_for_updates() {
    let current = env!("CARGO_PKG_VERSION");
    let exe_path = std::env::current_exe().unwrap_or_default();

    let response = match ureq::get(MANIFEST_URL).timeout(std::time::Duration::from_secs(10)).call() {
        Ok(r) => r,
        Err(_) => return,
    };

    let manifest: Manifest = match response.into_json() {
        Ok(m) => m,
        Err(_) => return,
    };

    if !is_newer(&manifest.version, current) {
        return;
    }

    let confirm = rfd::MessageDialog::new()
        .set_title("Update Available")
        .set_description(&format!(
            "Version {} is available (you have v{}).\n\nUpdate now?",
            manifest.version, current
        ))
        .set_buttons(rfd::MessageButtons::YesNo)
        .show();

    if confirm != rfd::MessageDialogResult::Yes {
        return;
    }

    // Download
    let temp_exe = std::env::temp_dir().join("folder_sync_update.exe");

    let resp = match ureq::get(&format!("{}?v={}", manifest.platforms.windows.url, manifest.version)).call() {
        Ok(r) => r,
        Err(e) => { show_error(&format!("Download failed: {}", e)); return; }
    };

    let mut reader = resp.into_reader();
    let mut data = Vec::new();
    match reader.read_to_end(&mut data) {
        Ok(_) => {}
        Err(e) => { show_error(&format!("Read failed: {}", e)); return; }
    }

    if data.len() < 1_000_000 {
        show_error(&format!("Downloaded file too small: {} bytes.", data.len()));
        return;
    }

    match std::fs::write(&temp_exe, &data) {
        Ok(_) => {}
        Err(e) => { show_error(&format!("Save failed: {}", e)); return; }
    }

    // Write updater batch — copies new exe AFTER app exits (OneDrive-safe)
    let bat_path = std::env::temp_dir().join("lrgex-updater.bat");
    let bat = format!(
        "@echo off\r\nping 127.0.0.1 -n 3 > nul\r\n:retry\r\ncopy /Y \"{}\" \"{}\" >nul 2>&1\r\nif errorlevel 1 (\r\n  ping 127.0.0.1 -n 3 > nul\r\n  goto retry\r\n)\r\ndel \"{}\" >nul 2>&1\r\nstart \"\" \"{}\"\r\ndel \"%~f0\"\r\n",
        temp_exe.to_string_lossy(),
        exe_path.to_string_lossy(),
        temp_exe.to_string_lossy(),
        exe_path.to_string_lossy()
    );
    let _ = std::fs::write(&bat_path, bat);

    // Show confirmation
    rfd::MessageDialog::new()
        .set_title("Updating")
        .set_description("The app will restart in a moment with the new version.")
        .set_buttons(rfd::MessageButtons::Ok)
        .show();

    // Launch updater batch detached, then exit
    use std::os::windows::process::CommandExt;
    let _ = std::process::Command::new("cmd.exe")
        .args(["/c", bat_path.to_str().unwrap_or("")])
        .creation_flags(0x08000000u32)
        .spawn();

    std::process::exit(0);
}

fn show_error(msg: &str) {
    rfd::MessageDialog::new()
        .set_title("Update Failed")
        .set_description(msg)
        .set_buttons(rfd::MessageButtons::Ok)
        .show();
}

fn is_newer(remote: &str, current: &str) -> bool {
    let parse = |s: &str| -> Vec<u32> {
        s.split('.').filter_map(|n| n.parse().ok()).collect()
    };
    let r = parse(remote);
    let c = parse(current);
    for i in 0..r.len().max(c.len()) {
        let rv = r.get(i).copied().unwrap_or(0);
        let cv = c.get(i).copied().unwrap_or(0);
        if rv > cv { return true; }
        if rv < cv { return false; }
    }
    false
}
