//! Backend-agnostic 2D GUI command vocabulary for nelisp.
//!
//! A nelisp program emits a stream of [`Command`]s; a [`Backend`] renders them.
//! The vocabulary is the only contract — backends (tiny-skia, Cairo/GTK4, …) are
//! interchangeable. See ../../README.org for the full design.

/// An RGB colour, 0–255 per channel.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

/// Blend / compositing mode (a small portable subset).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BlendMode {
    /// Source over destination (normal).
    Normal,
    /// Additive.
    Add,
    /// Source colour used as alpha against a key (HSP `gmode 2` family).
    AlphaKey,
}

/// The v0 drawing vocabulary. Each variant has a stable string name used on the
/// nelisp side (`gui-fill-rect`, …) and a game alias (`dtw-fill-rect`).
#[derive(Clone, Debug, PartialEq)]
pub enum Command {
    /// Create / configure an offscreen buffer (`gui-screen`).
    Screen { id: i32, w: i32, h: i32, mode: i32 },
    /// Make a buffer the current draw target (`gui-buffer-select`).
    BufferSelect { id: i32 },
    /// Set the current draw colour (`gui-set-color`).
    SetColor(Color),
    /// Set the blend mode (`gui-set-blend-mode`).
    SetBlendMode(BlendMode),
    /// Set the current font (`gui-set-font`).
    SetFont { name: String, size: i32, style: i32 },
    /// Move the draw cursor (`gui-set-position`).
    SetPosition { x: i32, y: i32 },
    /// Filled rectangle from (x1,y1) to (x2,y2) (`gui-fill-rect`).
    FillRect { x1: i32, y1: i32, x2: i32, y2: i32 },
    /// Line from (x1,y1) to (x2,y2) (`gui-draw-line`).
    DrawLine { x1: i32, y1: i32, x2: i32, y2: i32 },
    /// Single point (`gui-draw-point`).
    DrawPoint { x: i32, y: i32 },
    /// Text at the current cursor (`gui-draw-text`).
    DrawText { text: String },
    /// Blit a region of `src` onto the current buffer at the cursor (`gui-draw-image`).
    DrawImage { src: i32, sx: i32, sy: i32, w: i32, h: i32, dx: i32, dy: i32 },
    /// Scaled blit (`gui-draw-image-scaled`).
    DrawImageScaled { src: i32, sx: i32, sy: i32, sw: i32, sh: i32, dx: i32, dy: i32, dw: i32, dh: i32 },
    /// Declare sprite/object metrics (`gui-object-size`).
    ObjectSize { w: i32, h: i32 },
    /// Flush the visible buffer to the window (`gui-present`).
    Present,
}

/// A renderer for [`Command`]s. Implemented once per backend.
pub trait Backend {
    /// Apply a single command, mutating backend state / drawing.
    fn apply(&mut self, cmd: &Command);

    /// Apply a whole frame.
    fn apply_all(&mut self, frame: &[Command]) {
        for c in frame {
            self.apply(c);
        }
    }
}

/// Parse a stringly command `(name, i32-args, [text])` — the shape that arrives
/// from the nelisp state-diff event stream — into a [`Command`]. Returns `None`
/// for an unknown name. `text` carries the string payload for `gui-draw-text` /
/// font name; numeric args go in `a`.
pub fn parse(name: &str, a: &[i32], text: Option<&str>) -> Option<Command> {
    let g = |i: usize| a.get(i).copied().unwrap_or(0);
    Some(match name {
        "gui-screen" | "dtw-screen" => Command::Screen { id: g(0), w: g(1), h: g(2), mode: g(3) },
        "gui-buffer-select" | "dtw-select-buffer" => Command::BufferSelect { id: g(0) },
        "gui-set-color" | "dtw-set-color" => Command::SetColor(Color { r: g(0) as u8, g: g(1) as u8, b: g(2) as u8 }),
        "gui-set-blend-mode" | "dtw-set-blend-mode" => Command::SetBlendMode(match g(0) {
            0 | 1 => BlendMode::Normal,
            _ => BlendMode::AlphaKey,
        }),
        "gui-set-font" | "dtw-set-font" => Command::SetFont { name: text.unwrap_or("sans").to_string(), size: g(0), style: g(1) },
        "gui-set-position" | "dtw-set-position" => Command::SetPosition { x: g(0), y: g(1) },
        "gui-fill-rect" | "dtw-fill-rect" => Command::FillRect { x1: g(0), y1: g(1), x2: g(2), y2: g(3) },
        "gui-draw-line" | "dtw-draw-line" => Command::DrawLine { x1: g(0), y1: g(1), x2: g(2), y2: g(3) },
        "gui-draw-point" | "dtw-draw-point" => Command::DrawPoint { x: g(0), y: g(1) },
        "gui-draw-text" | "dtw-draw-text" => Command::DrawText { text: text.unwrap_or("").to_string() },
        "gui-draw-image" | "dtw-draw-image" => Command::DrawImage { src: g(0), sx: g(1), sy: g(2), w: g(3), h: g(4), dx: g(5), dy: g(6) },
        "gui-draw-image-scaled" | "dtw-draw-image-scaled" =>
            Command::DrawImageScaled { src: g(0), sx: g(1), sy: g(2), sw: g(3), sh: g(4), dx: g(5), dy: g(6), dw: g(7), dh: g(8) },
        "gui-object-size" | "dtw-object-size" => Command::ObjectSize { w: g(0), h: g(1) },
        "gui-present" | "dtw-redraw" => Command::Present,
        _ => return None,
    })
}

