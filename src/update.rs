use serde::Deserialize;
use std::io::Read;
use ed25519_dalek::{VerifyingKey, Verifier, Signature};

const MANIFEST_URL: &str = "https://download.lrgex.com/app/rst/folder-sync/latest.json";

// Public key baked into the binary — generated on dev PC, private key never leaves.
// Attacker cannot forge updates without the private key, even with full server access.
const UPDATE_PUBKEY_HEX: &str = "8f4e8831f8038819b4473644a7992b6ee825e562bc9cdb33b15af4ddb849f375";

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
    signature: Option<String>,
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

    let temp_exe = std::env::temp_dir().join("folder_sync_update.exe");

    let resp = match ureq::get(&format!("{}?v={}", manifest.platforms.windows.url, manifest.version))
        .timeout(std::time::Duration::from_secs(120))
        .call() {
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

    // Verify Ed25519 signature against embedded public key
    if let Some(sig_hex) = &manifest.platforms.windows.signature {
        if !sig_hex.is_empty() {
            match verify_signature(&data, sig_hex) {
                Ok(()) => {} // Verified — proceed
                Err(e) => {
                    show_error(&format!(
                        "Signature verification FAILED.\n\n{}\n\nThe download may be corrupted or tampered with. Update aborted for your safety.",
                        e
                    ));
                    return;
                }
            }
        } else {
            // Signature field exists but is empty — reject for safety
            show_error("Signature is EMPTY in the manifest. Update aborted — cannot verify authenticity.");
            return;
        }
    } else {
        // No signature field at all — reject for safety
        show_error("No signature found in manifest. Update aborted — cannot verify authenticity.");
        return;
    }

    match std::fs::write(&temp_exe, &data) {
        Ok(_) => {}
        Err(e) => { show_error(&format!("Save failed: {}", e)); return; }
    }

    let bat_path = std::env::temp_dir().join("lrgex-updater.bat");
    let bat = format!(
        "@echo off\r\nping 127.0.0.1 -n 3 > nul\r\n:retry\r\ncopy /Y \"{}\" \"{}\" >nul 2>&1\r\nif errorlevel 1 (\r\n  ping 127.0.0.1 -n 3 > nul\r\n  goto retry\r\n)\r\ndel \"{}\" >nul 2>&1\r\nstart \"\" \"{}\"\r\ndel \"%~f0\"\r\n",
        temp_exe.to_string_lossy(),
        exe_path.to_string_lossy(),
        temp_exe.to_string_lossy(),
        exe_path.to_string_lossy()
    );
    let _ = std::fs::write(&bat_path, bat);

    rfd::MessageDialog::new()
        .set_title("Updating")
        .set_description("Signature verified. The app will restart in a moment with the new version.")
        .set_buttons(rfd::MessageButtons::Ok)
        .show();

    use std::os::windows::process::CommandExt;
    let _ = std::process::Command::new("cmd.exe")
        .args(["/c", bat_path.to_str().unwrap_or("")])
        .creation_flags(0x08000000u32)
        .spawn();

    std::process::exit(0);
}

fn verify_signature(data: &[u8], sig_hex: &str) -> Result<(), String> {
    let pub_bytes = hex::decode(UPDATE_PUBKEY_HEX).map_err(|e| format!("Bad public key: {}", e))?;
    let mut pub_arr = [0u8; 32];
    pub_arr.copy_from_slice(&pub_bytes);
    let verifying_key = VerifyingKey::from_bytes(&pub_arr).map_err(|e| format!("Bad public key: {}", e))?;

    let sig_bytes = hex::decode(sig_hex).map_err(|e| format!("Bad signature format: {}", e))?;
    let mut sig_arr = [0u8; 64];
    sig_arr.copy_from_slice(&sig_bytes);
    let signature = Signature::from_bytes(&sig_arr);

    verifying_key.verify(data, &signature).map_err(|e| format!("Invalid signature: {}", e))
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
