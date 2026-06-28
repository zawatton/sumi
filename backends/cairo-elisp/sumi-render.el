;; sumi-render.el — NeLisp AOT runtime interpreter for the sumi command stream.
;;
;; A FIXED native GTK4 program (no Rust, no emacs-ffi-call): it reads a packed
;; command frame produced by frame-to-bin.js at RUN TIME and renders it via
;; cairo.  Swapping the .bin re-renders without recompiling — the foundation for
;; live (TCP) rendering, where the .bin read is later replaced by a socket recv.
;;
;; .bin layout (u64 LE): [0]num_cmds [8]W [16]H [24]blob_off [32]cmd_off
;;   blob: NUL-terminated strings ; records (48B): op a0 a1 a2 a3 toff
;;   numeric args are f64 BITS (converter pre-divided colours by 255), so the
;;   interpreter only does bits-to-f64 — no f64 arithmetic.
;;   opcodes: 2 set-color  3 set-font  5 fill-rect  6 draw-line  7 draw-point
;;            8 draw-text
;;
;; ctx: 0 loop  8 buf  16 blob_base  24 cmd_base  32 num_cmds  40 i
(seq
 (data-blob binpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-frame.bin\0" rodata)
 (data-blob mode_rb "rb\0" rodata)
 (data-blob title   "sumi-render (NeLisp AOT runtime interpreter)\0" rodata)
 (data-blob sig_destroy "destroy\0" rodata)

 ;; Interpret the command array, dispatching each opcode to cairo.
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
                  (ctx (extern-call malloc 64)))
              (seq
               (extern-call fread buf 1 size fp)
               (extern-call fclose fp)
               (ptr-write-u64 ctx 8 buf)
               (ptr-write-u64 ctx 16 (+ buf (ptr-read-u64 buf 24)))
               (ptr-write-u64 ctx 24 (+ buf (ptr-read-u64 buf 32)))
               (ptr-write-u64 ctx 32 (ptr-read-u64 buf 0))
               (let ((window (extern-call gtk_window_new)))
                 (seq
                  (extern-call gtk_window_set_title window (data-addr title))
                  (extern-call gtk_window_set_default_size window
                               (ptr-read-u64 buf 8) (ptr-read-u64 buf 16))
                  (let ((area (extern-call gtk_drawing_area_new))
                        (loop (extern-call g_main_loop_new 0 0)))
                    (seq
                     (ptr-write-u64 ctx 0 loop)
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
