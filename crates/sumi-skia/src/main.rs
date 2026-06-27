//! Spike: render the sumi demo frame through the tiny-skia backend and
//! write it to a PNG. Proves the vocabulary maps to a real 2D rasteriser with no
//! system dependencies.
//!
//! Run: `cargo run -p sumi-skia` -> writes `sumi-demo.png`.

use sumi_core::{demo_frame, Backend};
use sumi_skia::SkiaBackend;

fn main() {
    let frame = demo_frame();
    let mut backend = SkiaBackend::new();
    backend.apply_all(&frame);

    // buffer 0 is the visible buffer in the demo frame
    match backend.pixmap(0) {
        Some(pixmap) => match pixmap.save_png("sumi-demo.png") {
            Ok(()) => println!("wrote sumi-demo.png ({} commands)", frame.len()),
            Err(e) => eprintln!("save_png failed: {e}"),
        },
        None => eprintln!("no buffer 0 — did the frame run?"),
    }
}
