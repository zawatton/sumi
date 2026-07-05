;; sumi-sprite-live.el — NeLisp AOT LIVE sprite renderer for sumi (no Rust).
;;
;; Watches sumi-sprite.bin and re-applies each new frame to PERSISTENT buffers
;; (allocated once), so a running game streamed through sprite-bridge.js renders
;; live and natively.  load-image / screen only run when the buffer is empty
;; (bufsurf[id]==0), so sprite PNGs decode once even though the bridge re-sends
;; the setup every frame; per-frame draws (clear, blits) re-run each tick.  All
;; cairo draws are guarded against a null current cr and out-of-range buffer ids
;; so the varied real-game stream cannot fault.  Buffer 0 is shown in the window.
;;
;; Record (96B): [0]op a0..a9 [11]toff.  See sumi-sprite.el for the opcode map.
;; ctx: 0 loop 8 buf(fixed 4MB) 16 blob_base 24 cmd_base 32 num_cmds 40 i
;;      48 area 56 bufsurf[1024] 64 bufcr[1024] 72 cur_cr 80 screen_surf
;;      88 alpha_bits 96 key_seq 104 held_keycode 112 key_state_path 120 reserved
;;      128 key_state_scratch[256]
(seq
 (data-blob binpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-sprite.bin\0" rodata)
 (data-blob mode_rb "rb\0" rodata)
 (data-blob mode_wb "wb\0" rodata)
 (data-blob title   "sumi-sprite-live (NeLisp AOT, live game)\0" rodata)
 (data-blob sig_destroy "destroy\0" rodata)
 (data-blob sig_keyprs "key-pressed\0" rodata)
 (data-blob sig_keyrel "key-released\0" rodata)
 (data-blob snappath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/buffer0_live.png\0" rodata)
 (data-blob font_meiryo "Meiryo\0" rodata)
 (data-blob env_key_state "SUMI_KEY_STATE\0" rodata)
 (data-blob default_key_state "C:/Users/kuroz/Cowork/Notes/dev/newDTW-nelisp/build/key-state.txt\0" rodata)
 (data-blob tok_up "UP\0" rodata)
 (data-blob tok_down "DOWN\0" rodata)
 (data-blob tok_left "LEFT\0" rodata)
 (data-blob tok_right "RIGHT\0" rodata)
 (data-blob tok_idle "IDLE\0" rodata)

 (defun map_keyval (keyval)
   (cond
    ((= keyval 65361) 37)
    ((= keyval 65362) 38)
    ((= keyval 65363) 39)
    ((= keyval 65364) 40)
    ((= keyval 65293) 13)
    ((or (= keyval 65505) (= keyval 65506)) 16)
    ((and (>= keyval 97) (<= keyval 122)) (- keyval 32))
    ((and (>= keyval 65) (<= keyval 90)) keyval)
    ((and (>= keyval 48) (<= keyval 57)) keyval)
    ((= keyval 65307) 27)
    ((= keyval 32) 32)
    (t 0)))

 (defun token_ptr_for_keycode (keycode)
   (if (= keycode 37) (data-addr tok_left)
     (if (= keycode 38) (data-addr tok_up)
       (if (= keycode 39) (data-addr tok_right)
         (if (= keycode 40) (data-addr tok_down)
           (data-addr tok_idle))))))

 (defun copy_cstr (dst src)
   (let ((i 0)
         (b 0))
     (seq
      (while (not (= (setq b (ptr-read-u8 src i)) 0))
        (seq
         (ptr-write-u8 dst i b)
         (setq i (+ i 1))))
      i)))

 (defun write_u64_dec (dst n)
   (if (< n 10)
       (seq
        (ptr-write-u8 dst 0 (+ 48 n))
        1)
     (let ((len (write_u64_dec dst (/ n 10))))
       (seq
        (ptr-write-u8 dst len (+ 48 (mod n 10)))
        (+ len 1)))))

 (defun write_key_state (ctx keycode)
   (let ((path (ptr-read-u64 ctx 112)))
     (if (= path 0)
         0
       (let ((fp (extern-call fopen path (data-addr mode_wb))))
         (if (= fp 0)
             0
           (let ((buf (+ ctx 128))
                 (off 0)
                 (seqno (+ (ptr-read-u64 ctx 96) 1))
                 (token (token_ptr_for_keycode keycode)))
             (seq
              (ptr-write-u64 ctx 96 seqno)
              (setq off (copy_cstr buf token))
              (ptr-write-u8 buf off 32)
              (setq off (+ off 1))
              (setq off (+ off (write_u64_dec (+ buf off) seqno)))
              (ptr-write-u8 buf off 10)
              (setq off (+ off 1))
              (setq off (+ off (write_u64_dec (+ buf off) keycode)))
              (ptr-write-u8 buf off 10)
              (setq off (+ off 1))
              (ptr-write-u8 buf off 72)
              (ptr-write-u8 buf (+ off 1) 69)
              (ptr-write-u8 buf (+ off 2) 76)
              (ptr-write-u8 buf (+ off 3) 68)
              (setq off (+ off 4))
              (if (> keycode 0)
                  (seq
                   (ptr-write-u8 buf off 32)
                   (setq off (+ off 1))
                   (setq off (+ off (write_u64_dec (+ buf off) keycode))))
                0)
              (ptr-write-u8 buf off 10)
              (setq off (+ off 1))
              (extern-call fwrite buf 1 off fp)
              (extern-call fclose fp)
              0)))))))

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

 ;; Apply one frame's commands to the persistent buffers (fault-guarded).
 (defun process_stream (ctx)
   (let ((cmd_base (ptr-read-u64 ctx 24))
         (blob_base (ptr-read-u64 ctx 16))
         (bufsurf (ptr-read-u64 ctx 56))
         (bufcr (ptr-read-u64 ctx 64))
         (ncmd (ptr-read-u64 ctx 32)))
     (seq
      (ptr-write-u64 ctx 40 0)
      (while (and (< (ptr-read-u64 ctx 40) ncmd) (< (ptr-read-u64 ctx 40) 50000))
        (seq
         (let ((rec (+ cmd_base (* (ptr-read-u64 ctx 40) 96))))
           (let ((op (ptr-read-u64 rec 0)))
             (cond
              ((= op 9)
               (let ((id (ptr-read-u64 rec 8)))
                 (if (< id 1024)
                     (if (= (ptr-read-u64 (+ bufsurf (* id 8)) 0) 0)
                         (let ((surf (extern-call cairo_image_surface_create 0
                                                  (ptr-read-u64 rec 16) (ptr-read-u64 rec 24)))
                               (cr 0))
                           (seq
                            (setq cr (extern-call cairo_create surf))
                            (ptr-write-u64 (+ bufsurf (* id 8)) 0 surf)
                            (ptr-write-u64 (+ bufcr (* id 8)) 0 cr)
                            (extern-call cairo_select_font_face cr (data-addr font_meiryo) 0 0)
                            0))
                       ;; existing screen/scratch buffer: clear it each frame so
                       ;; translucent blits don't accumulate across ticks.
                       (let ((cr (ptr-read-u64 (+ bufcr (* id 8)) 0)))
                         (seq
                          (extern-call cairo_save cr)
                          (extern-call cairo_set_operator cr 0)
                          (extern-call cairo_paint cr)
                          (extern-call cairo_restore cr)
                          0)))
                   0)))
              ((= op 10)
               (let ((id (ptr-read-u64 rec 8)))
                 (if (< id 1024)
                     (if (= (ptr-read-u64 (+ bufsurf (* id 8)) 0) 0)
                         (let ((surf (extern-call cairo_image_surface_create_from_png
                                                  (+ blob_base (- (ptr-read-u64 rec 88) 1))))
                               (cr 0))
                           (seq
                            (setq cr (extern-call cairo_create surf))
                            (ptr-write-u64 (+ bufsurf (* id 8)) 0 surf)
                            (ptr-write-u64 (+ bufcr (* id 8)) 0 cr)
                            (extern-call cairo_select_font_face cr (data-addr font_meiryo) 0 0)
                            0))
                       0)
                   0)))
              ((= op 1)
               (let ((id (ptr-read-u64 rec 8)))
                 (if (< id 1024)
                     (ptr-write-u64 ctx 72 (ptr-read-u64 (+ bufcr (* id 8)) 0))
                   (ptr-write-u64 ctx 72 0))))
              ((= op 13)
               (ptr-write-u64 ctx 88 (ptr-read-u64 rec 8)))
              ((= op 2)
               (if (= (ptr-read-u64 ctx 72) 0) 0
                 (extern-call cairo_set_source_rgb (ptr-read-u64 ctx 72)
                              (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                              (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                              (:f64 (bits-to-f64 (ptr-read-u64 rec 24))))))
              ((= op 5)
               (if (= (ptr-read-u64 ctx 72) 0) 0
                 (seq
                  (extern-call cairo_rectangle (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 24)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 32))))
                  (extern-call cairo_fill (ptr-read-u64 ctx 72)))))
              ((= op 6)
               (if (= (ptr-read-u64 ctx 72) 0) 0
                 (seq
                  (extern-call cairo_move_to (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 16))))
                  (extern-call cairo_line_to (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 24)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 32))))
                  (extern-call cairo_set_line_width (ptr-read-u64 ctx 72) (:f64 1.0))
                  (extern-call cairo_stroke (ptr-read-u64 ctx 72)))))
              ((= op 7)
               (if (= (ptr-read-u64 ctx 72) 0) 0
                 (seq
                  (extern-call cairo_rectangle (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 16)))
                               (:f64 1.0) (:f64 1.0))
                  (extern-call cairo_fill (ptr-read-u64 ctx 72)))))
              ((= op 3)
               (if (= (ptr-read-u64 ctx 72) 0) 0
                 (seq
                  (extern-call cairo_select_font_face (ptr-read-u64 ctx 72)
                               (+ blob_base (- (ptr-read-u64 rec 88) 1)) 0 0)
                  (extern-call cairo_set_font_size (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))))))
              ((= op 8)
               (if (= (ptr-read-u64 ctx 72) 0) 0
                 (seq
                  (extern-call cairo_move_to (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 16))))
                  (extern-call cairo_show_text (ptr-read-u64 ctx 72)
                               (+ blob_base (- (ptr-read-u64 rec 88) 1))))))
              ((= op 12)
               (let ((dcr (let ((c (ptr-read-u64 ctx 72)))
                            (if (= c 0) (ptr-read-u64 bufcr 0) c)))
                     (src (ptr-read-u64 rec 8)))
                 (if (= dcr 0) 0
                   (if (< src 1024)
                       (let ((ssurf (ptr-read-u64 (+ bufsurf (* src 8)) 0)))
                         (if (= ssurf 0) 0
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
                            (extern-call cairo_clip dcr)
                            (extern-call cairo_paint_with_alpha dcr
                                         (:f64 (bits-to-f64 (ptr-read-u64 ctx 88))))
                            (extern-call cairo_restore dcr)
                            0)))
                     0))))
              (t 0))))
         (ptr-write-u64 ctx 40 (+ (ptr-read-u64 ctx 40) 1))))
      0)))

 (defun on_tick (ctx)
   (seq
    (if (> (ptr-read-u64 ctx 104) 0)
        (write_key_state ctx (ptr-read-u64 ctx 104))
      0)
    (load_frame ctx)
    (process_stream ctx)
    (ptr-write-u64 ctx 80 (ptr-read-u64 (ptr-read-u64 ctx 56) 0))
    (extern-call gtk_widget_queue_draw (ptr-read-u64 ctx 48))
    1))

 (defun on_key_pressed (controller keyval keycode state ctx)
   (let ((mapped (map_keyval keyval)))
     (seq
      (if (> mapped 0)
          (seq
           (ptr-write-u64 ctx 104 mapped)
           (write_key_state ctx mapped))
        0)
      1)))

 (defun on_key_released (controller keyval keycode state ctx)
   (let ((mapped (map_keyval keyval)))
     (seq
      (if (and (> mapped 0) (= (ptr-read-u64 ctx 104) mapped))
          (seq
           (ptr-write-u64 ctx 104 0)
           (write_key_state ctx 0))
        0)
      0)))

 (defun on_draw (area cr width height ctx)
   (seq
    (if (= (ptr-read-u64 ctx 80) 0)
        0
      (seq
       (extern-call cairo_surface_flush (ptr-read-u64 ctx 80))
       (extern-call cairo_set_source_surface cr (ptr-read-u64 ctx 80) (:f64 0.0) (:f64 0.0))
       (extern-call cairo_paint cr)))
    0))

 (defun on_snapshot (ctx)
   (let ((s0 (ptr-read-u64 (ptr-read-u64 ctx 56) 0)))
     (seq
      (extern-call cairo_surface_flush s0)
      (extern-call cairo_surface_write_to_png s0 (data-addr snappath))
      1)))

 (defun on_quit (ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 0)) 0))
 (defun on_destroy (widget ctx)
   (seq (extern-call g_main_loop_quit (ptr-read-u64 ctx 0)) 0))

 (defun main ()
   (seq
    (extern-call gtk_init)
    (let ((ctx (extern-call malloc 384))
          (buf (extern-call malloc 4194304))
          (bufsurf (extern-call calloc 1024 8))
          (bufcr (extern-call calloc 1024 8)))
      (seq
       (ptr-write-u64 ctx 8 buf)
       (ptr-write-u64 ctx 56 bufsurf)
       (ptr-write-u64 ctx 64 bufcr)
       (ptr-write-u64 ctx 72 0)
       (ptr-write-u64 ctx 88 4607182418800017408)
       (ptr-write-u64 ctx 96 0)
       (ptr-write-u64 ctx 104 0)
       (ptr-write-u64 ctx 112 (let ((p (extern-call getenv (data-addr env_key_state))))
                                (if (= p 0) (data-addr default_key_state) p)))
       (load_frame ctx)
       (process_stream ctx)
       (ptr-write-u64 ctx 80 (ptr-read-u64 bufsurf 0))
       (let ((window (extern-call gtk_window_new)))
         (seq
          (extern-call gtk_window_set_title window (data-addr title))
          (extern-call gtk_window_set_default_size window
                       (ptr-read-u64 buf 8) (ptr-read-u64 buf 16))
          (let ((area (extern-call gtk_drawing_area_new))
                (keyctl (extern-call gtk_event_controller_key_new))
                (loop (extern-call g_main_loop_new 0 0)))
            (seq
             (ptr-write-u64 ctx 0 loop)
             (ptr-write-u64 ctx 48 area)
             (extern-call gtk_widget_set_size_request area
                          (ptr-read-u64 buf 8) (ptr-read-u64 buf 16))
             (extern-call gtk_drawing_area_set_draw_func area (addr-of on_draw) ctx 0)
             (extern-call gtk_window_set_child window area)
             (extern-call g_signal_connect_data
                          keyctl (data-addr sig_keyprs) (addr-of on_key_pressed) ctx 0 0)
             (extern-call g_signal_connect_data
                          keyctl (data-addr sig_keyrel) (addr-of on_key_released) ctx 0 0)
             (extern-call gtk_widget_add_controller window keyctl)
             (extern-call g_signal_connect_data
                          window (data-addr sig_destroy) (addr-of on_destroy) ctx 0 0)
             (extern-call g_timeout_add 50 (addr-of on_tick) ctx)
             (extern-call g_timeout_add 300000 (addr-of on_quit) ctx)
             (extern-call gtk_window_present window)
             (extern-call g_main_loop_run loop)
             0)))))))))
