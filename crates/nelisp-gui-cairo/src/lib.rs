//! Native GTK4/Cairo backend for nelisp-gui — reference skeleton.
//!
//! Implements the same [`nelisp_gui_core::Backend`] trait as the tiny-skia
//! backend, but on real Cairo `ImageSurface`s with Pango text, hosted in a GTK4
//! `DrawingArea`. This is the "nelisp GUI library" native target.
//!
//! Builds and runs on this machine against gtk4-rs 0.9 / cairo-rs 0.20 with the
//! GTK4 dev libraries + a GNU Rust toolchain (see ../../README.org "Setup"). The
//! bins `nelisp-gui-cairo-demo` (PNG), `nelisp-gui-window` (live GTK4 window) and
//! `nelisp-gui-frame` (renders a captured game frame) exercise it.

use std::collections::HashMap;

use cairo::{Context, Format, ImageSurface};
use nelisp_gui_core::{Backend, Color, Command};

/// A Cairo backend: one `ImageSurface` per buffer + immediate-mode state.
pub struct CairoBackend {
    buffers: HashMap<i32, ImageSurface>,
    current: i32,
    color: Color,
    cursor: (f64, f64),
    font: (String, i32),
}

impl Default for CairoBackend {
    fn default() -> Self {
        Self {
            buffers: HashMap::new(),
            current: 0,
            color: Color { r: 0, g: 0, b: 0 },
            cursor: (0.0, 0.0),
            font: ("sans".into(), 16),
        }
    }
}

impl CairoBackend {
    pub fn new() -> Self {
        Self::default()
    }

    /// A fresh Cairo context over the current buffer with the current colour set.
    fn ctx(&self) -> Option<Context> {
        let surface = self.buffers.get(&self.current)?;
        let cr = Context::new(surface).ok()?;
        cr.set_source_rgb(self.color.r as f64 / 255.0, self.color.g as f64 / 255.0, self.color.b as f64 / 255.0);
        Some(cr)
    }

    /// The buffer surface (e.g. to attach to a GTK4 DrawingArea / write a PNG).
    pub fn surface(&self, id: i32) -> Option<&ImageSurface> {
        self.buffers.get(&id)
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
            Command::SetBlendMode(_m) => { /* TODO: cr.set_operator(...) per BlendMode */ }
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
            Command::Present => { /* host calls drawing_area.queue_draw() */ }
        }
    }
}

// A GTK4 host (window + DrawingArea that blits the visible buffer) lands in
// src/main.rs once this crate joins the workspace.
