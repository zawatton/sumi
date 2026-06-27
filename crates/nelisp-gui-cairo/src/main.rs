//! Phase 1a spike: render the nelisp-gui demo frame through the Cairo backend and
//! write it to a PNG — same vocabulary as the tiny-skia spike, but on real Cairo
//! surfaces with real Pango text (no placeholder).
//!
//! Run (with GTK4 + GNU toolchain on PATH/PKG_CONFIG_PATH):
//!   cargo run -p nelisp-gui-cairo  ->  writes nelisp-gui-cairo-demo.png

use std::fs::File;

use nelisp_gui_cairo::CairoBackend;
use nelisp_gui_core::{demo_frame, Backend};

fn main() {
    let frame = demo_frame();
    let mut backend = CairoBackend::new();
    backend.apply_all(&frame);

    match backend.surface(0) {
        Some(surface) => {
            match File::create("nelisp-gui-cairo-demo.png") {
                Ok(mut f) => match surface.write_to_png(&mut f) {
                    Ok(()) => println!("wrote nelisp-gui-cairo-demo.png ({} commands)", frame.len()),
                    Err(e) => eprintln!("write_to_png failed: {e}"),
                },
                Err(e) => eprintln!("create file failed: {e}"),
            }
        }
        None => eprintln!("no buffer 0 — did the frame run?"),
    }
}
