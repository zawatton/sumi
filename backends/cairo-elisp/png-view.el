;; png-view.el — minimal AOT test: load one PNG via cairo and paint it.
;; Gray background first (proves the window paints); then the image on top.
;; If only gray shows, cairo_image_surface_create_from_png returned an empty/error
;; surface; if the map image shows, from_png works and the blit path is fine.
;; ctx: 0 surf  8 loop
(seq
 (data-blob pngpath "C:/Users/kuroz/Cowork/Notes/dev/newDTW-nelisp/assets/img/img_map.gif.png\0" rodata)
 (data-blob title "png-view (from_png test)\0" rodata)
 (data-blob sig "destroy\0" rodata)

 (defun on_draw (area cr w h ctx)
   (seq
    (extern-call cairo_set_source_rgb cr (:f64 0.3) (:f64 0.3) (:f64 0.3))
    (extern-call cairo_paint cr)
    (if (= (ptr-read-u64 ctx 0) 0) 0
      (seq
       (extern-call cairo_set_source_surface cr (ptr-read-u64 ctx 0) (:f64 0.0) (:f64 0.0))
       (extern-call cairo_paint cr)))
    0))

 (defun on_quit (ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 8)) 0))
 (defun on_destroy (widget ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 8)) 0))

 (defun main ()
   (seq
    (extern-call gtk_init)
    (let ((ctx (extern-call malloc 16))
          (surf (extern-call cairo_image_surface_create_from_png (data-addr pngpath))))
      (seq
       (ptr-write-u64 ctx 0 surf)
       (let ((window (extern-call gtk_window_new))
             (area (extern-call gtk_drawing_area_new))
             (loop (extern-call g_main_loop_new 0 0)))
         (seq
          (ptr-write-u64 ctx 8 loop)
          (extern-call gtk_window_set_title window (data-addr title))
          (extern-call gtk_window_set_default_size window 400 400)
          (extern-call gtk_drawing_area_set_draw_func area (addr-of on_draw) ctx 0)
          (extern-call gtk_window_set_child window area)
          (extern-call g_signal_connect_data window (data-addr sig) (addr-of on_destroy) ctx 0 0)
          (extern-call g_timeout_add 60000 (addr-of on_quit) ctx)
          (extern-call gtk_window_present window)
          (extern-call g_main_loop_run loop)
          0)))))))
