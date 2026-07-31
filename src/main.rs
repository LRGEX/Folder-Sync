#![windows_subsystem = "windows"]
mod config;
mod sync;
mod synclog;
mod health;
mod gui;
mod update;

fn main() {
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
    if sync_mode { config::ensure_versions_setup(); sync::sync_all_pairs(); return; }
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
        cfg.junctions.push(config::Junction { source_path: link_path.clone(), auto_restore: true, created: synclog::timestamp() });
        config::save_config(&cfg);
        let (ok, _) = sync::sync_pair_to_cloud(&link_path, &cfg.excluded_names, cfg.trash_retention_days);
        if ok { crate::health::write_status(1, 0, 0, &[]); }
        return;
    }
    gui::run();
}
