//! Native GTK4 shell for nelisp-gui (Phase 4 — model A: command stream / IPC).
//!
//! A live render loop with no webview: each tick a [`CommandSource`] (a nelisp
//! program's role) yields a frame of drawing vocabulary; the shell renders it
//! through the Cairo backend into a GTK4 `DrawingArea` and folds keyboard input
//! into a `nelisp_input::InputState` it hands back to the source. The default
//! source is an in-process movable-box demo; `NELISP_GUI_STDIN=1` instead reads a
//! real program's NDJSON command stream from stdin.
//!
//! Run (Windows: GNU toolchain + MSYS2 GTK4 on PATH/PKG_CONFIG_PATH):
//!   cargo +stable-x86_64-pc-windows-gnu run -p nelisp-gui-gtk4-native
//! NELISP_GUI_AUTOQUIT=1 drives synthetic "move right" input for ~40 ticks, writes
//! nelisp-gui-live.png, and quits (headless smoke).

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, DrawingArea, EventControllerKey};
use nelisp_gui_cairo::CairoBackend;
use nelisp_gui_core::Backend;
use nelisp_input::{button_from_key, Button, InputEvent, InputState};

mod source;
use source::{BoxDemo, CommandSource, StdinSource};

const W: i32 = 680;
const H: i32 = 680;

struct State {
    backend: CairoBackend,
    source: Box<dyn CommandSource>,
    input: InputState,
    tick: u64,
}

fn main() {
    let app = Application::builder()
        .application_id("org.nelisp.gui.gtk4native")
        .build();
    app.connect_activate(build_ui);
    app.run();
}

fn build_ui(app: &Application) {
    let source: Box<dyn CommandSource> = if std::env::var("NELISP_GUI_STDIN").is_ok() {
        Box::new(StdinSource::new())
    } else {
        Box::new(BoxDemo::new(W, H))
    };
    let state = Rc::new(RefCell::new(State {
        backend: CairoBackend::new(),
        source,
        input: InputState::new(),
        tick: 0,
    }));

    let area = DrawingArea::new();
    area.set_content_width(W);
    area.set_content_height(H);
    {
        let state = state.clone();
        area.set_draw_func(move |_a, cr, _w, _h| {
            let st = state.borrow();
            if let Some(surface) = st.backend.surface(0) {
                let _ = cr.set_source_surface(surface, 0.0, 0.0);
                let _ = cr.paint();
            }
        });
    }

    let window = ApplicationWindow::builder()
        .application(app)
        .title("nelisp-gui — native GTK4 (live)")
        .child(&area)
        .build();

    // keyboard -> nelisp-input InputState
    let key = EventControllerKey::new();
    {
        let state = state.clone();
        key.connect_key_pressed(move |_c, keyval, _code, _mods| {
            if let Some(b) = keyval.name().and_then(|n| button_from_key(n.as_str())) {
                state.borrow_mut().input.apply(&InputEvent::ButtonDown(b));
            }
            glib::Propagation::Proceed
        });
    }
    {
        let state = state.clone();
        key.connect_key_released(move |_c, keyval, _code, _mods| {
            if let Some(b) = keyval.name().and_then(|n| button_from_key(n.as_str())) {
                state.borrow_mut().input.apply(&InputEvent::ButtonUp(b));
            }
        });
    }
    window.add_controller(key);
    window.present();

    let autoquit = std::env::var("NELISP_GUI_AUTOQUIT").is_ok();

    // ~60fps live loop
    let state_tick = state.clone();
    let area_tick = area.clone();
    let app_tick = app.clone();
    glib::timeout_add_local(Duration::from_millis(16), move || {
        {
            let mut st = state_tick.borrow_mut();
            st.tick += 1;
            // headless smoke: script a "hold Right" so the box visibly moves
            if autoquit {
                st.input.apply(&InputEvent::ButtonDown(Button::Right));
            }
            let input = st.input;
            let tick = st.tick;
            let cmds = st.source.frame(&input, tick);
            st.backend.apply_all(&cmds);
        }
        area_tick.queue_draw();

        if autoquit {
            let st = state_tick.borrow();
            if st.tick >= 40 {
                if let Some(surface) = st.backend.surface(0) {
                    if let Ok(mut f) = std::fs::File::create("nelisp-gui-live.png") {
                        let _ = surface.write_to_png(&mut f);
                    }
                }
                app_tick.quit();
                return glib::ControlFlow::Break;
            }
        }
        glib::ControlFlow::Continue
    });
}
