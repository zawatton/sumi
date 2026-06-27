//! Pure-Rust [`sumi_core::Backend`] on tiny-skia.
//!
//! Builds with **no system dependencies**, so it proves the GUI vocabulary maps
//! to a real 2D rasteriser without a GTK4/Cairo toolchain. The Cairo/GTK4 backend
//! (native window + Pango text) implements the same trait once GTK4 is installed.
//!
//! Text is rendered from a pure-Rust 8x8 bitmap font (=font8x8=), scaled to the
//! font size — real readable glyphs with no system font engine (the Cairo backend
//! renders high-quality antialiased text via Pango). Sub-region blits are honoured
//! (see [`sub_pixmap`]).

use std::collections::HashMap;

use font8x8::UnicodeFonts;
use sumi_core::{Backend, BlendMode, Color as GuiColor, Command};
use tiny_skia::{BlendMode as SkiaBlend, Color, Paint, PathBuilder, Pixmap, PixmapPaint, Rect, Stroke, Transform};

/// A tiny-skia backend. Holds one [`Pixmap`] per buffer plus immediate-mode state.
pub struct SkiaBackend {
    buffers: HashMap<i32, Pixmap>,
    current: i32,
    color: GuiColor,
    cursor: (i32, i32),
    blend: BlendMode,
    font_size: i32,
}

impl Default for SkiaBackend {
    fn default() -> Self {
        Self {
            buffers: HashMap::new(),
            current: 0,
            color: GuiColor { r: 0, g: 0, b: 0 },
            cursor: (0, 0),
            blend: BlendMode::Normal,
            font_size: 16,
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
        p.blend_mode = match self.blend {
            BlendMode::Add => SkiaBlend::Plus, // additive (HSP gmode add)
            // normal + alpha-key both composite via the source alpha channel
            BlendMode::Normal | BlendMode::AlphaKey => SkiaBlend::SourceOver,
        };
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
            Command::SetFont { size, .. } => self.font_size = (*size).max(1),
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
                // real glyphs from the pure-Rust 8x8 bitmap font, scaled to the
                // current font size (~size/8). Each set bit becomes a filled cell.
                let (x0, y0) = self.cursor;
                let scale = ((self.font_size + 4) / 8).max(1);
                let cell = 8 * scale;
                let paint = self.paint();
                if let Some(p) = self.buffers.get_mut(&self.current) {
                    let mut pen_x = x0;
                    for ch in text.chars() {
                        if let Some(glyph) = font8x8::BASIC_FONTS.get(ch) {
                            for (row, bits) in glyph.iter().enumerate() {
                                for col in 0..8u8 {
                                    if bits & (1 << col) != 0 {
                                        if let Some(rect) = Rect::from_xywh(
                                            (pen_x + col as i32 * scale) as f32,
                                            (y0 + row as i32 * scale) as f32,
                                            scale as f32,
                                            scale as f32,
                                        ) {
                                            p.fill_rect(rect, &paint, Transform::identity(), None);
                                        }
                                    }
                                }
                            }
                        }
                        pen_x += cell;
                    }
                }
            }
            Command::DrawImage { src, sx, sy, w, h, dx, dy } => {
                // blit only the (sx,sy,w,h) sub-region of src onto the cursor/(dx,dy)
                if let Some(srcbuf) = self.buffers.get(src).map(|p| p.clone()) {
                    if let Some(sub) = sub_pixmap(&srcbuf, *sx, *sy, *w, *h) {
                        if let Some(p) = self.buffers.get_mut(&self.current) {
                            p.draw_pixmap(*dx, *dy, sub.as_ref(), &PixmapPaint::default(), Transform::identity(), None);
                        }
                    }
                }
            }
            Command::DrawImageScaled { src, sx, sy, sw, sh, dx, dy, dw, dh } => {
                // take the (sx,sy,sw,sh) sub-region and scale it to (dw,dh) at (dx,dy)
                if let Some(srcbuf) = self.buffers.get(src).map(|p| p.clone()) {
                    if let Some(sub) = sub_pixmap(&srcbuf, *sx, *sy, *sw, *sh) {
                        let (kx, ky) = (
                            if *sw != 0 { *dw as f32 / *sw as f32 } else { 1.0 },
                            if *sh != 0 { *dh as f32 / *sh as f32 } else { 1.0 },
                        );
                        if let Some(p) = self.buffers.get_mut(&self.current) {
                            p.draw_pixmap(
                                0,
                                0,
                                sub.as_ref(),
                                &PixmapPaint::default(),
                                Transform::from_scale(kx, ky).post_translate(*dx as f32, *dy as f32),
                                None,
                            );
                        }
                    }
                }
            }
            Command::ObjectSize { .. } => {}
            // image loading needs a decoder; the dependency-free skia backend
            // skips it (the Cairo backend loads PNGs). Sprites stay empty here.
            Command::LoadImage { .. } => {}
            Command::Present => {} // PNG/window present handled by the host (see main.rs)
        }
    }
}

