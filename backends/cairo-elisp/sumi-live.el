;; sumi-live.el - NeLisp AOT live sumi renderer.
;;
;; Like sumi-render.el, but it RE-READS the .bin every ~50 ms (a g_timeout
;; "watch" tick) and repaints, so an external writer updating sumi-frame.bin
;; live-updates the window.  The current game path writes .bin frames from the
;; NeLisp/Elisp live feed loop using the native renderer path.
;;
;; .bin layout (u64 LE): [0]num_cmds [8]W [16]H [24]blob_off [32]cmd_off
;;   blob: NUL strings ; records (48B): op a0..a3(f64 bits) toff
;;   opcodes: 2 set-color 3 set-font 5 fill-rect 6 draw-line 7 draw-point 8 draw-text
;;
;; ctx: 0 loop  8 buf(fixed 1MB)  16 blob_base  24 cmd_base  32 num_cmds
;;      40 i  48 area
(seq
 (data-blob binpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-frame.bin\0" rodata)
 (data-blob mode_rb "rb\0" rodata)
 (data-blob title   "sumi-live (NeLisp AOT, .bin watch)\0" rodata)
 (data-blob sig_destroy "destroy\0" rodata)

 ;; Re-read the .bin into the fixed buffer; refresh header-derived pointers.
 (defun load_frame (ctx)
   (let ((fp (extern-call fopen (data-addr binpath) (data-addr mode_rb))))
     (if (= fp 0)
         0
       (let ((buf (ptr-read-u64 ctx 8)))
         (seq
          (extern-call fseek fp 0 2)
          (let ((size (extern-call ftell fp)))
            (seq
             (extern-call fseek fp 0 0)
             (extern-call fread buf 1 size fp)
             (extern-call fclose fp)
             (ptr-write-u64 ctx 16 (+ buf (ptr-read-u64 buf 24)))
             (ptr-write-u64 ctx 24 (+ buf (ptr-read-u64 buf 32)))
             (ptr-write-u64 ctx 32 (ptr-read-u64 buf 0))
             0)))))))

 (defun on_draw (area cr width height ctx)
   (let ((cmd_base (ptr-read-u64 ctx 24))
         (blob_base (ptr-read-u64 ctx 16))
         (ncmd (ptr-read-u64 ctx 32)))
     (seq
      (ptr-write-u64 ctx 40 0)
      (while (< (ptr-read-u64 ctx 40) ncmd)
        (seq
         (let ((rec (+ cmd_base (* (ptr-read-u64 ctx 40) 48))))
           (let ((op (ptr-read-u64 rec 0)))
             (cond
              ((= op 2)
               (extern-call cairo_set_source_rgb cr
                            (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                            (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                            (:f64 (bits-to-f64 (ptr-read-u64 rec 24)))))
              ((= op 5)
               (seq
                (extern-call cairo_rectangle cr
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 24)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 32))))
                (extern-call cairo_fill cr)))
              ((= op 6)
               (seq
                (extern-call cairo_set_line_width cr (:f64 1.0))
                (extern-call cairo_move_to cr
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 16))))
                (extern-call cairo_line_to cr
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 24)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 32))))
                (extern-call cairo_stroke cr)))
              ((= op 3)
               (seq
                (extern-call cairo_select_font_face cr
                             (+ blob_base (- (ptr-read-u64 rec 40) 1)) 0 0)
                (extern-call cairo_set_font_size cr
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8))))))
              ((= op 8)
               (seq
                (extern-call cairo_move_to cr
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 16))))
                (extern-call cairo_show_text cr
                             (+ blob_base (- (ptr-read-u64 rec 40) 1)))))
              ((= op 7)
               (seq
                (extern-call cairo_rectangle cr
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                             (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                             (:f64 1.0) (:f64 1.0))
                (extern-call cairo_fill cr)))
              (t 0))))
         (ptr-write-u64 ctx 40 (+ (ptr-read-u64 ctx 40) 1))))
      0)))

 ;; Watch tick: re-read the .bin and repaint.  G_SOURCE_CONTINUE (1).
 (defun on_tick (ctx)
   (seq
    (load_frame ctx)
    (extern-call gtk_widget_queue_draw (ptr-read-u64 ctx 48))
    1))

 (defun on_quit (ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 0)) 0))
 (defun on_destroy (widget ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 0)) 0))

 (defun main ()
   (seq
    (extern-call gtk_init)
    (let ((ctx (extern-call malloc 64))
          (buf (extern-call malloc 1048576)))
      (seq
       (ptr-write-u64 ctx 8 buf)
       (load_frame ctx)
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
             (extern-call g_timeout_add 50 (addr-of on_tick) ctx)
             (extern-call g_timeout_add 30000 (addr-of on_quit) ctx)
             (extern-call gtk_window_present window)
             (extern-call g_main_loop_run loop)
             0)))))))))
