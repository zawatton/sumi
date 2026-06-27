//! Phase 1a spike: render the sumi demo frame through the Cairo backend and
//! write it to a PNG — same vocabulary as the tiny-skia spike, but on real Cairo
//! surfaces with real Pango text (no placeholder).
//!
//! Run (with GTK4 + GNU toolchain on PATH/PKG_CONFIG_PATH):
//!   cargo run -p sumi-cairo  ->  writes sumi-cairo-demo.png

use std::fs::File;

use sumi_cairo::CairoBackend;
use sumi_core::{demo_frame, Backend};

fn main() {
    let frame = demo_frame();
    let mut backend = CairoBackend::new();
    backend.apply_all(&frame);

    match backend.surface(0) {
        Some(surface) => {
            match File::create("sumi-cairo-demo.png") {
                Ok(mut f) => match surface.write_to_png(&mut f) {
                    Ok(()) => println!("wrote sumi-cairo-demo.png ({} commands)", frame.len()),
                    Err(e) => eprintln!("write_to_png failed: {e}"),
                },
                Err(e) => eprintln!("create file failed: {e}"),
            }
        }
        None => eprintln!("no buffer 0 — did the frame run?"),
    }
}
