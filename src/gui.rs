use std::os::windows::process::CommandExt;
slint::slint! {
    import { Button, LineEdit, VerticalBox, HorizontalBox, ScrollView } from "std-widgets.slint";

    export struct FolderEntry {
        path: string,
        auto_restore: string,
    }

    export struct VersionEntry {
        display: string,
    }

    component MenuItem inherits Rectangle {
        in property <string> label;
        callback clicked();
        height: 30px;
        background: ta.has-hover ? #282828 : transparent;
        Text {
            text: label;
            color: #f0f0f0;
            vertical-alignment: center;
        }
        ta := TouchArea {
            clicked => { root.clicked(); }
        }
    }

    export component App inherits Window {
        title: "LRGEX Folder Sync " + root.app-version;
        icon: @image-url("../assets/app-icon.png");
        preferred-width: 560px;
        preferred-height: 700px;
        background: #1e1e1e;

        in-out property <string> health-text: " Checking...";
        in-out property <color> health-color: #4caf50;
        in-out property <string> status-text: "";
        in-out property <string> source-text: "";
        in-out property <[FolderEntry]> folders: [];
        in-out property <string> rc-label: "Right-Click Sync: OFF";
        in-out property <bool> menu-open: false;
        in-out property <int> selected-index: -1;
        in-out property <bool> versions-visible: false;
        in-out property <[VersionEntry]> versions-list: [];
        in-out property <int> selected-version: -1;
        in-out property <string> app-version: "";
        in-out property <string> versions-title: "Versions";

        callback browse-clicked();
        callback link-clicked();
        callback restore-clicked();
        callback toggle-clicked();
        callback remove-clicked();
        callback log-clicked();
        callback rightclick-clicked();
        callback health-clicked();
        callback export-clicked();
        callback import-clicked();
        callback interval-clicked();
        callback exclusions-clicked();
        callback uninstall-clicked();
        callback versions-clicked(int);
        callback restore-version();
        callback close-versions();

        VerticalBox {
            spacing: 8px;

            // Tools menu bar
            HorizontalLayout {
                height: 32px;
                spacing: 0px;
                Rectangle {
                    width: 72px;
                    height: 30px;
                    background: root.menu-open ? #cb803c : #2d2d2d;
                    Text {
                        text: "Tools";
                        color: root.menu-open ? white : #f0f0f0;
                        horizontal-alignment: center;
                        vertical-alignment: center;
                        font-weight: 700;
                    }
                    TouchArea { clicked => { root.menu-open = !root.menu-open; } }
                }
            }

            // Logo (centered, smaller)
            HorizontalLayout {
                alignment: center;
                Image { source: @image-url("../assets/logo.png"); width: 240px; height: 50px; image-fit: contain; }
            }
            HorizontalLayout {
                alignment: center;
                Text { text: "Folder Sync"; font-size: 24px; font-weight: 900; color: #b3b3b3; letter-spacing: 1px; }
            }
            HorizontalLayout {
                alignment: center;
                Text { text: "v" + root.app-version; font-size: 11px; color: #888; }
            }

            // Health lamp
            Rectangle {
                height: 28px;
                background: root.health-color;
                Text {
                    text: root.health-text;
                    color: white;
                    font-weight: 700;
                    vertical-alignment: center;
                }
            }

            // Source input
            HorizontalBox {
                spacing: 6px;
                LineEdit {
                    placeholder-text: "Folder to backup...";
                    text <=> root.source-text;
                    width: 440px;
                }
                Button { text: "Browse"; clicked => { root.browse-clicked(); } }
            }

            // Backed up folders list (right under source input, shows full paths)
            Text { text: "Backed up folders:"; color: #aaa; font-size: 12px; }
            ScrollView {
                height: 200px;
                VerticalBox {
                    for entry[i] in root.folders : Rectangle {
                        height: 28px;
                        background: i == root.selected-index ? #2d2d2d : #252525;
                        // Left accent bar (orange when selected, invisible otherwise)
                        Rectangle {
                            x: 0px;
                            width: 3px;
                            height: parent.height;
                            background: i == root.selected-index ? #cb803c : transparent;
                        }
                        TouchArea { clicked => { root.selected-index = i; root.source-text = entry.path; } }
                        HorizontalLayout {
                            Text {
                                text: entry.path;
                                color: i == root.selected-index ? #cb803c : #f0f0f0;
                                vertical-alignment: center;
                                horizontal-stretch: 1;
                                overflow: elide;
                            }
                            Text {
                                text: entry.auto_restore;
                                color: entry.auto_restore == "ON" ? #4caf50 : #888;
                                vertical-alignment: center;
                                width: 30px;
                                horizontal-alignment: center;
                            }
                            Rectangle {
                                width: 68px;
                                height: 20px;
                                y: 4px;
                                background: vbtn.has-hover ? #3a3a3a : #2d2d2d;
                                border-radius: 3px;
                                Text { text: "Versions"; color: #cb803c; font-size: 10px; horizontal-alignment: center; vertical-alignment: center; }
                                vbtn := TouchArea { clicked => { root.versions-clicked(i); } }
                            }
                        }
                    }
                }
            }

            // Action buttons (at the bottom — all equal width)
            HorizontalBox {
                spacing: 8px;
                Button { text: "Backup Folder"; horizontal-stretch: 1; min-width: 250px; clicked => { root.link-clicked(); } }
                Button { text: "Restore Saved"; horizontal-stretch: 1; min-width: 250px; clicked => { root.restore-clicked(); } }
            }
            HorizontalBox {
                spacing: 8px;
                Button { text: "Toggle Auto-Restore"; horizontal-stretch: 1; min-width: 250px; clicked => { root.toggle-clicked(); } }
                Button { text: "Remove"; horizontal-stretch: 1; min-width: 250px; clicked => { root.remove-clicked(); } }
            }

            Text { text: root.status-text; color: #cb803c; font-size: 12px; height: 28px; }
        }

        // Tools dropdown overlay
        if root.menu-open : Rectangle {
            x: 0px;
            y: 0px;
            width: root.width;
            height: root.height;
            background: transparent;
            TouchArea { clicked => { root.menu-open = false; } }

            Rectangle {
                x: 8px;
                y: 40px;
                width: 240px;
                height: 308px;
                background: #191919;
                border-radius: 4px;
                border-width: 1px;
                border-color: #3a3a3a;

                VerticalLayout {
                    MenuItem {
                        label: "Junction Health Check";
                        clicked => { root.health-clicked(); root.menu-open = false; }
                    }
                    Rectangle { height: 1px; background: #3a3a3a; }
                    MenuItem {
                        label: "Export Configuration";
                        clicked => { root.export-clicked(); root.menu-open = false; }
                    }
                    MenuItem {
                        label: "Import Configuration";
                        clicked => { root.import-clicked(); root.menu-open = false; }
                    }
                    Rectangle { height: 1px; background: #3a3a3a; }
                    MenuItem {
                        label: root.rc-label;
                        clicked => { root.rightclick-clicked(); root.menu-open = false; }
                    }
                    Rectangle { height: 1px; background: #3a3a3a; }
                    MenuItem {
                        label: "View Sync Log";
                        clicked => { root.log-clicked(); root.menu-open = false; }
                    }
                    MenuItem {
                        label: "Set Sync Interval...";
                        clicked => { root.interval-clicked(); root.menu-open = false; }
                    }
                    MenuItem {
                        label: "Manage Exclusions...";
                        clicked => { root.exclusions-clicked(); root.menu-open = false; }
                    }
                    Rectangle { height: 1px; background: #3a3a3a; }
                    MenuItem {
                        label: "Uninstall";
                        clicked => { root.uninstall-clicked(); root.menu-open = false; }
                    }
                }
            }
        }

        // Versions overlay panel
        if root.versions-visible : Rectangle {
            x: 0px;
            y: 0px;
            width: root.width;
            height: root.height;
            background: rgba(0, 0, 0, 0.75);

            Rectangle {
                x: (root.width - self.width) / 2;
                y: (root.height - self.height) / 2;
                width: 360px;
                height: 420px;
                background: #1e1e1e;
                border-radius: 8px;
                border-width: 1px;
                border-color: #3a3a3a;

                VerticalLayout {
                    padding: 16px;
                    spacing: 8px;

                    Text {
                        text: root.versions-title;
                        font-size: 16px;
                        font-weight: 800;
                        color: #b3b3b3;
                        horizontal-alignment: center;
                    }

                    Rectangle { height: 1px; background: #3a3a3a; }

                    ScrollView {
                        vertical-stretch: 1;
                        VerticalLayout {
                            spacing: 2px;
                            for entry[i] in root.versions-list : Rectangle {
                                height: 30px;
                                background: i == root.selected-version ? #cb803c : (vta.has-hover ? #2d2d2d : transparent);
                                border-radius: 3px;
                                vta := TouchArea { clicked => { root.selected-version = i; } }
                                Text {
                                    text: entry.display;
                                    color: i == root.selected-version ? white : #f0f0f0;
                                    vertical-alignment: center;
                                }
                            }
                        }
                    }

                    HorizontalLayout {
                        spacing: 8px;
                        alignment: center;
                        Rectangle {
                            width: 100px; height: 30px;
                            background: rbtn.has-hover ? #d89554 : #cb803c;
                            border-radius: 4px;
                            Text { text: "Restore"; color: white; horizontal-alignment: center; vertical-alignment: center; font-weight: 700; }
                            rbtn := TouchArea { clicked => { root.restore-version(); } }
                        }
                        Rectangle {
                            width: 100px; height: 30px;
                            background: cbtn.has-hover ? #3a3a3a : #2d2d2d;
                            border-radius: 4px;
                            Text { text: "Close"; color: #f0f0f0; horizontal-alignment: center; vertical-alignment: center; }
                            cbtn := TouchArea { clicked => { root.close-versions(); } }
                        }
                    }
                }
            }
        }
    }
}

use slint::VecModel;
use crate::{config, sync, health, synclog};

pub fn run() {
    // First-run: relocate to home folder if needed
    if !config::is_home() {
        // Check if already installed elsewhere
        if health::task_exists() || config::canonical_home().is_some() {
            let existing = config::canonical_home()
                .map(|h| h.to_string_lossy().to_string())
                .unwrap_or_else(|| "an unknown location".to_string());
            rfd::MessageDialog::new()
                .set_title("Already Installed")
                .set_description(&format!("Folder Sync is already installed at:\n{}\n\nOpen it from there.\n\nTo move: Tools -> Uninstall first, then run this exe again.", existing))
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
            return;
        }
        setup_home();
        return;
    }

    // Migration: if canonical home not in registry yet, promote current home
    if config::canonical_home().is_none() {
        config::set_canonical_home(&config::script_dir());
    }

    // Verify: this exe IS the canonical home exe
    if let Some(canonical) = config::canonical_home() {
        if config::script_dir() != canonical {
            rfd::MessageDialog::new()
                .set_title("Wrong Copy")
                .set_description(&format!("This is not the installed copy.\n\nThe real installation is at:\n{}", canonical.display()))
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
            return;
        }
    }

    // Self-heal: register task using canonical home (never current_exe)
    config::cleanup_legacy_ps();
    let cfg0 = config::load_config();
    sync::register_sync_task(cfg0.sync_interval_minutes);
    config::ensure_versions_setup();

    let app = App::new().unwrap();
    app.set_app_version(env!("CARGO_PKG_VERSION").into());

    // Initial state
    refresh_folders(&app);
    let h = health::get_health();
    app.set_health_text(format!(" {} - {} ", h.label, h.reason).into());
    app.set_health_color(match h.status.as_str() {
        "GREEN" => slint::Color::from_rgb_u8(76, 175, 80),
        "AMBER" => slint::Color::from_rgb_u8(200, 140, 0),
        _ => slint::Color::from_rgb_u8(200, 30, 30),
    });
    update_rc_label(&app);

    // --- Browse ---
    {
        let w = app.as_weak();
        app.on_browse_clicked(move || {
            if let Some(folder) = rfd::FileDialog::new().pick_folder() {
                let p = folder.to_string_lossy().to_string();
                w.upgrade_in_event_loop(move |a| a.set_source_text(p.into())).ok();
            }
        });
    }

    // --- Backup Folder ---
    {
        let w = app.as_weak();
        app.on_link_clicked(move || {
            let a = match w.upgrade() { Some(a) => a, None => return };
                let path = a.get_source_text().to_string();
                if path.is_empty() || !std::path::Path::new(&path).exists() {
                    a.set_status_text("Invalid source folder.".into());
                    return;
                }
                let cfg = config::load_config();
                if cfg.junctions.iter().any(|j| j.source_path == path) {
                    let leaf_name = std::path::Path::new(&path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                    crate::synclog::write_progress(&format!("Compressing {}...", leaf_name));
                    let (ok, msg) = sync::sync_pair_to_cloud(&path, &cfg.excluded_names, cfg.trash_retention_days, true);
                    crate::synclog::write_progress("");
                    if ok { health::write_status(1, 0, 0, &[]); }
                    a.set_status_text(if ok { "Compressed.".into() } else { msg.into() });
                    return;
                }
                let leaf = std::path::Path::new(&path)
                    .file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                let ar = rfd::MessageDialog::new()
                    .set_title("Auto-Restore")
                    .set_description(&format!("Enable auto-restore for '{}'?", leaf))
                    .set_buttons(rfd::MessageButtons::YesNo)
                    .show() == rfd::MessageDialogResult::Yes;
                let mut c2 = config::load_config();
                c2.junctions.retain(|j| j.source_path != path);
                c2.junctions.push(config::Junction {
                    source_path: path.clone(), auto_restore: ar, created: synclog::timestamp(),
                });
                config::save_config(&c2);
                crate::synclog::write_progress(&format!("Compressing {}...", leaf));
                let (ok, msg) = sync::sync_pair_to_cloud(&path, &c2.excluded_names, c2.trash_retention_days, true);
                crate::synclog::write_progress("");
                if ok { health::write_status(1, 0, 0, &[]); }
                refresh_folders(&a);
                a.set_status_text(if ok { "Compressed.".into() } else { msg.into() });
        });
    }

    // --- Restore Saved ---
    {
        let w = app.as_weak();
        app.on_restore_clicked(move || {
            let count_cfg = config::load_config();
            if count_cfg.junctions.is_empty() { return; }
            let confirm = rfd::MessageDialog::new()
                .set_title("Confirm Restore")
                .set_description(&format!("Restore {} folder(s) from backup?\nThis will overwrite current files.", count_cfg.junctions.len()))
                .set_buttons(rfd::MessageButtons::YesNo)
                .show() == rfd::MessageDialogResult::Yes;
            if !confirm { return; }
            let mut count = 0;
            for j in &config::load_config().junctions {
                let (ok, _) = sync::restore_pair_from_cloud(&j.source_path);
                if ok { count += 1; }
            }
            let msg = format!("Restored {} folder(s).", count);
            rfd::MessageDialog::new()
                .set_title("Restore Complete")
                .set_description(&msg)
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
            w.upgrade_in_event_loop(move |a| a.set_status_text(msg.into())).ok();
        });
    }

    // --- Toggle Auto-Restore ---
    {
        let w = app.as_weak();
        app.on_toggle_clicked(move || {
            let a = match w.upgrade() { Some(a) => a, None => return };
                let idx = a.get_selected_index();
                if idx < 0 {
                    rfd::MessageDialog::new()
                        .set_title("Toggle")
                        .set_description("Select a folder from the list first.")
                        .set_buttons(rfd::MessageButtons::Ok)
                        .show();
                    return;
                }
                let mut cfg = config::load_config();
                let i = idx as usize;
                if i >= cfg.junctions.len() { return; }
                cfg.junctions[i].auto_restore = !cfg.junctions[i].auto_restore;
                let ar = cfg.junctions[i].auto_restore;
                config::save_config(&cfg);
                refresh_folders(&a);
                a.set_status_text(format!("Auto-restore {}.", if ar { "ON" } else { "OFF" }).into());
                a.set_selected_index(idx);
        });
    }

    // --- Remove (button + Tools menu) ---
    {
        let w = app.as_weak();
        app.on_remove_clicked(move || {
            let a = match w.upgrade() { Some(a) => a, None => return };
            let idx = a.get_selected_index();
            if idx < 0 {
                rfd::MessageDialog::new()
                    .set_title("Remove")
                    .set_description("Select a folder from the list first.")
                    .set_buttons(rfd::MessageButtons::Ok)
                    .show();
                return;
            }
            let mut cfg = config::load_config();
            let i = idx as usize;
            if i >= cfg.junctions.len() { return; }
            let name = std::path::Path::new(&cfg.junctions[i].source_path)
                .file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            let confirm = rfd::MessageDialog::new()
                .set_title("Confirm Remove")
                .set_description(&format!("Remove '{}' from sync list?", name))
                .set_buttons(rfd::MessageButtons::YesNo)
                .show() == rfd::MessageDialogResult::Yes;
            if !confirm { return; }
            cfg.junctions.remove(i);
            config::save_config(&cfg);
            a.set_selected_index(-1);
            refresh_folders(&a);
            rfd::MessageDialog::new()
                .set_title("Removed")
                .set_description(&format!("'{}' removed from sync list.", name))
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
        });
    }

    // --- View Sync Log ---
    app.on_log_clicked(|| {
        let log = synclog::read_tail(50);
        let display = if log.is_empty() { "No log entries yet.".to_string() } else { log };
        rfd::MessageDialog::new()
            .set_title("Sync Log (last 50 lines)")
            .set_description(&display)
            .set_buttons(rfd::MessageButtons::Ok)
            .show();
    });

    // --- Right-Click Sync Toggle ---
    {
        let w = app.as_weak();
        app.on_rightclick_clicked(move || {
            let enabled = is_rightclick_enabled();
            let new_state = !enabled;
            toggle_rightclick(new_state);
            rfd::MessageDialog::new()
                .set_title("Right-Click Sync")
                .set_description(if new_state {
                    "Right-click sync ENABLED. Right-click any folder to sync it."
                } else {
                    "Right-click sync removed."
                })
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
            w.upgrade_in_event_loop(|a| { update_rc_label(&a); }).ok();
        });
    }

    // --- Junction Health Check ---
    app.on_health_clicked(|| {
        let cfg = config::load_config();
        let total = cfg.junctions.len();
        if total == 0 {
            rfd::MessageDialog::new()
                .set_title("Junction Health Check")
                .set_description("No junctions configured yet.")
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
            return;
        }
        let mut details = String::new();
        let mut ok_count = 0;
        for j in &cfg.junctions {
            let leaf = std::path::Path::new(&j.source_path)
                .file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            let cloud = config::pair_cloud_path(&j.source_path);
            if cloud.exists() {
                ok_count += 1;
                details.push_str(&format!("\n  {} - OK", leaf));
            } else {
                details.push_str(&format!("\n  {} - MISSING", leaf));
            }
        }
        rfd::MessageDialog::new()
            .set_title("Junction Health Check")
            .set_description(&format!("{} of {} junctions healthy:{}", ok_count, total, details))
            .set_buttons(rfd::MessageButtons::Ok)
            .show();
    });

    // --- Export Configuration ---
    app.on_export_clicked(|| {
        let cfg = config::load_config();
        if let Some(path) = rfd::FileDialog::new()
            .set_file_name("folder-sync-config.json")
            .add_filter("JSON", &["json"])
            .save_file()
        {
            if let Ok(data) = serde_json::to_string_pretty(&cfg) {
                let _ = std::fs::write(&path, data);
                rfd::MessageDialog::new()
                    .set_title("Export Complete")
                    .set_description("Configuration exported successfully.")
                    .set_buttons(rfd::MessageButtons::Ok)
                    .show();
            }
        }
    });

    // --- Import Configuration ---
    {
        let w = app.as_weak();
        app.on_import_clicked(move || {
            if let Some(path) = rfd::FileDialog::new()
                .add_filter("JSON", &["json"])
                .pick_file()
            {
                if let Ok(raw) = std::fs::read_to_string(&path) {
                    let raw = raw.strip_prefix('\u{feff}').unwrap_or(&raw);
                    match serde_json::from_str::<config::Config>(raw) {
                        Ok(cfg) => {
                            config::save_config(&cfg);
                            w.upgrade_in_event_loop(|a| { refresh_folders(&a); }).ok();
                            rfd::MessageDialog::new()
                                .set_title("Import Complete")
                                .set_description("Configuration imported successfully.")
                                .set_buttons(rfd::MessageButtons::Ok)
                                .show();
                        }
                        Err(_) => {
                            rfd::MessageDialog::new()
                                .set_title("Import Failed")
                                .set_description("Could not read configuration file. Invalid format.")
                                .set_buttons(rfd::MessageButtons::Ok)
                                .show();
                        }
                    }
                }
            }
        });
    }

    // --- Set Sync Interval ---
    app.on_interval_clicked(|| {
        let cfg = config::load_config();
        let cur = cfg.sync_interval_minutes;
        if let Some(val) = ps_inputbox(
            &format!("Current interval: {} minutes. Enter new interval (1 or more):", cur),
            "Sync Interval",
            &cur.to_string(),
        ) {
            match val.trim().parse::<i32>() {
                Ok(mins) if mins >= 1 => {
                    let mut c2 = config::load_config();
                    c2.sync_interval_minutes = mins;
                    config::save_config(&c2);
                    sync::register_sync_task(mins);
                    rfd::MessageDialog::new()
                        .set_title("Sync Interval")
                        .set_description(&format!("Sync interval set to {} minute(s).", mins))
                        .set_buttons(rfd::MessageButtons::Ok)
                        .show();
                }
                _ => {
                    rfd::MessageDialog::new()
                        .set_title("Invalid Input")
                        .set_description("Enter a whole number of minutes (1 or more).")
                        .set_buttons(rfd::MessageButtons::Ok)
                        .show();
                }
            }
        }
    });

    // --- Manage Exclusions ---
    app.on_exclusions_clicked(|| {
        let cfg = config::load_config();
        let current = cfg.excluded_names.join(", ");
        let display = if current.is_empty() { "(none)".to_string() } else { current.clone() };
        if let Some(val) = ps_inputbox(
            &format!("Current: {}. Enter exclusion names (comma-separated), or clear to remove all:", display),
            "Manage Exclusions",
            &current,
        ) {
            let trimmed = val.trim();
            let mut c2 = config::load_config();
            c2.excluded_names = if trimmed.is_empty() {
                vec![]
            } else {
                trimmed.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect()
            };
            let result = if c2.excluded_names.is_empty() { "(none)".to_string() } else { c2.excluded_names.join(", ") };
            config::save_config(&c2);
            rfd::MessageDialog::new()
                .set_title("Exclusions Updated")
                .set_description(&format!("Exclusions: {}", result))
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
        }
    });

    // --- Versions (per folder) ---
    // Shared state for version restore (paths + source)
    let version_state: std::rc::Rc<std::cell::RefCell<(Vec<std::path::PathBuf>, String)>> =
        std::rc::Rc::new(std::cell::RefCell::new((vec![], String::new())));

    // --- Versions button: populate list + show panel ---
    {
        let w = app.as_weak();
        let vs = version_state.clone();
        app.on_versions_clicked(move |idx| {
            let a = match w.upgrade() { Some(a) => a, None => return };
            let cfg = config::load_config();
            let i = idx as usize;
            if i >= cfg.junctions.len() { return; }
            let source = cfg.junctions[i].source_path.clone();
            let leaf = std::path::Path::new(&source)
                .file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            let versions_folder = config::trash_path_for(&leaf);

            let mut snapshots: Vec<(String, std::path::PathBuf)> = vec![];
            if let Ok(entries) = std::fs::read_dir(&versions_folder) {
                for entry in entries.flatten() {
                    let name = entry.file_name().to_string_lossy().to_string();
                    if name.len() == 15 && entry.path().is_dir() {
                        let formatted = format!(
                            "{}-{}-{} {}:{}:{}",
                            &name[0..4], &name[4..6], &name[6..8],
                            &name[9..11], &name[11..13], &name[13..15]
                        );
                        snapshots.push((formatted, entry.path()));
                    }
                }
            }
            snapshots.sort_by(|a, b| b.0.cmp(&a.0)); // newest first

            if snapshots.is_empty() {
                rfd::MessageDialog::new()
                    .set_title("Versions")
                    .set_description("No versions saved for this folder yet.")
                    .set_buttons(rfd::MessageButtons::Ok)
                    .show();
                return;
            }

            // Store paths + source in shared state
            let paths: Vec<std::path::PathBuf> = snapshots.iter().map(|(_, p)| p.clone()).collect();
            *vs.borrow_mut() = (paths, source);

            // Populate Slint model
            let model = slint::VecModel::from_iter(
                snapshots.iter().map(|(display, _)| VersionEntry { display: display.clone().into() })
            );
            a.set_versions_title(format!("Versions ({})", leaf).into());
            a.set_versions_list(slint::ModelRc::new(model));
            a.set_selected_version(-1);
            a.set_versions_visible(true);
        });
    }

    // --- Restore selected version ---
    {
        let w = app.as_weak();
        let vs = version_state.clone();
        app.on_restore_version(move || {
            let a = match w.upgrade() { Some(a) => a, None => return };
            let idx = a.get_selected_version();
            if idx < 0 {
                rfd::MessageDialog::new()
                    .set_title("Restore")
                    .set_description("Select a version first.")
                    .set_buttons(rfd::MessageButtons::Ok)
                    .show();
                return;
            }
            let (paths, source) = vs.borrow().clone();
            let i = idx as usize;
            if i >= paths.len() { return; }

            let confirm = rfd::MessageDialog::new()
                .set_title("Confirm Restore")
                .set_description("Restore entire folder from this version?\nThis will overwrite current files.")
                .set_buttons(rfd::MessageButtons::YesNo)
                .show() == rfd::MessageDialogResult::Yes;
            if !confirm { return; }

            let (ok, msg) = sync::restore_snapshot(&paths[i], &source);
            a.set_versions_visible(false);
            rfd::MessageDialog::new()
                .set_title(if ok { "Restored" } else { "Restore Failed" })
                .set_description(if ok { "Folder restored successfully.".into() } else { format!("Error: {}", msg) })
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
        });
    }

    // --- Close versions panel ---
    {
        let w = app.as_weak();
        app.on_close_versions(move || {
            if let Some(a) = w.upgrade() {
                a.set_versions_visible(false);
            }
        });
    }

    // Shared cache for last health result (avoids schtasks on every 3s tick)
    let health_cache: std::rc::Rc<std::cell::RefCell<(slint::SharedString, slint::Color)>> =
        std::rc::Rc::new(std::cell::RefCell::new((" Checking...".into(), slint::Color::from_rgb_u8(76, 175, 80))));

    // Fast progress check every 3 seconds (just reads a file — no process spawn)
    let progress_timer = slint::Timer::default();
    {
        let w = app.as_weak();
        let cache = health_cache.clone();
        progress_timer.start(slint::TimerMode::Repeated, std::time::Duration::from_secs(3), move || {
            let progress = synclog::read_progress();
            if let Some(a) = w.upgrade() {
                if !progress.is_empty() {
                    a.set_health_text(format!(" {} ", progress).into());
                    a.set_health_color(slint::Color::from_rgb_u8(200, 140, 0));
                } else {
                    let cached = cache.borrow();
                    a.set_health_text(cached.0.clone());
                    a.set_health_color(cached.1);
                }
            }
        });
    }

    // Periodic full health refresh every 30 seconds
    let health_timer = slint::Timer::default();
    {
        let w = app.as_weak();
        let cache = health_cache.clone();
        health_timer.start(slint::TimerMode::Repeated, std::time::Duration::from_secs(30), move || {
            let h = health::get_health();
            let text: slint::SharedString = format!(" {} - {} ", h.label, h.reason).into();
            let color = match h.status.as_str() {
                "GREEN" => slint::Color::from_rgb_u8(76, 175, 80),
                "AMBER" => slint::Color::from_rgb_u8(200, 140, 0),
                _ => slint::Color::from_rgb_u8(200, 30, 30),
            };
            *cache.borrow_mut() = (text.clone(), color);
            if let Some(a) = w.upgrade() {
                a.set_health_text(text);
                a.set_health_color(color);
            }
        });
    }

    // Check for updates 2 seconds after launch (one-shot)
    let update_timer = slint::Timer::default();
    update_timer.start(slint::TimerMode::SingleShot, std::time::Duration::from_secs(2), || {
        crate::update::check_for_updates();
    });

    // --- Uninstall ---
    app.on_uninstall_clicked(|| {
        let input = ps_inputbox(
            "Type 'yes' to uninstall.\n\nThis removes the scheduled task, right-click menu, and home marker.\nYour backup files will NOT be deleted.",
            "Uninstall",
            ""
        );
        let has_input = input.is_some();
        let confirmed = input
            .map(|s| s.trim().eq_ignore_ascii_case("yes"))
            .unwrap_or(false);
        if !confirmed {
            if has_input {
                rfd::MessageDialog::new()
                    .set_title("Uninstall")
                    .set_description("Cancelled.")
                    .set_buttons(rfd::MessageButtons::Ok)
                    .show();
            }
            return;
        }

        // Remove home marker + canonical home from registry
        let _ = std::fs::remove_file(config::script_dir().join(".lrgex-home"));
        config::clear_canonical_home();

        // Write cleanup batch to temp (waits for app exit, then cleans up)
        let bat_path = std::env::temp_dir().join("lrgex-cleanup.bat");
        let bat = "@echo off\r\nping 127.0.0.1 -n 3 > nul\r\nschtasks /Delete /TN \"LRGEX-FolderSync-Rust\" /F >nul 2>&1\r\nreg delete \"HKCU\\Software\\Classes\\Directory\\shell\\LRGEXSync\" /f >nul 2>&1\r\ndel \"%~f0\"\r\n";
        let _ = std::fs::write(&bat_path, bat);

        // Show goodbye
        rfd::MessageDialog::new()
            .set_title("Uninstalled")
            .set_description("Cleanup will finish in a moment.\n\nYou can now safely delete this folder.")
            .set_buttons(rfd::MessageButtons::Ok)
            .show();

        // Launch cleanup batch detached, then exit immediately
        use std::os::windows::process::CommandExt;
        let _ = std::process::Command::new("cmd.exe")
            .args(["/c", bat_path.to_str().unwrap_or("")])
            .creation_flags(0x08000000u32)
            .spawn();

        std::process::exit(0);
    });

    app.run().unwrap();
}
fn setup_home() {
    rfd::MessageDialog::new()
        .set_title("First Run Setup")
        .set_description("Pick the folder where LRGEX Folder Sync will live.

RECOMMENDED: a folder inside a cloud service (OneDrive, Google Drive, etc.) so your backups survive a PC format.")
        .set_buttons(rfd::MessageButtons::Ok)
        .show();

    let home = rfd::FileDialog::new()
        .set_title("Select LRGEX sync folder")
        .pick_folder();

    if let Some(home) = home {
        if let Ok(exe) = std::env::current_exe() {
            let exe_name = exe.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "LRGEXSync.exe".into());
            let dest = home.join(&exe_name);
            let _ = std::fs::copy(&exe, &dest);
            let _ = std::fs::write(home.join(".lrgex-home"), "LRGEX Folder Sync Home");
            // Set canonical home in registry — ONE source of truth
            config::set_canonical_home(&home);

            let cfg_path = home.join("junction-config.json");
            if !cfg_path.exists() {
                if let Ok(data) = serde_json::to_string_pretty(&config::Config::default()) {
                    let _ = std::fs::write(&cfg_path, data);
                }
            }

            let _ = std::process::Command::new(&dest).spawn();
        }
    }
}

fn refresh_folders(app: &App) {
    let cfg = config::load_config();
    let model = VecModel::from_iter(cfg.junctions.iter().map(|j| FolderEntry {
        path: j.source_path.clone().into(),
        auto_restore: if j.auto_restore { "ON" } else { "OFF" }.into(),
    }));
    app.set_folders(slint::ModelRc::new(model));
}

fn update_rc_label(app: &App) {
    let enabled = is_rightclick_enabled();
    app.set_rc_label(
        if enabled { "Right-Click Sync: ON   (click to disable)" }
        else { "Right-Click Sync: OFF   (click to enable)" }
        .into()
    );
}

fn is_rightclick_enabled() -> bool {
    winreg::RegKey::predef(winreg::enums::HKEY_CURRENT_USER)
        .open_subkey(r"Software\Classes\Directory\shell\LRGEXSync").is_ok()
}

fn toggle_rightclick(enable: bool) {
    let shell = winreg::RegKey::predef(winreg::enums::HKEY_CURRENT_USER)
        .open_subkey_with_flags(r"Software\Classes\Directory\shell", winreg::enums::KEY_ALL_ACCESS);
    if enable {
        if let Ok(shell) = shell {
            // Create LRGEXSync key with display name
            if let Ok((key,_)) = shell.create_subkey("LRGEXSync") {
                let _ = key.set_value("", &"Sync folder (LRGEX)");
                // Icon = the exe itself (icon embedded via winres)
                let exe = std::env::current_exe()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_default();
                if !exe.is_empty() {
                    let _ = key.set_value("Icon", &exe);
                }
                // Command subkey: exe -link "%V"
                if let Ok((cmd,_)) = key.create_subkey("command") {
                    let cmd_str = format!("\"{}\" -link \"%V\"", exe);
                    let _ = cmd.set_value("", &cmd_str);
                }
            }
        }
    } else {
        if let Ok(shell) = shell {
            let _ = shell.delete_subkey_all("LRGEXSync");
        }
    }
}


fn ps_inputbox(prompt: &str, title: &str, default: &str) -> Option<String> {
    let p = prompt.replace('\'', "''");
    let t = title.replace('\'', "''");
    let d = default.replace('\'', "''");
    let script = format!(
        "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.Interaction]::InputBox('{}', '{}', '{}')",
        p, t, d
    );
    let output = std::process::Command::new("powershell.exe")
        .args(["-NoProfile", "-Command", &script])
        .creation_flags(0x08000000u32)
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() { None } else { Some(text) }
}
