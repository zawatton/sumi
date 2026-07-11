;; sumi-sprite.el - NeLisp AOT sprite/buffer renderer for sumi.
;;
;; Replays a CAPTURED sumi command stream (sumi-sprite.bin)
;; including PNG sprite blits, the way the game actually draws: off-screen
;; buffers are cairo image surfaces; the game loads PNGs into buffers, selects a
;; draw target, and blits scaled sprite regions between buffers.  The whole
;; stream is processed once into the buffers; buffer 0 (the screen) is then
;; shown in the GTK4 window.
;;
;; Record (96B, 12 u64 LE): [0]op a0..a9 [11]toff.  Numeric args are f64 BITS
;; (colours/scale pre-divided by the converter); ints (ids, w/h) are raw.
;;   1 select-buffer(a0=id)  2 set-color(rgb)  3 set-font(a0=size,toff=family)
;;   5 fill-rect(xywh)  8 draw-text(a0,a1=xy,toff=text)  9 screen(id,w,h)
;;  10 load-image(a0=id,toff=png-path)
;;  12 draw-image-scaled(a0=src a1,a2=dx,dy a3,a4=-sx,-sy a5,a6=sw,sh a7,a8=scale)
;;
;; ctx: 0 loop  8 buf  16 blob_base  24 cmd_base  32 num_cmds  40 i  48 area
;;      56 bufsurf[256]  64 bufcr[256]  72 cur_cr  80 screen_surf
(seq
 (data-blob binpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-sprite.bin\0" rodata)
 (data-blob mode_rb "rb\0" rodata)
 (data-blob title   "sumi-sprite (NeLisp AOT, native game frame)\0" rodata)
 (data-blob sig_destroy "destroy\0" rodata)

 ;; Process the whole command stream into the buffer surfaces.
 (defun process_stream (ctx)
   (let ((cmd_base (ptr-read-u64 ctx 24))
         (blob_base (ptr-read-u64 ctx 16))
         (bufsurf (ptr-read-u64 ctx 56))
         (bufcr (ptr-read-u64 ctx 64))
         (ncmd (ptr-read-u64 ctx 32)))
     (seq
      (ptr-write-u64 ctx 40 0)
      (while (< (ptr-read-u64 ctx 40) ncmd)
        (seq
         (let ((rec (+ cmd_base (* (ptr-read-u64 ctx 40) 96))))
           (let ((op (ptr-read-u64 rec 0)))
             (cond
              ((= op 9)
               (let ((id (ptr-read-u64 rec 8)))
                 (let ((surf (extern-call cairo_image_surface_create 0
                                          (ptr-read-u64 rec 16) (ptr-read-u64 rec 24))))
                   (seq
                    (ptr-write-u64 (+ bufsurf (* id 8)) 0 surf)
                    (ptr-write-u64 (+ bufcr (* id 8)) 0 (extern-call cairo_create surf))
                    0))))
              ((= op 10)
               (let ((id (ptr-read-u64 rec 8)))
                 (let ((surf (extern-call cairo_image_surface_create_from_png
                                          (+ blob_base (- (ptr-read-u64 rec 88) 1)))))
                   (seq
                    (ptr-write-u64 (+ bufsurf (* id 8)) 0 surf)
                    (ptr-write-u64 (+ bufcr (* id 8)) 0 (extern-call cairo_create surf))
                    0))))
              ((= op 1)
               (ptr-write-u64 ctx 72 (ptr-read-u64 (+ bufcr (* (ptr-read-u64 rec 8) 8)) 0)))
              ((= op 2)
               (extern-call cairo_set_source_rgb (ptr-read-u64 ctx 72)
                            (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                            (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                            (:f64 (bits-to-f64 (ptr-read-u64 rec 24)))))
              ((= op 5)
               (seq
                (extern-call cairo_rectangle (ptr-read-u64 ctx 72)
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 24)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 32))))
                (extern-call cairo_fill (ptr-read-u64 ctx 72))))
              ((= op 3)
               (seq
                (extern-call cairo_select_font_face (ptr-read-u64 ctx 72)
                             (+ blob_base (- (ptr-read-u64 rec 88) 1)) 0 0)
                (extern-call cairo_set_font_size (ptr-read-u64 ctx 72)
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8))))))
              ((= op 8)
               (seq
                (extern-call cairo_move_to (ptr-read-u64 ctx 72)
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 16))))
                (extern-call cairo_show_text (ptr-read-u64 ctx 72)
                             (+ blob_base (- (ptr-read-u64 rec 88) 1)))))
              ((= op 12)
               (let ((dcr (ptr-read-u64 ctx 72))
                     (ssurf (ptr-read-u64 (+ bufsurf (* (ptr-read-u64 rec 8) 8)) 0)))
                 (seq
                  (extern-call cairo_save dcr)
                  (extern-call cairo_translate dcr
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 24))))
                  (extern-call cairo_scale dcr
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 64)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 72))))
                  (extern-call cairo_set_source_surface dcr ssurf
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 32)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 40))))
                  (extern-call cairo_rectangle dcr (:f64 0.0) (:f64 0.0)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 48)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 56))))
                  (extern-call cairo_fill dcr)
                  (extern-call cairo_restore dcr)
                  0)))
              (t 0))))
         (ptr-write-u64 ctx 40 (+ (ptr-read-u64 ctx 40) 1))))
      0)))

 (defun on_draw (area cr width height ctx)
   (seq
    (extern-call cairo_set_source_surface cr (ptr-read-u64 ctx 80) (:f64 0.0) (:f64 0.0))
    (extern-call cairo_paint cr)
    0))

 (defun on_quit (ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 0)) 0))
 (defun on_destroy (widget ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 0)) 0))

 (defun main ()
   (seq
    (extern-call gtk_init)
    (let ((fp (extern-call fopen (data-addr binpath) (data-addr mode_rb))))
      (if (= fp 0)
          1
        (seq
         (extern-call fseek fp 0 2)
         (let ((size (extern-call ftell fp)))
           (seq
            (extern-call fseek fp 0 0)
            (let ((buf (extern-call malloc size))
                  (ctx (extern-call malloc 96))
                  (bufsurf (extern-call calloc 256 8))
                  (bufcr (extern-call calloc 256 8)))
              (seq
               (extern-call fread buf 1 size fp)
               (extern-call fclose fp)
               (ptr-write-u64 ctx 8 buf)
               (ptr-write-u64 ctx 16 (+ buf (ptr-read-u64 buf 24)))
               (ptr-write-u64 ctx 24 (+ buf (ptr-read-u64 buf 32)))
               (ptr-write-u64 ctx 32 (ptr-read-u64 buf 0))
               (ptr-write-u64 ctx 56 bufsurf)
               (ptr-write-u64 ctx 64 bufcr)
               (process_stream ctx)
               (ptr-write-u64 ctx 80 (ptr-read-u64 bufsurf 0))
               (let ((window (extern-call gtk_window_new)))
                 (seq
                  (extern-call gtk_window_set_title window (data-addr title))
                  (extern-call gtk_window_set_default_size window
                               (ptr-read-u64 buf 8) (ptr-read-u64 buf 16))
                  (let ((area (extern-call gtk_drawing_area_new))
                        (loop (extern-call g_main_loop_new 0 0)))
                    (seq
                     (ptr-write-u64 ctx 0 loop)
                     (ptr-write-u64 ctx 48 area)
                     (extern-call gtk_widget_set_size_request area
                                  (ptr-read-u64 buf 8) (ptr-read-u64 buf 16))
                     (extern-call gtk_drawing_area_set_draw_func area (addr-of on_draw) ctx 0)
                     (extern-call gtk_window_set_child window area)
                     (extern-call g_signal_connect_data
                                  window (data-addr sig_destroy) (addr-of on_destroy) ctx 0 0)
                     (extern-call g_timeout_add 30000 (addr-of on_quit) ctx)
                     (extern-call gtk_window_present window)
                     (extern-call g_main_loop_run loop)
                     0))))))))))))))
