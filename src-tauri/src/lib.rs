mod atomic;
mod background;
mod background_helper;
mod background_legacy;
mod background_runtime;
mod catalog;
mod cdp;
mod commands;
mod config;
mod error;
mod images;
mod library;
mod models;
mod paths;
mod platform;
mod platform_install;
mod process_identity;
mod process_identity_windows;
mod service;

#[cfg(test)]
mod tests;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(commands::BackendState::new())
        .invoke_handler(tauri::generate_handler![
            commands::bootstrap,
            commands::apply_theme,
            commands::restore_theme,
            commands::save_draft,
            commands::save_to_library,
            commands::delete_theme,
            commands::rename_theme,
            commands::restore_built_ins,
            commands::import_background,
            commands::remove_background,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run CodexSkinTool");
}

pub fn run_background_helper_if_requested() -> bool {
    background_helper::run_if_requested()
}
