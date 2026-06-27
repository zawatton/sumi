// Thin Tauri shell: opens a WebView window whose frontend (dist/) renders the
// sumi Canvas backend. The shell carries no drawing logic — it just hosts
// the same Canvas backend the Electron shell uses, proving the vocabulary runs
// unchanged under a Tauri (Rust) shell instead of Electron.
//
// SUMI_AUTOQUIT=1 closes the app after ~4s (for CI / smoke).

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            if std::env::var("SUMI_AUTOQUIT").is_ok() {
                let handle = app.handle().clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_secs(4));
                    handle.exit(0);
                });
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running the sumi Tauri shell");
}
