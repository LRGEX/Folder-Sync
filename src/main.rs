#![windows_subsystem = "windows"]
mod config;
mod pathutil;
mod sync;
mod synclog;
mod health;
mod gui;
mod update;

fn main() {
    // Crash logger: write panic info to lrgex-crash.log next to the exe
    std::panic::set_hook(Box::new(|info| {
        let exe_dir = std::env::current_exe()
            .and_then(|e| e.parent().map(|p| p.to_path_buf()).ok_or(()).map_err(|_| std::io::Error::new(std::io::ErrorKind::Other, "")))
            .unwrap_or_else(|_| std::path::PathBuf::from("."));
        let crash_log = exe_dir.join("lrgex-crash.log");
        let msg = format!("{} CRASH: {}
", crate::synclog::timestamp(), info);
        let _ = std::fs::OpenOptions::new().create(true).append(true).open(&crash_log)
            .and_then(|mut f| std::io::Write::write_all(&mut f, msg.as_bytes()));
    }));
    // Force software renderer — works on VMs without GPU
    if std::env::var("SLINT_BACKEND").is_err() {
        std::env::set_var("SLINT_BACKEND", "software");
    }
    let args: Vec<String> = std::env::args().collect();
    let mut sync_mode = false;
    let mut auto_restore = false;
    let mut link_path = String::new();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-sync" => sync_mode = true,
            "-autorestore" => auto_restore = true,
            "-link" => { if i + 1 < args.len() { link_path = args[i + 1].clone(); i += 1; } }
            _ => {}
        }
        i += 1;
    }
    if sync_mode {
        // Mutex prevents concurrent sync processes from stacking up
        use windows_sys::Win32::System::Threading::CreateMutexW;
        use windows_sys::Win32::Foundation::GetLastError;
        use std::os::windows::ffi::OsStrExt;
        let sync_mutex: Vec<u16> = std::ffi::OsStr::new("LRGEXSyncSyncLock")
            .encode_wide().chain(std::iter::once(0)).collect();
        unsafe {
            let handle = CreateMutexW(std::ptr::null(), 0, sync_mutex.as_ptr());
            if GetLastError() == 183 {
                return; // Another sync is already running — exit silently
            }
            let _ = handle; // keep mutex alive
        }
        config::ensure_versions_setup();
        sync::sync_all_pairs();
        return;
    }
    if auto_restore {
        let cfg = config::load_config();
        for j in &cfg.junctions {
            if !j.auto_restore { continue; }
            let p = std::path::Path::new(&j.source_path);
            if !p.exists() || sync::is_dir_empty(&j.source_path) { sync::restore_pair_from_cloud(&j.source_path); }
        }
        return;
    }
    if !link_path.is_empty() {
        // Confirm before syncing (prevents accidental right-click)
        let leaf = std::path::Path::new(&link_path)
            .file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        let confirm = rfd::MessageDialog::new()
            .set_title("Sync Folder")
            .set_description(&format!("Sync '{}' to your backup?", leaf))
            .set_buttons(rfd::MessageButtons::YesNo)
            .show() == rfd::MessageDialogResult::Yes;
        if !confirm { return; }

        let mut cfg = config::load_config();
        cfg.junctions.retain(|j| j.source_path != link_path);
        cfg.junctions.push(config::Junction { source_path: link_path.clone(), auto_restore: true, created: synclog::timestamp(), is_game: false });
        config::save_config(&cfg);
        let (ok, reason) = sync::sync_pair_to_cloud(&link_path, &cfg.excluded_names, cfg.max_versions, true);
        if ok {
            crate::health::write_status(1, 0, 0, &[]);
            rfd::MessageDialog::new()
                .set_title("Sync Complete")
                .set_description(&format!("'{}' backed up successfully.", leaf))
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
        } else {
            rfd::MessageDialog::new()
                .set_title("Sync Failed")
                .set_description(&format!("Failed to back up '{}'.\n\nError: {}", leaf, reason))
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
        }
        return;
    }
    // Single instance — only for GUI mode (not -sync, -link, -autorestore)
    use windows_sys::Win32::System::Threading::CreateMutexW;
    use windows_sys::Win32::Foundation::GetLastError;
    use std::os::windows::ffi::OsStrExt;
    let mutex_name: Vec<u16> = std::ffi::OsStr::new("LRGEXSyncSingleInstance")
        .encode_wide().chain(std::iter::once(0)).collect();
    unsafe {
        let handle = CreateMutexW(std::ptr::null(), 0, mutex_name.as_ptr());
        if GetLastError() == 183 { // ERROR_ALREADY_EXISTS
            return; // Another GUI instance is running — exit silently
        }
        let _ = handle; // keep mutex alive
    }

    gui::run();
}