/// Which backend a host should instantiate. Choosing a backend is the host's
/// *only* backend-specific decision — a nelisp program emits the vocabulary and
/// never names a backend. Native hosts pick [`BackendKind::Cairo`] (windowed) or
/// [`BackendKind::Skia`] (headless PNG); a webview shell picks
/// [`BackendKind::Canvas`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackendKind {
    /// Pure-Rust tiny-skia rasteriser — headless PNG, no system deps.
    Skia,
    /// Native Cairo/GTK4 — windowed, real Pango text.
    Cairo,
    /// HTML Canvas 2D — Electron / Tauri webview.
    Canvas,
}

impl BackendKind {
    /// Parse a backend name, case-insensitively. Accepts `skia`/`tiny-skia`,
    /// `cairo`/`gtk4`/`gtk`, and `canvas`/`web`/`html`.
    pub fn from_name(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "skia" | "tiny-skia" => Some(Self::Skia),
            "cairo" | "gtk4" | "gtk" => Some(Self::Cairo),
            "canvas" | "web" | "html" => Some(Self::Canvas),
            _ => None,
        }
    }

    /// The backend named by `$SUMI_BACKEND`, if set and recognised.
    pub fn from_env() -> Option<Self> {
        std::env::var("SUMI_BACKEND").ok().and_then(|v| Self::from_name(&v))
    }
}

/// A small demo frame used by the spike to prove a backend renders the vocabulary.
pub fn demo_frame() -> Vec<Command> {
    use Command::*;
    vec![
        Screen { id: 0, w: 320, h: 240, mode: 0 },
        BufferSelect { id: 0 },
        SetColor(Color { r: 16, g: 16, b: 48 }),
        FillRect { x1: 0, y1: 0, x2: 320, y2: 240 },
        SetColor(Color { r: 220, g: 60, b: 60 }),
        FillRect { x1: 40, y1: 40, x2: 160, y2: 120 },
        SetColor(Color { r: 60, g: 200, b: 90 }),
        DrawLine { x1: 20, y1: 200, x2: 300, y2: 60 },
        SetColor(Color { r: 240, g: 220, b: 60 }),
        SetPosition { x: 60, y: 160 },
        DrawText { text: "sumi".to_string() },
        Present,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_accepts_both_name_families() {
        assert!(matches!(parse("dtw-fill-rect", &[0, 0, 1, 1], None), Some(Command::FillRect { .. })));
        assert!(matches!(parse("gui-fill-rect", &[0, 0, 1, 1], None), Some(Command::FillRect { .. })));
        assert_eq!(parse("gui-draw-text", &[], Some("hi")), Some(Command::DrawText { text: "hi".into() }));
        assert!(parse("not-a-command", &[], None).is_none());
    }

    #[test]
    fn backend_kind_parses_names() {
        assert_eq!(BackendKind::from_name("Cairo"), Some(BackendKind::Cairo));
        assert_eq!(BackendKind::from_name(" GTK4 "), Some(BackendKind::Cairo));
        assert_eq!(BackendKind::from_name("canvas"), Some(BackendKind::Canvas));
        assert_eq!(BackendKind::from_name("tiny-skia"), Some(BackendKind::Skia));
        assert_eq!(BackendKind::from_name("nope"), None);
    }
}
