use std::{fs, path::Path};

// Vendor the Canvas backend (and the captured frame) into the frontend dist so
// the WebView can import them as same-origin assets, then run the Tauri codegen.
// Keeps backends/canvas/ as the single source of truth — dist/lib is generated
// and git-ignored.
fn main() {
    let lib_dst = Path::new("dist/lib");
    let _ = fs::create_dir_all(lib_dst);
    if let Ok(entries) = fs::read_dir("../../backends/canvas/src") {
        for e in entries.flatten() {
            let p = e.path();
            if p.extension().and_then(|s| s.to_str()) == Some("js") {
                let _ = fs::copy(&p, lib_dst.join(p.file_name().unwrap()));
            }
        }
    }
    // the real captured game frame, so the shell shows the same picture as the
    // native backends (falls back to an inline frame if absent)
    let _ = fs::copy("../../frame.json", "dist/frame.json");

    println!("cargo:rerun-if-changed=../../backends/canvas/src");
    println!("cargo:rerun-if-changed=../../frame.json");

    tauri_build::build();
}
