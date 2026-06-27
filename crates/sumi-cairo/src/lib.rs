//! Native GTK4/Cairo backend for sumi — reference skeleton.
//!
//! Implements the same [`sumi_core::Backend`] trait as the tiny-skia
//! backend, but on real Cairo `ImageSurface`s with Pango text, hosted in a GTK4
//! `DrawingArea`. This is the "nelisp GUI library" native target.
//!
//! Builds and runs on this machine against gtk4-rs 0.9 / cairo-rs 0.20 with the
//! GTK4 dev libraries + a GNU Rust toolchain (see ../../README.org "Setup"). The
//! bins `sumi-cairo-demo` (PNG), `sumi-window` (live GTK4 window) and
//! `sumi-frame` (renders a captured game frame) exercise it.

use std::collections::HashMap;

use cairo::{Context, Format, ImageSurface, Operator};
use sumi_core::{Backend, BlendMode, Color, Command};

/// A Cairo backend: one `ImageSurface` per buffer + immediate-mode state.
pub struct CairoBackend {
    buffers: HashMap<i32, ImageSurface>,
    current: i32,
    color: Color,
    cursor: (f64, f64),
    font: (String, i32),
    blend: BlendMode,
    /// Directory that `LoadImage` resolves asset names against (`<root>/<name>.png`).
    image_root: String,
}

impl Default for CairoBackend {
    fn default() -> Self {
        Self {
            buffers: HashMap::new(),
            current: 0,
            color: Color { r: 0, g: 0, b: 0 },
            cursor: (0.0, 0.0),
            font: ("sans".into(), 16),
            blend: BlendMode::Normal,
            image_root: String::new(),
        }
    }
}

impl CairoBackend {
    pub fn new() -> Self {
        Self::default()
    }

    /// Directory that `LoadImage` asset names resolve against (`<root>/<name>.png`).
    pub fn set_image_root(&mut self, root: impl Into<String>) {
        self.image_root = root.into();
    }

    /// A fresh Cairo context over the current buffer with the current colour set.
    fn ctx(&self) -> Option<Context> {
        let surface = self.buffers.get(&self.current)?;
        let cr = Context::new(surface).ok()?;
        cr.set_source_rgb(self.color.r as f64 / 255.0, self.color.g as f64 / 255.0, self.color.b as f64 / 255.0);
        cr.set_operator(match self.blend {
            BlendMode::Normal => Operator::Over,
            BlendMode::Add => Operator::Add,
            // alpha-key sprites composite via the source alpha channel (our
            // surfaces are ARgb32), which is exactly "over".
            BlendMode::AlphaKey => Operator::Over,
        });
        Some(cr)
    }

    /// The buffer surface (e.g. to attach to a GTK4 DrawingArea / write a PNG).
    pub fn surface(&self, id: i32) -> Option<&ImageSurface> {
        self.buffers.get(&id)
    }

    /// Remove and return a buffer's surface — e.g. to hand the finished frame to
    /// a PNG writer or a host, or to read its pixels (which Cairo only allows on
    /// an exclusively-owned surface). The backend no longer owns it afterward.
    pub fn take_surface(&mut self, id: i32) -> Option<ImageSurface> {
        self.buffers.remove(&id)
    }
}

