//! Render a *captured real game frame* natively.
//!
//! `frame.json` is one frame of the migrated game's own `dtw-*` draw command
//! stream, recorded by `newDTW.github.io/tools/capture_gui_frame.js` straight off
//! the state-diff runner the game uses. This binary loads it, maps each command
//! through `nelisp_gui_core::parse` (the stable vocabulary contract), renders it
//! on real Cairo surfaces with Pango text, writes a PNG, and hosts it live in a
//! GTK4 window — no webview, no Canvas. This is the "real screen, native" proof.
//!
//! Run (GTK4 + GNU toolchain on PATH/PKG_CONFIG_PATH):
//!   cargo +stable-x86_64-pc-windows-gnu run -p nelisp-gui-cairo --bin nelisp-gui-frame
//! Override the frame file with NELISP_GUI_FRAME=/path/to/frame.json.
//! Set NELISP_GUI_AUTOQUIT=1 to close the window after ~1.2s (CI / smoke).

use std::fs;
use std::time::Duration;

use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, DrawingArea};
use nelisp_gui_cairo::CairoBackend;
use nelisp_gui_core::{parse, Backend, Command};
use serde::Deserialize;

/// One entry of the captured stream: `{ "name": "...", "nums": [..], "text": ? }`.
#[derive(Deserialize)]
struct RawCmd {
    name: String,
    #[serde(default)]
    nums: Vec<i32>,
    #[serde(default)]
    text: Option<String>,
}

fn frame_path() -> String {
    std::env::var("NELISP_GUI_FRAME")
        .unwrap_or_else(|_| concat!(env!("CARGO_MANIFEST_DIR"), "/../../frame.json").to_string())
}

/// Load frame.json and translate it into the backend-agnostic vocabulary.
fn load_frame(path: &str) -> Result<Vec<Command>, String> {
    let raw = fs::read_to_string(path).map_err(|e| format!("read {path}: {e}"))?;
    let entries: Vec<RawCmd> = serde_json::from_str(&raw).map_err(|e| format!("parse json: {e}"))?;
    let mut cmds = Vec::with_capacity(entries.len());
    let mut skipped = 0usize;
    for e in &entries {
        match parse(&e.name, &e.nums, e.text.as_deref()) {
            Some(c) => cmds.push(c),
            None => skipped += 1, // unknown vocabulary (e.g. sprite blit without assets)
        }
    }
    if skipped > 0 {
        eprintln!("note: {skipped} command(s) not in the renderable vocabulary, skipped");
    }
    Ok(cmds)
}

/// Determine the on-screen size from the frame's first `Screen` command.
fn frame_size(frame: &[Command]) -> (i32, i32) {
    for c in frame {
        if let Command::Screen { w, h, .. } = c {
            return (*w, *h);
        }
    }
    (680, 680)
}

fn main() {
    let path = frame_path();
    let frame = match load_frame(&path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("nelisp-gui-frame: {e}");
            std::process::exit(1);
        }
    };
    println!("loaded {} commands from {path}", frame.len());

    let (w, h) = frame_size(&frame);

    // headless side-effect: also write a PNG so the result is inspectable without a display
    {
        let mut backend = CairoBackend::new();
        backend.apply_all(&frame);
        if let Some(surface) = backend.surface(0) {
            match std::fs::File::create("nelisp-gui-frame.png") {
                Ok(mut f) => match surface.write_to_png(&mut f) {
                    Ok(()) => println!("wrote nelisp-gui-frame.png ({w}x{h})"),
                    Err(e) => eprintln!("write_to_png failed: {e}"),
                },
                Err(e) => eprintln!("create png failed: {e}"),
            }
        }
    }

    let app = Application::builder()
        .application_id("org.nelisp.gui.frame")
        .build();

    app.connect_activate(move |app| {
        let frame = frame.clone();
        let area = DrawingArea::new();
        area.set_content_width(w);
        area.set_content_height(h);

        area.set_draw_func(move |_area, cr, _w, _h| {
            let mut backend = CairoBackend::new();
            backend.apply_all(&frame);
            if let Some(surface) = backend.surface(0) {
                let _ = cr.set_source_surface(surface, 0.0, 0.0);
                let _ = cr.paint();
            }
        });

        let window = ApplicationWindow::builder()
            .application(app)
            .title("nelisp-gui — captured game frame (GTK4 / Cairo)")
            .child(&area)
            .build();
        window.present();

        if std::env::var("NELISP_GUI_AUTOQUIT").is_ok() {
            let app = app.clone();
            glib::timeout_add_local_once(Duration::from_millis(1200), move || app.quit());
        }
    });

    app.run();
}