/// Copy the `(sx,sy,w,h)` sub-region of `src` into a fresh `w`×`h` pixmap.
/// Pixels outside `src` come out transparent. Returns `None` for a non-positive
/// size. This is how a sub-region blit is clipped: the extracted pixmap is the
/// exact region, so drawing it never spills the rest of the source buffer.
fn sub_pixmap(src: &Pixmap, sx: i32, sy: i32, w: i32, h: i32) -> Option<Pixmap> {
    if w <= 0 || h <= 0 {
        return None;
    }
    let mut out = Pixmap::new(w as u32, h as u32)?;
    // shift src up-left so its (sx,sy) lands at out's (0,0); out's size clips the rest
    out.draw_pixmap(-sx, -sy, src.as_ref(), &PixmapPaint::default(), Transform::identity(), None);
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn px(p: &Pixmap, x: usize, y: usize) -> (u8, u8, u8, u8) {
        let d = p.data();
        let i = (y * p.width() as usize + x) * 4;
        (d[i], d[i + 1], d[i + 2], d[i + 3])
    }

    /// A sub-region blit must copy only the requested rectangle; everything
    /// outside it stays untouched (transparent).
    #[test]
    fn draw_image_clips_to_sub_region() {
        let mut b = SkiaBackend::new();
        // source buffer 1: 4x4, fully red
        b.apply(&Command::Screen { id: 1, w: 4, h: 4, mode: 0 });
        b.apply(&Command::BufferSelect { id: 1 });
        b.apply(&Command::SetColor(GuiColor { r: 255, g: 0, b: 0 }));
        b.apply(&Command::FillRect { x1: 0, y1: 0, x2: 4, y2: 4 });
        // dest buffer 0: 4x4, empty
        b.apply(&Command::Screen { id: 0, w: 4, h: 4, mode: 0 });
        b.apply(&Command::BufferSelect { id: 0 });
        // blit the 2x2 region at (1,1) of src 1 onto (0,0) of dest 0
        b.apply(&Command::DrawImage { src: 1, sx: 1, sy: 1, w: 2, h: 2, dx: 0, dy: 0 });

        let p = b.pixmap(0).unwrap();
        assert_eq!(px(p, 0, 0), (255, 0, 0, 255), "blitted pixel is opaque red");
        assert_eq!(px(p, 1, 1), (255, 0, 0, 255), "blitted pixel is opaque red");
        assert_eq!(px(p, 2, 2).3, 0, "outside the 2x2 sub-region stays transparent");
        assert_eq!(px(p, 3, 3).3, 0, "outside the 2x2 sub-region stays transparent");
    }

    /// A scaled sub-region blit lands at the destination origin with the
    /// requested size — a 1x1 source region scaled to 3x3 fills (dx..dx+3).
    #[test]
    fn draw_image_scaled_places_and_scales() {
        let mut b = SkiaBackend::new();
        b.apply(&Command::Screen { id: 1, w: 4, h: 4, mode: 0 });
        b.apply(&Command::BufferSelect { id: 1 });
        b.apply(&Command::SetColor(GuiColor { r: 0, g: 255, b: 0 }));
        b.apply(&Command::FillRect { x1: 0, y1: 0, x2: 4, y2: 4 });
        b.apply(&Command::Screen { id: 0, w: 8, h: 8, mode: 0 });
        b.apply(&Command::BufferSelect { id: 0 });
        // take a 1x1 green texel and scale it to 3x3 at (2,2)
        b.apply(&Command::DrawImageScaled { src: 1, sx: 0, sy: 0, sw: 1, sh: 1, dx: 2, dy: 2, dw: 3, dh: 3 });

        let p = b.pixmap(0).unwrap();
        assert_eq!(px(p, 3, 3), (0, 255, 0, 255), "centre of the scaled blit is green");
        assert_eq!(px(p, 0, 0).3, 0, "before the destination origin stays transparent");
        assert_eq!(px(p, 7, 7).3, 0, "past the scaled region stays transparent");
    }

    /// Additive blend mode sums the source onto the destination (HSP gmode add),
    /// where normal compositing would just overwrite it.
    #[test]
    fn add_blend_mode_brightens() {
        let mut b = SkiaBackend::new();
        b.apply(&Command::Screen { id: 0, w: 2, h: 2, mode: 0 });
        b.apply(&Command::BufferSelect { id: 0 });
        // base layer: red 100
        b.apply(&Command::SetColor(GuiColor { r: 100, g: 0, b: 0 }));
        b.apply(&Command::FillRect { x1: 0, y1: 0, x2: 2, y2: 2 });
        // additive red 100 on top -> 200
        b.apply(&Command::SetBlendMode(BlendMode::Add));
        b.apply(&Command::SetColor(GuiColor { r: 100, g: 0, b: 0 }));
        b.apply(&Command::FillRect { x1: 0, y1: 0, x2: 2, y2: 2 });

        let r = px(b.pixmap(0).unwrap(), 0, 0).0;
        assert_eq!(r, 200, "additive blend summed the two reds (100+100)");
    }

    /// draw-text rasterises real glyphs (not the old placeholder): a printable
    /// char sets pixels inside its cell, a space sets none.
    #[test]
    fn draw_text_rasterises_glyphs() {
        let mut b = SkiaBackend::new();
        b.apply(&Command::Screen { id: 0, w: 16, h: 16, mode: 0 });
        b.apply(&Command::BufferSelect { id: 0 });
        b.apply(&Command::SetColor(GuiColor { r: 255, g: 255, b: 255 }));
        b.apply(&Command::SetFont { name: "sans".into(), size: 8, style: 0 });
        b.apply(&Command::SetPosition { x: 0, y: 0 });
        b.apply(&Command::DrawText { text: "A".into() });
        let p = b.pixmap(0).unwrap();
        let any_set = (0..8).any(|y| (0..8).any(|x| px(p, x, y).3 > 0));
        assert!(any_set, "glyph 'A' rasterised at least one pixel");

        // a space glyph is all-zero -> nothing drawn
        let mut b2 = SkiaBackend::new();
        b2.apply(&Command::Screen { id: 0, w: 16, h: 16, mode: 0 });
        b2.apply(&Command::BufferSelect { id: 0 });
        b2.apply(&Command::SetColor(GuiColor { r: 255, g: 255, b: 255 }));
        b2.apply(&Command::SetFont { name: "sans".into(), size: 8, style: 0 });
        b2.apply(&Command::DrawText { text: " ".into() });
        let p2 = b2.pixmap(0).unwrap();
        let none_set = (0..16).all(|y| (0..16).all(|x| px(p2, x, y).3 == 0));
        assert!(none_set, "a space rasterises no pixels");
    }
}