impl Backend for CairoBackend {
    fn apply(&mut self, cmd: &Command) {
        match cmd {
            Command::Screen { id, w, h, .. } => {
                if let Ok(s) = ImageSurface::create(Format::ARgb32, (*w).max(1), (*h).max(1)) {
                    self.buffers.insert(*id, s);
                }
            }
            Command::BufferSelect { id } => self.current = *id,
            Command::SetColor(c) => self.color = *c,
            Command::SetBlendMode(m) => self.blend = *m,
            Command::SetFont { name, size, .. } => self.font = (name.clone(), *size),
            Command::SetPosition { x, y } => self.cursor = (*x as f64, *y as f64),
            Command::FillRect { x1, y1, x2, y2 } => {
                if let Some(cr) = self.ctx() {
                    cr.rectangle(*x1 as f64, *y1 as f64, (*x2 - *x1) as f64, (*y2 - *y1) as f64);
                    let _ = cr.fill();
                }
            }
            Command::DrawLine { x1, y1, x2, y2 } => {
                if let Some(cr) = self.ctx() {
                    cr.set_line_width(1.0);
                    cr.move_to(*x1 as f64, *y1 as f64);
                    cr.line_to(*x2 as f64, *y2 as f64);
                    let _ = cr.stroke();
                }
            }
            Command::DrawPoint { x, y } => {
                if let Some(cr) = self.ctx() {
                    cr.rectangle(*x as f64, *y as f64, 1.0, 1.0);
                    let _ = cr.fill();
                }
            }
            Command::DrawText { text } => {
                if let Some(cr) = self.ctx() {
                    let layout = pangocairo::functions::create_layout(&cr);
                    let mut desc = pango::FontDescription::new();
                    desc.set_family(&self.font.0);
                    desc.set_size(self.font.1 * pango::SCALE);
                    layout.set_font_description(Some(&desc));
                    layout.set_text(text);
                    cr.move_to(self.cursor.0, self.cursor.1);
                    pangocairo::functions::show_layout(&cr, &layout);
                }
            }
            Command::DrawImage { src, sx, sy, w, h, dx, dy } => {
                if *w > 0 && *h > 0 {
                    if let Some(srcsurf) = self.buffers.get(src).cloned() {
                        if let Some(cr) = self.ctx() {
                            // clip the destination to the (w,h) box so only the
                            // (sx,sy,w,h) sub-region of src is painted
                            cr.rectangle(*dx as f64, *dy as f64, *w as f64, *h as f64);
                            cr.clip();
                            // place src so that its (sx,sy) lands at (dx,dy)
                            let _ = cr.set_source_surface(&srcsurf, (*dx - *sx) as f64, (*dy - *sy) as f64);
                            let _ = cr.paint();
                        }
                    }
                }
            }
            Command::DrawImageScaled { src, sx, sy, sw, sh, dx, dy, dw, dh } => {
                if *sw > 0 && *sh > 0 {
                    if let Some(srcsurf) = self.buffers.get(src).cloned() {
                        if let Some(cr) = self.ctx() {
                            let (kx, ky) = (*dw as f64 / *sw as f64, *dh as f64 / *sh as f64);
                            cr.translate(*dx as f64, *dy as f64);
                            cr.scale(kx, ky);
                            // in scaled space, clip to the source sub-region size (sw,sh)
                            cr.rectangle(0.0, 0.0, *sw as f64, *sh as f64);
                            cr.clip();
                            // align src's (sx,sy) to the clipped origin
                            let _ = cr.set_source_surface(&srcsurf, -(*sx as f64), -(*sy as f64));
                            let _ = cr.paint();
                        }
                    }
                }
            }
            Command::ObjectSize { .. } => {}
            Command::LoadImage { id, name } => {
                // resolve <image_root>/<name>.png and load it into buffer `id`
                let path = format!("{}/{}.png", self.image_root, name);
                match std::fs::File::open(&path).map_err(|_| ()).and_then(|mut f| {
                    ImageSurface::create_from_png(&mut f).map_err(|_| ())
                }) {
                    Ok(surface) => {
                        self.buffers.insert(*id, surface);
                    }
                    Err(_) => eprintln!("load-image: failed to open {path}"),
                }
            }
            Command::Present => { /* host calls drawing_area.queue_draw() */ }
        }
    }
}

// The GTK4 hosts live in src/window.rs (demo frame) and src/frame.rs (captured
// game frame); src/main.rs writes a PNG.

#[cfg(test)]
mod tests {
    use super::*;

    /// Additive blend mode sums the source onto the destination via Cairo's
    /// `Operator::Add`, where normal compositing would overwrite it.
    #[test]
    fn add_blend_mode_brightens() {
        let mut b = CairoBackend::new();
        b.apply(&Command::Screen { id: 0, w: 2, h: 2, mode: 0 });
        b.apply(&Command::BufferSelect { id: 0 });
        // base layer: red 100
        b.apply(&Command::SetColor(Color { r: 100, g: 0, b: 0 }));
        b.apply(&Command::FillRect { x1: 0, y1: 0, x2: 2, y2: 2 });
        // additive red 100 on top -> ~200
        b.apply(&Command::SetBlendMode(BlendMode::Add));
        b.apply(&Command::SetColor(Color { r: 100, g: 0, b: 0 }));
        b.apply(&Command::FillRect { x1: 0, y1: 0, x2: 2, y2: 2 });

        let mut surf = b.take_surface(0).expect("buffer 0");
        surf.flush();
        let data = surf.data().expect("surface data");
        // ARgb32 is BGRA byte order on little-endian; red is at offset 2.
        let r = data[2];
        assert!((195..=205).contains(&r), "additive blend brightened red to ~200 (got {r})");
    }
}
