//! Command sources for the native shell.
//!
//! A [`CommandSource`] plays the role of the nelisp *program*: given the current
//! input, it yields one frame of drawing vocabulary. The shell renders whatever
//! it returns. Two implementations: an in-process [`BoxDemo`] (a stand-in that
//! proves the live loop + input), and [`StdinSource`] — the model-A IPC path that
//! reads a real program's NDJSON command stream from stdin.

use sumi_core::{parse, Color, Command};
use sumi_input::{Button, InputState};

/// Yields one frame of drawing commands per tick. In production this is a nelisp
/// program (over IPC); here it is either an in-process demo or a stdin stream.
pub trait CommandSource {
    fn frame(&mut self, input: &InputState, tick: u64) -> Vec<Command>;
}

/// A movable box: arrows / WASD move it, the frame is the whole screen redrawn.
/// This stands in for a nelisp program to prove the live input→render loop.
pub struct BoxDemo {
    x: i32,
    y: i32,
    size: i32,
    w: i32,
    h: i32,
}

impl BoxDemo {
    pub fn new(w: i32, h: i32) -> Self {
        Self { x: w / 2 - 30, y: h / 2 - 30, size: 60, w, h }
    }
}

impl CommandSource for BoxDemo {
    fn frame(&mut self, input: &InputState, _tick: u64) -> Vec<Command> {
        let s = 6;
        if input.is_down(Button::Left) {
            self.x -= s;
        }
        if input.is_down(Button::Right) {
            self.x += s;
        }
        if input.is_down(Button::Up) {
            self.y -= s;
        }
        if input.is_down(Button::Down) {
            self.y += s;
        }
        self.x = self.x.clamp(0, self.w - self.size);
        self.y = self.y.clamp(0, self.h - self.size);

        use Command::*;
        vec![
            Screen { id: 0, w: self.w, h: self.h, mode: 0 },
            BufferSelect { id: 0 },
            SetColor(Color { r: 18, g: 18, b: 44 }),
            FillRect { x1: 0, y1: 0, x2: self.w, y2: self.h },
            SetColor(Color { r: 240, g: 220, b: 60 }),
            SetFont { name: "sans".into(), size: 18, style: 0 },
            SetPosition { x: 18, y: 16 },
            DrawText { text: "sumi — native GTK4 live  (arrows / WASD to move)".into() },
            SetColor(Color { r: 220, g: 70, b: 70 }),
            FillRect { x1: self.x, y1: self.y, x2: self.x + self.size, y2: self.y + self.size },
            Present,
        ]
    }
}

/// Model-A IPC source: each line of stdin is one frame — a JSON array of
/// `{name, nums, text?}` — exactly the shape `frame.json` uses. A nelisp program
/// drives the native shell with `nelisp-program | sumi-gtk4-native` and
/// `SUMI_STDIN=1`. A reader thread keeps the channel filled so the render
/// loop never blocks; the latest frame wins.
pub struct StdinSource {
    rx: std::sync::mpsc::Receiver<Vec<Command>>,
    last: Vec<Command>,
}

impl StdinSource {
    pub fn new() -> Self {
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            use std::io::BufRead;
            let stdin = std::io::stdin();
            for line in stdin.lock().lines().map_while(Result::ok) {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                if let Ok(entries) = serde_json::from_str::<Vec<RawCmd>>(line) {
                    let cmds = entries
                        .iter()
                        .filter_map(|e| parse(&e.name, &e.nums, e.text.as_deref()))
                        .collect();
                    if tx.send(cmds).is_err() {
                        break;
                    }
                }
            }
        });
        Self { rx, last: Vec::new() }
    }
}

impl CommandSource for StdinSource {
    fn frame(&mut self, _input: &InputState, _tick: u64) -> Vec<Command> {
        // drain to the newest frame; keep showing the last one if nothing new
        while let Ok(cmds) = self.rx.try_recv() {
            self.last = cmds;
        }
        self.last.clone()
    }
}

#[derive(serde::Deserialize)]
struct RawCmd {
    name: String,
    #[serde(default)]
    nums: Vec<i32>,
    #[serde(default)]
    text: Option<String>,
}
