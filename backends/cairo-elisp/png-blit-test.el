;; png-blit-test.el — isolate the op-12 blit-to-IMAGE-SURFACE idiom.
;; Create an offscreen image surface (like the live renderer's buffer 0), clear
;; it dark, blit a 200x200 region of img_map onto it using the EXACT op-12 idiom
;; (save/translate/scale/set_source_surface/rectangle/fill/restore), draw text
;; too, then show that surface in the window.  If the map region + text both
;; appear, the blit-to-image idiom is fine; if only the text/dark bg appears, the
;; blit-to-image idiom is the bug.
;; ctx: 0 buf-surface  8 loop
(seq
 (data-blob pngpath "C:/Users/kuroz/Cowork/Notes/dev/newDTW-nelisp/assets/img/img_map.gif.png\0" rodata)
 (data-blob title "png-blit-test (blit to image surface)\0" rodata)
 (data-blob font  "Meiryo\0" rodata)
 (data-blob label "TEXT works\0" rodata)
 (data-blob sig "destroy\0" rodata)

 (defun on_draw (area cr w h ctx)
   (seq
    (extern-call cairo_set_source_surface cr (ptr-read-u64 ctx 0) (:f64 0.0) (:f64 0.0))
    (extern-call cairo_paint cr)
    0))

 (defun on_quit (ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 8)) 0))
 (defun on_destroy (widget ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 8)) 0))

 (defun main ()
   (seq
    (extern-call gtk_init)
    (let ((ctx (extern-call malloc 16))
          (src (extern-call cairo_image_surface_create_from_png (data-addr pngpath)))
          (buf (extern-call cairo_image_surface_create 0 400 400)))
      (let ((cr (extern-call cairo_create buf)))
        (seq
         (ptr-write-u64 ctx 0 buf)
         ;; clear dark
         (extern-call cairo_set_source_rgb cr (:f64 0.10) (:f64 0.12) (:f64 0.20))
         (extern-call cairo_paint cr)
         ;; op-12 idiom: blit region (0,0,200,200) of src to dest (10,10) scale 1
         (extern-call cairo_save cr)
         (extern-call cairo_translate cr (:f64 10.0) (:f64 10.0))
         (extern-call cairo_scale cr (:f64 1.0) (:f64 1.0))
         (extern-call cairo_set_source_surface cr src (:f64 0.0) (:f64 0.0))
         (extern-call cairo_rectangle cr (:f64 0.0) (:f64 0.0) (:f64 200.0) (:f64 200.0))
         (extern-call cairo_fill cr)
         (extern-call cairo_restore cr)
         ;; text to prove text works on the same surface
         (extern-call cairo_set_source_rgb cr (:f64 1.0) (:f64 1.0) (:f64 0.3))
         (extern-call cairo_select_font_face cr (data-addr font) 0 0)
         (extern-call cairo_set_font_size cr (:f64 22.0))
         (extern-call cairo_move_to cr (:f64 20.0) (:f64 260.0))
         (extern-call cairo_show_text cr (data-addr label))
         (extern-call cairo_surface_flush buf)
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
            0))))))))
