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

/// Check for updates. Called on app launch (delayed).
/// Silently skips on network error — never blocks the user.
pub fn check_for_updates() {
    let current = env!("CARGO_PKG_VERSION");

    // Fetch manifest
    let response = match ureq::get(MANIFEST_URL).timeout(std::time::Duration::from_secs(10)).call() {
        Ok(r) => r,
        Err(_) => return, // network error — silently skip
    };

    let manifest: Manifest = match response.into_json() {
        Ok(m) => m,
        Err(_) => return,
    };

    // Compare versions
    if !is_newer(&manifest.version, current) {
        return; // up to date
    }

    // Show update dialog
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

    // Download new exe to temp
    let temp_exe = std::env::temp_dir().join("folder_sync_update.exe");

    let resp = match ureq::get(&manifest.platforms.windows.url).call() {
        Ok(r) => r,
        Err(e) => {
            show_error(&format!("Download failed: {}", e));
            return;
        }
    };

    let mut reader = resp.into_reader();
    let mut data = Vec::new();
    if reader.read_to_end(&mut data).is_err() {
        show_error("Failed to read download data.");
        return;
    }

    if std::fs::write(&temp_exe, &data).is_err() {
        show_error("Failed to save update file.");
        return;
    }

    // Swap the running exe
    match self_replace::self_replace(&temp_exe) {
        Ok(_) => {
            // Cleanup temp file (best effort)
            let _ = std::fs::remove_file(&temp_exe);
            // Relaunch the new exe before exiting
            let exe = std::env::current_exe().unwrap_or_default();
            let _ = std::process::Command::new(&exe).spawn();
            std::process::exit(0);
        }
        Err(e) => {
            show_error(&format!("Failed to replace executable: {}", e));
        }
    }
}

fn show_error(msg: &str) {
    rfd::MessageDialog::new()
        .set_title("Update Failed")
        .set_description(msg)
        .set_buttons(rfd::MessageButtons::Ok)
        .show();
}

/// Compare semantic versions: returns true if remote > current
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
