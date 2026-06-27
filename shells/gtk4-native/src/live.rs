//! Live native renderer: a TCP server that renders a webview game's command
//! stream into a GTK4 window in real time. The game (Electron) connects and
//! sends one NDJSON line per frame (a JSON array of `{name,nums,text?}`); this
//! applies each frame to a *persistent* Cairo backend and repaints the window —
//! so the game plays natively on GTK4, no webview.
//!
//! Env:
//!   SUMI_TCP          listen port (default 9099)
//!   SUMI_IMAGE_ROOT   asset dir for load-image (<root>/<name>.png)
//!   SUMI_SCALE        integer upscale of the 340x340 game buffer (default 2)
//!   SUMI_AUTOQUIT_MS  write sumi-live-frame.png and quit after N ms (smoke)

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::cell::RefCell;
use std::io::{BufRead, BufReader};
use std::net::TcpListener;
use std::rc::Rc;
use std::sync::mpsc;
use std::time::Duration;

use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, DrawingArea};
use serde::Deserialize;
use sumi_cairo::CairoBackend;
use sumi_core::{parse, Backend, Command};

#[derive(Deserialize)]
struct RawCmd {
    name: String,
    #[serde(default)]
    nums: Vec<i32>,
    #[serde(default)]
    text: Option<String>,
}

fn main() {
    let port: u16 = std::env::var("SUMI_TCP").ok().and_then(|s| s.parse().ok()).unwrap_or(9099);
    let image_root = std::env::var("SUMI_IMAGE_ROOT").unwrap_or_default();
    let scale: f64 = std::env::var("SUMI_SCALE").ok().and_then(|s| s.parse().ok()).unwrap_or(2.0);
    let autoquit_ms: Option<u64> = std::env::var("SUMI_AUTOQUIT_MS").ok().and_then(|s| s.parse().ok());

    // TCP reader thread -> channel of per-frame command lists
    let (tx, rx) = mpsc::channel::<Vec<Command>>();
    std::thread::spawn(move || {
        let listener = match TcpListener::bind(("127.0.0.1", port)) {
            Ok(l) => l,
            Err(e) => {
                eprintln!("bind 127.0.0.1:{port}: {e}");
                return;
            }
        };
        println!("sumi-live listening on 127.0.0.1:{port}");
        for stream in listener.incoming().flatten() {
            let reader = BufReader::new(stream);
            for line in reader.lines().map_while(Result::ok) {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                if let Ok(entries) = serde_json::from_str::<Vec<RawCmd>>(line) {
                    let cmds: Vec<Command> = entries
                        .iter()
                        .filter_map(|e| parse(&e.name, &e.nums, e.text.as_deref()))
                        .collect();
                    if tx.send(cmds).is_err() {
                        return;
                    }
                }
            }
        }
    });

    let app = Application::builder().application_id("org.sumi.live").build();
    let rx = Rc::new(rx);
    app.connect_activate(move |app| {
        let mut b = CairoBackend::new();
        b.set_image_root(&image_root);
        let backend = Rc::new(RefCell::new(b));
        let frames = Rc::new(RefCell::new(0u64));

        let area = DrawingArea::new();
        area.set_content_width((340.0 * scale) as i32);
        area.set_content_height((340.0 * scale) as i32);
        {
            let backend = backend.clone();
            area.set_draw_func(move |_a, cr, _w, _h| {
                let b = backend.borrow();
                if let Some(surface) = b.surface(0) {
                    cr.scale(scale, scale);
                    let _ = cr.set_source_surface(surface, 0.0, 0.0);
                    let _ = cr.paint();
                }
            });
        }

        let window = ApplicationWindow::builder()
            .application(app)
            .title("sumi — live native game (GTK4 / Cairo)")
            .child(&area)
            .build();
        window.present();

        // drain incoming frames each tick, apply to the persistent backend, repaint
        let backend_t = backend.clone();
        let area_t = area.clone();
        let frames_t = frames.clone();
        let rx_t = rx.clone();
        let app_t = app.clone();
        glib::timeout_add_local(Duration::from_millis(16), move || {
            let mut got = false;
            while let Ok(cmds) = rx_t.try_recv() {
                backend_t.borrow_mut().apply_all(&cmds);
                *frames_t.borrow_mut() += 1;
                got = true;
            }
            if got {
                area_t.queue_draw();
            }
            glib::ControlFlow::Continue
        });

        if let Some(ms) = autoquit_ms {
            let backend_q = backend.clone();
            let frames_q = frames.clone();
            let app_q = app_t.clone();
            glib::timeout_add_local_once(Duration::from_millis(ms), move || {
                if let Some(surface) = backend_q.borrow().surface(0) {
                    if let Ok(mut f) = std::fs::File::create("sumi-live-frame.png") {
                        let _ = surface.write_to_png(&mut f);
                        println!("wrote sumi-live-frame.png after {} frames", frames_q.borrow());
                    }
                }
                app_q.quit();
            });
        }
    });
    app.run();
}
