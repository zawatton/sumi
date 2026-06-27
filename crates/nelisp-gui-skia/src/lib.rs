//! Pure-Rust [`nelisp_gui_core::Backend`] on tiny-skia.
//!
//! Builds with **no system dependencies**, so it proves the GUI vocabulary maps
//! to a real 2D rasteriser without a GTK4/Cairo toolchain. The Cairo/GTK4 backend
//! (native window + Pango text) implements the same trait once GTK4 is installed.
//!
//! Text rendering is stubbed here (tiny-skia has no font engine); the Cairo
//! backend renders real text via Pango. Sub-region blits are a TODO.

use std::collections::HashMap;

use nelisp_gui_core::{Backend, BlendMode, Color as GuiColor, Command};
use tiny_skia::{Color, Paint, PathBuilder, Pixmap, PixmapPaint, Rect, Stroke, Transform};

/// A tiny-skia backend. Holds one [`Pixmap`] per buffer plus immediate-mode state.
pub struct SkiaBackend {
    buffers: HashMap<i32, Pixmap>,
    current: i32,
    color: GuiColor,
    cursor: (i32, i32),
    blend: BlendMode,
}

impl Default for SkiaBackend {
    fn default() -> Self {
        Self {
            buffers: HashMap::new(),
            current: 0,
            color: GuiColor { r: 0, g: 0, b: 0 },
            cursor: (0, 0),
            blend: BlendMode::Normal,
        }
    }
}

impl SkiaBackend {
    pub fn new() -> Self {
        Self::default()
    }

    fn paint(&self) -> Paint<'static> {
        let mut p = Paint::default();
        p.set_color(Color::from_rgba8(self.color.r, self.color.g, self.color.b, 255));
        p.anti_alias = true;
        p
    }

    /// The current visible buffer, e.g. for saving to PNG in the spike.
    pub fn pixmap(&self, id: i32) -> Option<&Pixmap> {
        self.buffers.get(&id)
    }
}

impl Backend for SkiaBackend {
    fn apply(&mut self, cmd: &Command) {
        match cmd {
            Command::Screen { id, w, h, .. } => {
                if let Some(p) = Pixmap::new((*w).max(1) as u32, (*h).max(1) as u32) {
                    self.buffers.insert(*id, p);
                }
            }
            Command::BufferSelect { id } => self.current = *id,
            Command::SetColor(c) => self.color = *c,
            Command::SetBlendMode(m) => self.blend = *m,
            Command::SetFont { .. } => {} // font handled by the Cairo/Pango backend
            Command::SetPosition { x, y } => self.cursor = (*x, *y),
            Command::FillRect { x1, y1, x2, y2 } => {
                let paint = self.paint();
                if let (Some(p), Some(rect)) = (
                    self.buffers.get_mut(&self.current),
                    Rect::from_xywh(*x1 as f32, *y1 as f32, (*x2 - *x1) as f32, (*y2 - *y1) as f32),
                ) {
                    p.fill_rect(rect, &paint, Transform::identity(), None);
                }
            }
            Command::DrawLine { x1, y1, x2, y2 } => {
                let paint = self.paint();
                let mut pb = PathBuilder::new();
                pb.move_to(*x1 as f32, *y1 as f32);
                pb.line_to(*x2 as f32, *y2 as f32);
                if let (Some(p), Some(path)) = (self.buffers.get_mut(&self.current), pb.finish()) {
                    p.stroke_path(&path, &paint, &Stroke { width: 1.0, ..Default::default() }, Transform::identity(), None);
                }
            }
            Command::DrawPoint { x, y } => {
                let paint = self.paint();
                if let (Some(p), Some(rect)) =
                    (self.buffers.get_mut(&self.current), Rect::from_xywh(*x as f32, *y as f32, 1.0, 1.0))
                {
                    p.fill_rect(rect, &paint, Transform::identity(), None);
                }
            }
            Command::DrawText { text } => {
                // tiny-skia has no font engine: draw a placeholder underline so the
                // layout is visible. Real text comes from the Cairo/Pango backend.
                let (x, y) = self.cursor;
                let w = (text.chars().count() as i32) * 8;
                let paint = self.paint();
                if let (Some(p), Some(rect)) =
                    (self.buffers.get_mut(&self.current), Rect::from_xywh(x as f32, (y + 14) as f32, w as f32, 2.0))
                {
                    p.fill_rect(rect, &paint, Transform::identity(), None);
                }
            }
            Command::DrawImage { src, dx, dy, .. } => {
                // TODO: honour the (sx,sy,w,h) sub-region; spike blits the whole src.
                if let Some(srcbuf) = self.buffers.get(src).map(|p| p.clone()) {
                    if let Some(p) = self.buffers.get_mut(&self.current) {
                        p.draw_pixmap(*dx, *dy, srcbuf.as_ref(), &PixmapPaint::default(), Transform::identity(), None);
                    }
                }
            }
            Command::DrawImageScaled { src, dx, dy, sw, sh, dw, dh, .. } => {
                if let Some(srcbuf) = self.buffers.get(src).map(|p| p.clone()) {
                    let (kx, ky) = (
                        if *sw != 0 { *dw as f32 / *sw as f32 } else { 1.0 },
                        if *sh != 0 { *dh as f32 / *sh as f32 } else { 1.0 },
                    );
                    if let Some(p) = self.buffers.get_mut(&self.current) {
                        p.draw_pixmap(
                            *dx,
                            *dy,
                            srcbuf.as_ref(),
                            &PixmapPaint::default(),
                            Transform::from_scale(kx, ky),
                            None,
                        );
                    }
                }
            }
            Command::ObjectSize { .. } => {}
            Command::Present => {} // PNG/window present handled by the host (see main.rs)
        }
    }
}
