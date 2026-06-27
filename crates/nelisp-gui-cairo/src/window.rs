//! Live GTK4 window host for the nelisp-gui Cairo backend.
//!
//! Renders the demo frame into a Cairo surface and blits it onto a GTK4
//! `DrawingArea`. This is the native "nelisp GUI library" surface — no webview.
//!
//! Run (GTK4 + GNU toolchain on PATH/PKG_CONFIG_PATH):
//!   cargo +stable-x86_64-pc-windows-gnu run -p nelisp-gui-cairo --bin nelisp-gui-window
//! Set NELISP_GUI_AUTOQUIT=1 to close the window after ~1.2s (for CI / smoke).

use std::time::Duration;

use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, DrawingArea};
use nelisp_gui_cairo::CairoBackend;
use nelisp_gui_core::{demo_frame, Backend};

fn main() {
    let app = Application::builder()
        .application_id("org.nelisp.gui.demo")
        .build();

    app.connect_activate(|app| {
        let area = DrawingArea::new();
        area.set_content_width(320);
        area.set_content_height(240);

        // draw callback: render the nelisp-gui frame and blit it onto the widget
        area.set_draw_func(|_area, cr, _w, _h| {
            let mut backend = CairoBackend::new();
            backend.apply_all(&demo_frame());
            if let Some(surface) = backend.surface(0) {
                let _ = cr.set_source_surface(surface, 0.0, 0.0);
                let _ = cr.paint();
            }
        });

        let window = ApplicationWindow::builder()
            .application(app)
            .title("nelisp-gui (GTK4 / Cairo)")
            .child(&area)
            .build();
        window.present();

        if std::env::var("NELISP_GUI_AUTOQUIT").is_ok() {
            let app = app.clone();
            glib::timeout_add_local_once(Duration::from_millis(1200), move || app.quit());
        }
    });

    app.run();
}
