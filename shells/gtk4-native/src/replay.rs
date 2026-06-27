//! Replay a captured game command stream natively on Cairo/GTK4.
//!
//! Reads a JSON array of `{name, nums, text?}` (e.g. `sumi-title-stream.json`,
//! recorded from the webview game with SUMI_RECORD=1), loads its image assets via
//! Cairo, replays every command on the Cairo backend, and presents the visible
//! buffer — the webview game's frame rendered *natively* on GTK4, no webview.
//!
//! Env:
//!   SUMI_STREAM_FILE   the stream json (default: sumi-title-stream.json)
//!   SUMI_IMAGE_ROOT    asset dir for load-image (resolves <root>/<name>.png)
//!   SUMI_PRESENT_BUFFER  which buffer to show (default: 0, the game's screen)
//!   SUMI_AUTOQUIT      close the window after ~1.5s (smoke)

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::fs;
use std::time::Duration;

use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, DrawingArea};
use serde::Deserialize;
use sumi_cairo::CairoBackend;
use sumi_core::{parse, Backend};

#[derive(Deserialize)]
struct RawCmd {
    name: String,
    #[serde(default)]
    nums: Vec<i32>,
    #[serde(default)]
    text: Option<String>,
}

/// Replay the stream into a fresh backend; returns (backend, present-buffer-id).
fn replay() -> (CairoBackend, i32) {
    let stream_path = std::env::var("SUMI_STREAM_FILE").unwrap_or_else(|_| "sumi-title-stream.json".into());
    let image_root = std::env::var("SUMI_IMAGE_ROOT").unwrap_or_default();
    let present: i32 = std::env::var("SUMI_PRESENT_BUFFER").ok().and_then(|s| s.parse().ok()).unwrap_or(0);

    let raw = fs::read_to_string(&stream_path).unwrap_or_else(|e| {
        eprintln!("read {stream_path}: {e}");
        std::process::exit(1);
    });
    let entries: Vec<RawCmd> = serde_json::from_str(&raw).unwrap_or_else(|e| {
        eprintln!("parse json: {e}");
        std::process::exit(1);
    });

    let mut backend = CairoBackend::new();
    backend.set_image_root(&image_root);
    let (mut applied, mut skipped) = (0u32, 0u32);
    for e in &entries {
        match parse(&e.name, &e.nums, e.text.as_deref()) {
            Some(cmd) => {
                backend.apply(&cmd);
                applied += 1;
            }
            None => skipped += 1,
        }
    }
    println!("replayed {applied} commands ({skipped} skipped); presenting buffer {present}");
    (backend, present)
}

fn main() {
    let app = Application::builder().application_id("org.sumi.replay").build();
    app.connect_activate(|app| {
        let (backend, present) = replay();
        let (w, h) = backend.surface(present).map(|s| (s.width(), s.height())).unwrap_or((340, 340));

        // write the native render to a PNG for inspection
        if let Some(surface) = backend.surface(present) {
            if let Ok(mut f) = std::fs::File::create("sumi-game-native.png") {
                let _ = surface.write_to_png(&mut f);
                println!("wrote sumi-game-native.png ({w}x{h})");
            }
        } else {
            eprintln!("present buffer {present} was never created");
        }

        let area = DrawingArea::new();
        area.set_content_width(w);
        area.set_content_height(h);
        area.set_draw_func(move |_a, cr, _w, _h| {
            if let Some(surface) = backend.surface(present) {
                let _ = cr.set_source_surface(surface, 0.0, 0.0);
                let _ = cr.paint();
            }
        });

        let window = ApplicationWindow::builder()
            .application(app)
            .title("sumi — native game frame (GTK4 / Cairo)")
            .child(&area)
            .build();
        window.present();

        if std::env::var("SUMI_AUTOQUIT").is_ok() {
            let app = app.clone();
            glib::timeout_add_local_once(Duration::from_millis(1500), move || app.quit());
        }
    });
    app.run();
}
