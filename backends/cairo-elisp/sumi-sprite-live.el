;; sumi-sprite-live.el - NeLisp AOT live sprite renderer for sumi.
;;
;; Watches sumi-sprite.bin and re-applies each new frame to PERSISTENT buffers
;; (allocated once), so the NeLisp/Elisp live feed renders natively.  load-image
;; / screen only run when the buffer is empty (bufsurf[id]==0), so sprite PNGs
;; decode once even though the feed re-sends the setup every frame; per-frame
;; draws (clear, blits) re-run each tick.  All
;; cairo draws are guarded against a null current cr and out-of-range buffer ids
;; so the varied real-game stream cannot fault.  Buffer 0 is shown in the window.
;;
;; Record (96B): [0]op a0..a9 [11]toff.  See sumi-sprite.el for the opcode map.
;; ctx: 0 loop 8 buf(fixed 4MB) 16 blob_base 24 cmd_base 32 num_cmds 40 i
;;      48 area 56 bufsurf[1024] 64 bufcr[1024] 72 cur_cr 80 screen_surf
;;      88 alpha_bits 96 key_seq 104 held_count 112 held_keys[8]
;;      176 active_keycode 184 key_state_path 192 last_applied
;;      200 color_r_bits 208 color_g_bits 216 color_b_bits
;;      224 scratch[288]
;;      512 window 520 output_w 528 output_h 536 hwnd 544 f1_down
;;      552 resize_seen 560 selftest_env[208] 768 text_tmp
(seq
 (data-blob binpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-sprite.bin\0" rodata)
 (data-blob headpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-sprite-head.txt\0" rodata)
 (data-blob seqprefix "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-sprite-\0" rodata)
 (data-blob seqsuffix ".bin\0" rodata)
 (data-blob mode_rb "rb\0" rodata)
 (data-blob mode_wb "wb\0" rodata)
 (data-blob title "sumi-sprite-live (NeLisp AOT, live game)\0" rodata)
 (data-blob sig_destroy "destroy\0" rodata)
 (data-blob sig_active "notify::is-active\0" rodata)
 (data-blob sig_keyprs "key-pressed\0" rodata)
 (data-blob sig_keyrel "key-released\0" rodata)
 (data-blob snappath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/buffer0_live.png\0" rodata)
 (data-blob font_meiryo "Meiryo\0" rodata)
 (data-blob env_key_state "SUMI_KEY_STATE\0" rodata)
 (data-blob env_key_selftest "SUMI_KEY_SELFTEST\0" rodata)
 (data-blob default_key_state "C:/Users/kuroz/Cowork/Notes/dev/newDTW-nelisp/build/key-state.txt\0" rodata)
 (data-blob selftest_mid_label "SELFTEST-MID\0" rodata)
 (data-blob selftest_final_label "SELFTEST-FINAL\0" rodata)
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
    ((= keyval 65470) 112)
    ((= keyval 65471) 113)
    ((= keyval 65472) 114)
    ((= keyval 65473) 115)
    ((= keyval 65474) 116)
    ((= keyval 65475) 117)
    ((= keyval 65476) 118)
    ((= keyval 65477) 119)
    ((= keyval 65478) 120)
    ((= keyval 65479) 121)
    ((= keyval 65480) 122)
    ((= keyval 65481) 123)
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

 (defun parse_u64_dec (src)
   (let ((i 0)
         (n 0)
         (b 0))
     (seq
      (while (and (>= (setq b (ptr-read-u8 src i)) 48) (<= b 57))
        (seq
         (setq n (+ (* n 10) (- b 48)))
         (setq i (+ i 1))))
      n)))

 (defun utf8_cont_p (b)
   (= (logand b 192) 128))

 (defun cp932_lead_p (b)
   (or (and (>= b 129) (<= b 159))
       (and (>= b 224) (<= b 252))))

 (defun cp932_trail_p (b)
   (or (and (>= b 64) (<= b 126))
       (and (>= b 128) (<= b 252))))

 (defun utf8_seq_len_at (src i)
   (let ((b0 (ptr-read-u8 src i))
         (b1 (ptr-read-u8 src (+ i 1)))
         (b2 (ptr-read-u8 src (+ i 2)))
         (b3 (ptr-read-u8 src (+ i 3))))
     (if (< b0 128)
         1
       (if (and (>= b0 194) (<= b0 223)
                (utf8_cont_p b1))
           2
         (if (and (= b0 224)
                  (>= b1 160) (<= b1 191)
                  (utf8_cont_p b2))
             3
           (if (and (or (and (>= b0 225) (<= b0 236))
                        (and (>= b0 238) (<= b0 239)))
                    (utf8_cont_p b1)
                    (utf8_cont_p b2))
               3
             (if (and (= b0 237)
                      (>= b1 128) (<= b1 159)
                      (utf8_cont_p b2))
                 3
               (if (and (= b0 240)
                        (>= b1 144) (<= b1 191)
                        (utf8_cont_p b2)
                        (utf8_cont_p b3))
                   4
                 (if (and (>= b0 241) (<= b0 243)
                          (utf8_cont_p b1)
                          (utf8_cont_p b2)
                          (utf8_cont_p b3))
                     4
                   (if (and (= b0 244)
                            (>= b1 128) (<= b1 143)
                            (utf8_cont_p b2)
                            (utf8_cont_p b3))
                       4
                     0))))))))))

 (defun append_utf8_codepoint (dst off cp)
   (if (< cp 128)
       (seq
        (ptr-write-u8 dst off cp)
        (+ off 1))
     (if (< cp 2048)
         (seq
          (ptr-write-u8 dst off (+ 192 (/ cp 64)))
          (ptr-write-u8 dst (+ off 1) (+ 128 (logand cp 63)))
          (+ off 2))
       (if (< cp 65536)
           (seq
            (ptr-write-u8 dst off (+ 224 (/ cp 4096)))
            (ptr-write-u8 dst (+ off 1) (+ 128 (logand (/ cp 64) 63)))
            (ptr-write-u8 dst (+ off 2) (+ 128 (logand cp 63)))
            (+ off 3))
         (seq
          (ptr-write-u8 dst off (+ 240 (/ cp 262144)))
          (ptr-write-u8 dst (+ off 1) (+ 128 (logand (/ cp 4096) 63)))
          (ptr-write-u8 dst (+ off 2) (+ 128 (logand (/ cp 64) 63)))
          (ptr-write-u8 dst (+ off 3) (+ 128 (logand cp 63)))
          (+ off 4))))))

 (defun append_utf8_replacement (dst off)
   (append_utf8_codepoint dst off 65533))

 (defun sanitize_text_for_cairo (ctx src)
   (let ((dst (ptr-read-u64 ctx 768))
         (i 0)
         (off 0)
         (b 0)
         (n 0))
     (seq
      (if (= dst 0)
          src
        (seq
         (while (and (< i 4095) (< off 16379))
           (seq
            (setq b (ptr-read-u8 src i))
            (if (= b 0)
                (setq i 4095)
              (seq
               (setq n (utf8_seq_len_at src i))
               (if (> n 0)
                   (seq
                    (while (> n 0)
                      (seq
                       (ptr-write-u8 dst off (ptr-read-u8 src i))
                       (setq off (+ off 1))
                       (setq i (+ i 1))
                       (setq n (- n 1)))))
                 (if (and (>= b 161) (<= b 223))
                     (seq
                      (setq off (append_utf8_codepoint dst off (+ 65377 (- b 161))))
                      (setq i (+ i 1)))
                   (if (and (cp932_lead_p b)
                            (cp932_trail_p (ptr-read-u8 src (+ i 1))))
                       (seq
                        (setq off (append_utf8_replacement dst off))
                        (setq i (+ i 2)))
                     (seq
                      (setq off (append_utf8_replacement dst off))
                      (setq i (+ i 1))))))))))
         (ptr-write-u8 dst off 0)
         dst)))))

 (defun clear_held_keys (ctx)
   (let ((base (+ ctx 112))
         (i 0))
     (seq
      (ptr-write-u64 ctx 104 0)
      (ptr-write-u64 ctx 176 0)
      (while (< i 8)
        (seq
         (ptr-write-u64 (+ base (* i 8)) 0 0)
         (setq i (+ i 1))))
      0)))

 (defun find_held_key_index (ctx keycode)
   (let ((base (+ ctx 112))
         (count (ptr-read-u64 ctx 104))
         (i 0)
         (found 8)
         (slot 0))
     (seq
      (while (< i count)
        (seq
         (setq slot (ptr-read-u64 (+ base (* i 8)) 0))
         (if (= slot keycode)
             (setq found i)
           0)
         (if (= found 8)
             (setq i (+ i 1))
           (setq i count))))
      found)))

 (defun add_held_key (ctx keycode)
   (let ((base (+ ctx 112))
         (count (ptr-read-u64 ctx 104))
         (idx 0)
         (i 0))
     (seq
      (setq idx (find_held_key_index ctx keycode))
      (if (< idx count)
          0
        (if (< count 8)
            (seq
             (ptr-write-u64 (+ base (* count 8)) 0 keycode)
             (ptr-write-u64 ctx 104 (+ count 1))
             1)
          (seq
           (setq i 1)
           (while (< i 8)
             (seq
              (ptr-write-u64 (+ base (* (- i 1) 8)) 0
                             (ptr-read-u64 (+ base (* i 8)) 0))
              (setq i (+ i 1))))
           (ptr-write-u64 (+ base 56) 0 keycode)
           1))))))

 (defun sync_active_keycode (ctx)
   (let ((count (ptr-read-u64 ctx 104))
         (base (+ ctx 112))
         (last 0))
     (seq
      (if (= count 0)
          (ptr-write-u64 ctx 176 0)
        (seq
         (setq last (ptr-read-u64 (+ base (* (- count 1) 8)) 0))
         (ptr-write-u64 ctx 176 last)))
      0)))

 (defun remove_held_key (ctx keycode)
   (let ((base (+ ctx 112))
         (count (ptr-read-u64 ctx 104))
         (idx 0)
         (i 0)
         (last_idx 0))
     (seq
      (setq idx (find_held_key_index ctx keycode))
      (if (>= idx count)
          0
        (seq
         (setq last_idx (- count 1))
         (setq i idx)
         (while (< i last_idx)
           (seq
            (ptr-write-u64 (+ base (* i 8)) 0
                           (ptr-read-u64 (+ base (* (+ i 1) 8)) 0))
            (setq i (+ i 1))))
         (ptr-write-u64 (+ base (* last_idx 8)) 0 0)
         (ptr-write-u64 ctx 104 last_idx)
         (sync_active_keycode ctx)
         1)))))

 (defun write_key_state (ctx keycode)
   (let ((path (ptr-read-u64 ctx 184)))
     (if (= path 0)
         0
       (let ((fp (extern-call fopen path (data-addr mode_wb))))
         (if (= fp 0)
             0
           (let ((sortbuf (+ ctx 224))
                 (buf (+ ctx 288))
                 (off 0)
                 (seqno (+ (ptr-read-u64 ctx 96) 1))
                 (token 0)
                 (count (ptr-read-u64 ctx 104))
                 (base (+ ctx 112))
                 (i 0)
                 (j 0)
                 (a 0)
                 (b 0))
             (seq
              (ptr-write-u64 ctx 96 seqno)
              (setq token (token_ptr_for_keycode keycode))
              (while (< i count)
                (seq
                 (ptr-write-u64 (+ sortbuf (* i 8)) 0
                                (ptr-read-u64 (+ base (* i 8)) 0))
                 (setq i (+ i 1))))
              (setq i 0)
              (while (< i count)
                (seq
                 (setq j (+ i 1))
                 (while (< j count)
                   (seq
                    (setq a (ptr-read-u64 (+ sortbuf (* i 8)) 0))
                    (setq b (ptr-read-u64 (+ sortbuf (* j 8)) 0))
                    (if (> a b)
                        (seq
                         (ptr-write-u64 (+ sortbuf (* i 8)) 0 b)
                         (ptr-write-u64 (+ sortbuf (* j 8)) 0 a))
                      0)
                    (setq j (+ j 1))))
                 (setq i (+ i 1))))
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
              (setq i 0)
              (while (< i count)
                (seq
                 (ptr-write-u8 buf off 32)
                 (setq off (+ off 1))
                 (setq off (+ off (write_u64_dec (+ buf off)
                                                 (ptr-read-u64 (+ sortbuf (* i 8)) 0))))
                 (setq i (+ i 1))))
              (ptr-write-u8 buf off 10)
              (setq off (+ off 1))
              (extern-call fwrite buf 1 off fp)
              (extern-call fclose fp)
              0)))))))

 (defun refresh_held_key_state (ctx)
   (let ((count (ptr-read-u64 ctx 104))
         (active (ptr-read-u64 ctx 176)))
     (if (> count 0)
         (write_key_state ctx active)
       0)))

 (defun dump_key_state_stdout (ctx label)
   (let ((path (ptr-read-u64 ctx 184)))
     (if (= path 0)
         0
       (let ((fp (extern-call fopen path (data-addr mode_rb))))
         (if (= fp 0)
             0
           (let ((buf (+ ctx 224))
                 (nread 0))
             (seq
              (setq nread (extern-call fread buf 1 255 fp))
              (ptr-write-u8 buf nread 0)
              (extern-call fclose fp)
              (extern-call puts label)
              (extern-call puts buf)
              0)))))))

 (defun run_key_selftest (ctx)
   (seq
    (clear_held_keys ctx)
    (ptr-write-u64 ctx 96 0)
    (add_held_key ctx 37)
    (ptr-write-u64 ctx 176 37)
    (write_key_state ctx 37)
    (add_held_key ctx 38)
    (ptr-write-u64 ctx 176 38)
    (write_key_state ctx 38)
    (refresh_held_key_state ctx)
    (dump_key_state_stdout ctx (data-addr selftest_mid_label))
    (remove_held_key ctx 37)
    (write_key_state ctx 38)
    (remove_held_key ctx 38)
    (write_key_state ctx 0)
    (dump_key_state_stdout ctx (data-addr selftest_final_label))
    0))

 (defun load_frame (ctx path)
   (let ((fp (extern-call fopen path (data-addr mode_rb))))
     (if (= fp 0)
         0
       (let ((buf (ptr-read-u64 ctx 8)))
         (seq
          (extern-call fseek fp 0 2)
          (let ((size (extern-call ftell fp)))
            (if (or (< size 40) (> size 4194304))
                (seq
                 (extern-call fclose fp)
                 0)
              (seq
               (extern-call fseek fp 0 0)
               (let ((nread (extern-call fread buf 1 size fp)))
                 (seq
                  (extern-call fclose fp)
                  (if (not (= nread size))
                      0
                    (let ((ncmd (ptr-read-u64 buf 0))
                          (blob_off (ptr-read-u64 buf 24))
                          (cmd_off (ptr-read-u64 buf 32)))
                      (if (or (< blob_off 40)
                              (< cmd_off blob_off)
                              (> blob_off size)
                              (> cmd_off size)
                              (> ncmd 50000)
                              (> (+ cmd_off (* ncmd 96)) size))
                          0
                        (seq
                         (ptr-write-u64 ctx 16 (+ buf blob_off))
                         (ptr-write-u64 ctx 24 (+ buf cmd_off))
                         (ptr-write-u64 ctx 32 ncmd)
                         1))))))))))))))

 (defun read_head (ctx)
   (let ((fp (extern-call fopen (data-addr headpath) (data-addr mode_rb))))
     (if (= fp 0)
         0
       (let ((buf (+ ctx 224)))
         (seq
          (let ((nread (extern-call fread buf 1 255 fp)))
            (ptr-write-u8 buf nread 0))
          (extern-call fclose fp)
          (parse_u64_dec buf))))))

 (defun build_seq_path (ctx n)
   (let ((dst (+ ctx 224))
         (off 0))
     (seq
      (setq off (copy_cstr dst (data-addr seqprefix)))
      (let ((d0 (/ n 100000))
            (d1 (mod (/ n 10000) 10))
            (d2 (mod (/ n 1000) 10))
            (d3 (mod (/ n 100) 10))
            (d4 (mod (/ n 10) 10))
            (d5 (mod n 10)))
        (seq
         (ptr-write-u8 dst off (+ 48 d0))
         (ptr-write-u8 dst (+ off 1) (+ 48 d1))
         (ptr-write-u8 dst (+ off 2) (+ 48 d2))
         (ptr-write-u8 dst (+ off 3) (+ 48 d3))
         (ptr-write-u8 dst (+ off 4) (+ 48 d4))
         (ptr-write-u8 dst (+ off 5) (+ 48 d5))
         (setq off (+ off 6))))
      (setq off (+ off (copy_cstr (+ dst off) (data-addr seqsuffix))))
      (ptr-write-u8 dst off 0)
      dst)))

 (defun apply_source_rgba (ctx cr)
   (extern-call cairo_set_source_rgba cr
                (:f64 (bits-to-f64 (ptr-read-u64 ctx 200)))
                (:f64 (bits-to-f64 (ptr-read-u64 ctx 208)))
                (:f64 (bits-to-f64 (ptr-read-u64 ctx 216)))
                (:f64 (bits-to-f64 (ptr-read-u64 ctx 88)))))

 (defun clear_every_frame_buffer_p (id)
   (or (= id 0) (= id 4) (= id 7) (= id 10) (= id 32)))

 (defun ensure_buffer_surface (ctx id w h)
   (if (or (< id 0) (>= id 1024))
       0
     (let ((bufsurf (ptr-read-u64 ctx 56))
           (bufcr (ptr-read-u64 ctx 64)))
       (if (= (ptr-read-u64 (+ bufsurf (* id 8)) 0) 0)
           (let ((surf (extern-call cairo_image_surface_create 0 w h))
                 (cr 0))
             (seq
              (setq cr (extern-call cairo_create surf))
              (ptr-write-u64 (+ bufsurf (* id 8)) 0 surf)
              (ptr-write-u64 (+ bufcr (* id 8)) 0 cr)
              (extern-call cairo_save cr)
              (extern-call cairo_set_operator cr 0)
              (extern-call cairo_paint cr)
              (extern-call cairo_restore cr)
              (extern-call cairo_select_font_face cr (data-addr font_meiryo) 0 1)
              1))
         1))))

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
                            ;; Fresh work buffers must start transparent so an
                            ;; untouched scratch canvas blits as a no-op.
                            (extern-call cairo_save cr)
                            (extern-call cairo_set_operator cr 0)
                            (extern-call cairo_paint cr)
                            (extern-call cairo_restore cr)
                            (extern-call cairo_select_font_face cr (data-addr font_meiryo) 0 1)
                            0))
                       ;; The bridge repeats gui-screen every frame only to
                       ;; guarantee surface existence.  Some work buffers are
                       ;; genuinely per-frame canvases (screen, overlays,
                       ;; scratch composites) and must clear on every replayed
                       ;; gui-screen or stale pixels leak into later frames.
                         (let ((surf (ptr-read-u64 (+ bufsurf (* id 8)) 0))
                               (old_w 0)
                               (old_h 0))
                           (seq
                            (setq old_w (extern-call cairo_image_surface_get_width surf))
                            (setq old_h (extern-call cairo_image_surface_get_height surf))
                            (if (or (not (= old_w (ptr-read-u64 rec 16)))
                                    (not (= old_h (ptr-read-u64 rec 24))))
                                (let ((new_surf (extern-call cairo_image_surface_create 0
                                                             (ptr-read-u64 rec 16)
                                                             (ptr-read-u64 rec 24)))
                                      (new_cr 0))
                                  (seq
                                   (setq new_cr (extern-call cairo_create new_surf))
                                   (ptr-write-u64 (+ bufsurf (* id 8)) 0 new_surf)
                                   (ptr-write-u64 (+ bufcr (* id 8)) 0 new_cr)
                                   (extern-call cairo_save new_cr)
                                   (extern-call cairo_set_operator new_cr 0)
                                   (extern-call cairo_paint new_cr)
                                   (extern-call cairo_restore new_cr)
                                   (extern-call cairo_select_font_face new_cr (data-addr font_meiryo) 0 1)
                                   0))
                              (if (clear_every_frame_buffer_p id)
                                  (let ((cr (ptr-read-u64 (+ bufcr (* id 8)) 0)))
                                    (seq
                                     (extern-call cairo_save cr)
                                     (extern-call cairo_set_operator cr 0)
                                     (extern-call cairo_paint cr)
                                     (extern-call cairo_restore cr)
                                     0))
                                0)))))
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
                            (extern-call cairo_select_font_face cr (data-addr font_meiryo) 0 1)
                            0))
                       0)
                   0)))
              ((= op 1)
               (let ((id (ptr-read-u64 rec 8)))
                 (if (< id 1024)
                     (seq
                      (ensure_buffer_surface ctx id 340 340)
                      (ptr-write-u64 ctx 72 (ptr-read-u64 (+ bufcr (* id 8)) 0)))
                   (ptr-write-u64 ctx 72 0))))
              ((= op 13)
               (seq
                (ptr-write-u64 ctx 88 (ptr-read-u64 rec 8))
                (let ((cr (ptr-read-u64 ctx 72)))
                  (if (= cr 0) 0
                    (apply_source_rgba ctx cr)))))
              ((= op 14)
               0)
              ((= op 2)
               (seq
                (ptr-write-u64 ctx 200 (ptr-read-u64 rec 8))
                (ptr-write-u64 ctx 208 (ptr-read-u64 rec 16))
                (ptr-write-u64 ctx 216 (ptr-read-u64 rec 24))
                (let ((cr (ptr-read-u64 ctx 72)))
                  (if (= cr 0) 0
                    (apply_source_rgba ctx cr)))))
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
                               (+ blob_base (- (ptr-read-u64 rec 88) 1)) 0 1)
                  (extern-call cairo_set_font_size (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))))))
              ((= op 8)
               (if (= (ptr-read-u64 ctx 72) 0) 0
                 (seq
                  (extern-call cairo_move_to (ptr-read-u64 ctx 72)
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 8)))
                               (:f64 (bits-to-f64 (ptr-read-u64 rec 16))))
                  (extern-call cairo_show_text (ptr-read-u64 ctx 72)
                               (sanitize_text_for_cairo
                                ctx (+ blob_base (- (ptr-read-u64 rec 88) 1)))))))
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
              ((= op 15)
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
                                         (:f64 (bits-to-f64 (ptr-read-u64 rec 80))))
                            (extern-call cairo_restore dcr)
                            0)))
                     0))))
              ((= op 16)
               (let ((dcr (let ((c (ptr-read-u64 ctx 72)))
                            (if (= c 0) (ptr-read-u64 bufcr 0) c)))
                     (src (ptr-read-u64 rec 8))
                     (count (ptr-read-u64 rec 16))
                     (items (+ blob_base (- (ptr-read-u64 rec 24) 1)))
                     (j 0))
                 (if (= dcr 0) 0
                   (if (< src 1024)
                       (let ((ssurf (ptr-read-u64 (+ bufsurf (* src 8)) 0)))
                         (if (= ssurf 0) 0
                           (seq
                            (while (and (< j count) (< j 4096))
                              (let ((item (+ items (* j 64))))
                                (seq
                                 (extern-call cairo_save dcr)
                                 (extern-call cairo_translate dcr
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 0)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 8))))
                                 (extern-call cairo_scale dcr
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 48)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 56))))
                                 (extern-call cairo_set_source_surface dcr ssurf
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 16)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 24))))
                                 (extern-call cairo_rectangle dcr (:f64 0.0) (:f64 0.0)
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 32)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 40))))
                                 (extern-call cairo_clip dcr)
                                 (extern-call cairo_paint_with_alpha dcr
                                              (:f64 (bits-to-f64 (ptr-read-u64 ctx 88))))
                                 (extern-call cairo_restore dcr)
                                 (setq j (+ j 1)))))
                            0)))
                     0))))
              ((= op 17)
               (let ((dcr (let ((c (ptr-read-u64 ctx 72)))
                            (if (= c 0) (ptr-read-u64 bufcr 0) c)))
                     (srca (ptr-read-u64 rec 8))
                     (srcb (ptr-read-u64 rec 16))
                     (count (ptr-read-u64 rec 24))
                     (items (+ blob_base (- (ptr-read-u64 rec 32) 1)))
                     (alpha-a (ptr-read-u64 rec 40))
                     (alpha-b (ptr-read-u64 rec 48))
                     (j 0))
                 (if (= dcr 0) 0
                   (if (and (< srca 1024) (< srcb 1024))
                       (let ((surf-a (ptr-read-u64 (+ bufsurf (* srca 8)) 0))
                             (surf-b (ptr-read-u64 (+ bufsurf (* srcb 8)) 0)))
                         (if (or (= surf-a 0) (= surf-b 0)) 0
                           (seq
                            (while (and (< j count) (< j 4096))
                              (let ((item (+ items (* j 64))))
                                (seq
                                 (extern-call cairo_save dcr)
                                 (extern-call cairo_translate dcr
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 0)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 8))))
                                 (extern-call cairo_scale dcr
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 48)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 56))))
                                 (extern-call cairo_rectangle dcr (:f64 0.0) (:f64 0.0)
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 32)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 40))))
                                 (extern-call cairo_clip dcr)
                                 (extern-call cairo_set_source_surface dcr surf-a
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 16)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 24))))
                                 (extern-call cairo_paint_with_alpha dcr
                                              (:f64 (bits-to-f64 alpha-a)))
                                 (extern-call cairo_set_source_surface dcr surf-b
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 16)))
                                              (:f64 (bits-to-f64 (ptr-read-u64 item 24))))
                                 (extern-call cairo_paint_with_alpha dcr
                                              (:f64 (bits-to-f64 alpha-b)))
                                 (extern-call cairo_restore dcr)
                                 (setq j (+ j 1)))))
                            0)))
                     0))))
              ((= op 18)
               (let ((cr (ptr-read-u64 ctx 72))
                     (count (ptr-read-u64 rec 8))
                     (items (+ blob_base (- (ptr-read-u64 rec 16) 1)))
                     (j 0))
                 (if (= cr 0) 0
                   (seq
                    (while (and (< j count) (< j 4096))
                      (let ((item (+ items (* j 24))))
                        (seq
                         (extern-call cairo_move_to cr
                                      (:f64 (bits-to-f64 (ptr-read-u64 item 0)))
                                      (:f64 (bits-to-f64 (ptr-read-u64 item 8))))
                         (extern-call cairo_show_text cr
                                      (sanitize_text_for_cairo
                                       ctx (+ blob_base (- (ptr-read-u64 item 16) 1))))
                         (setq j (+ j 1)))))
                    0))))
              (t 0))))
         (ptr-write-u64 ctx 40 (+ (ptr-read-u64 ctx 40) 1))))
      0)))

 (defun set_output_size (ctx w h)
   (let ((window (ptr-read-u64 ctx 512))
         (area (ptr-read-u64 ctx 48))
         (hwnd (ptr-read-u64 ctx 536))
         ;; With SetProcessDPIAware in effect the GTK drawing area renders the
         ;; game canvas at 1:1 physical pixels, so the native outer window must
         ;; match the canvas exactly.  The former 3/2 (150% DPI) compensation
         ;; oversized the window and left blank padding on the right and bottom.
         (outer_w w)
         ;; Reserve the GTK titlebar height outside the game canvas.
         (outer_h (+ h 50)))
     (if (= window 0) 0
       (seq
        (ptr-write-u64 ctx 520 w)
        (ptr-write-u64 ctx 528 h)
        (if (= area 0) 0
          (seq
           (extern-call gtk_drawing_area_set_content_width area w)
           (extern-call gtk_drawing_area_set_content_height area h)
           (extern-call gtk_widget_set_size_request area w h)))
        (extern-call gtk_widget_set_size_request window w h)
        (extern-call gtk_window_set_default_size window w h)
        (if (= hwnd 0) 0
          (extern-call SetWindowPos hwnd 0 0 0 outer_w outer_h 2))
        (ptr-write-u64 ctx 552 0)
        0))))

 (defun enforce_output_window_size (ctx)
   (let ((hwnd (ptr-read-u64 ctx 536))
         (w (ptr-read-u64 ctx 520))
         (h (ptr-read-u64 ctx 528))
         (outer_w 0)
         (outer_h 0)
         (seen (ptr-read-u64 ctx 552)))
     (seq
      (setq outer_w w)
      (setq outer_h (+ h 50))
      (if (= hwnd 0)
          (let ((found (extern-call FindWindowA 0 (data-addr title))))
            (if (= found 0) 0
              (seq
               (ptr-write-u64 ctx 536 found)
               (setq hwnd found))))
        0)
      (if (= hwnd 0) 0
        (if (= seen 0)
            (seq
             (extern-call SetWindowPos hwnd 0 0 0 outer_w outer_h 2)
             (ptr-write-u64 ctx 552 1))
          0)))))

 (defun toggle_output_size (ctx)
   (if (= (ptr-read-u64 ctx 520) 680)
       (set_output_size ctx 340 340)
     (set_output_size ctx 680 680)))

 (defun on_tick (ctx)
   (let ((did-frame 0))
     (seq
      (enforce_output_window_size ctx)
      (if (> (ptr-read-u64 ctx 104) 0)
          (refresh_held_key_state ctx)
        0)
      (let ((head (read_head ctx)))
        (if (= head 0)
            (let ((mainres (load_frame ctx (data-addr binpath))))
              (if (= mainres 0)
                  0
                (seq
                 (process_stream ctx)
                 (setq did-frame 1))))
          (seq
           ;; The bridge numbers bins per connection; a head below our
           ;; last_applied means a new session started — resync from 0.
           (if (< head (ptr-read-u64 ctx 192))
               (ptr-write-u64 ctx 192 0)
             0)
           (if (> head (ptr-read-u64 ctx 192))
               (let ((mainres (load_frame ctx (data-addr binpath))))
                 (if (= mainres 0)
                     0
                   (seq
                    (process_stream ctx)
                    (ptr-write-u64 ctx 192 head)
                    (setq did-frame 1))))
             0))))
      (if (= did-frame 1)
          (seq
           (ptr-write-u64 ctx 80 (ptr-read-u64 (ptr-read-u64 ctx 56) 0))
           (extern-call gtk_widget_queue_draw (ptr-read-u64 ctx 48)))
        0)
      1)))

 (defun poll_function_keys (ctx)
   (let ((f1 (extern-call GetAsyncKeyState 112))
         (f2 (extern-call GetAsyncKeyState 113))
         (f3 (extern-call GetAsyncKeyState 114))
         (mask 0)
         (oldmask (ptr-read-u64 ctx 544)))
     (seq
      (if (not (= (logand f1 32768) 0))
          (setq mask (logior mask 1))
        0)
      (if (not (= (logand f2 32768) 0))
          (setq mask (logior mask 2))
        0)
      (if (not (= (logand f3 32768) 0))
          (setq mask (logior mask 4))
        0)
      (if (and (not (= (logand mask 1) 0))
               (= (logand oldmask 1) 0))
          (toggle_output_size ctx)
        0)
      (if (and (not (= (logand mask 2) 0))
               (= (logand oldmask 2) 0))
          (set_output_size ctx 680 680)
        0)
      (if (and (not (= (logand mask 4) 0))
               (= (logand oldmask 4) 0))
          (set_output_size ctx 340 340)
        0)
      (ptr-write-u64 ctx 544 mask))))

 (defun on_key_pressed (controller keyval keycode state ctx)
   (let ((mapped (map_keyval keyval)))
     (seq
      (if (> mapped 0)
          (if (= mapped 112)
              (toggle_output_size ctx)
            (if (= mapped 113)
                (set_output_size ctx 680 680)
              (if (= mapped 114)
                  (set_output_size ctx 340 340)
                (seq
                 (add_held_key ctx mapped)
                 (ptr-write-u64 ctx 176 mapped)
                 (write_key_state ctx mapped)))))
        0)
      1)))

 (defun on_key_released (controller keyval keycode state ctx)
   (let ((mapped (map_keyval keyval))
         (count 0)
         (active 0))
     (seq
      (if (> mapped 0)
          (seq
           (remove_held_key ctx mapped)
           (setq count (ptr-read-u64 ctx 104))
           (if (> count 0)
               (seq
                (setq active (ptr-read-u64 ctx 176))
                (write_key_state ctx active))
             (write_key_state ctx 0)))
        0)
      0)))

 (defun on_active_changed (window pspec ctx)
   (let ((active (extern-call gtk_window_is_active window))
         (count (ptr-read-u64 ctx 104)))
     (seq
      (if (= active 0)
          (if (> count 0)
              (seq
               (clear_held_keys ctx)
               (write_key_state ctx 0))
            0)
        0)
      0)))

 (defun on_draw (area cr width height ctx)
   (seq
    (if (= (ptr-read-u64 ctx 80) 0)
        0
      (seq
       (extern-call cairo_surface_flush (ptr-read-u64 ctx 80))
       (extern-call cairo_save cr)
       (if (not (= (ptr-read-u64 ctx 520) 340))
           (extern-call cairo_rectangle cr (:f64 0.0) (:f64 0.0)
                        (:f64 680.0) (:f64 680.0))
         (extern-call cairo_rectangle cr (:f64 0.0) (:f64 0.0)
                      (:f64 340.0) (:f64 340.0)))
       (extern-call cairo_clip cr)
       ;; GTK callback dimensions are DPI-virtualized on Windows.  The
       ;; renderer's output mode is the stable source of truth for the
       ;; 340px game surface transform.
       (if (= (ptr-read-u64 ctx 520) 680)
           (extern-call cairo_scale cr (:f64 2.0) (:f64 2.0))
         (extern-call cairo_scale cr (:f64 1.0) (:f64 1.0)))
       (extern-call cairo_set_source_surface cr (ptr-read-u64 ctx 80) (:f64 0.0) (:f64 0.0))
       (extern-call cairo_pattern_set_filter (extern-call cairo_get_source cr) 3)
       (extern-call cairo_paint cr)
       (extern-call cairo_restore cr)))
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
   (let ((ctx (extern-call malloc 776))
         (buf (extern-call malloc 4194304))
         (bufsurf (extern-call calloc 1024 8))
         (bufcr (extern-call calloc 1024 8))
         (texttmp (extern-call malloc 16384))
         (envbuf (extern-call malloc 260))
         (key_state_n 0)
         (selftest_n 0))
     (seq
      (clear_held_keys ctx)
      (ptr-write-u64 ctx 8 buf)
      (ptr-write-u64 ctx 56 bufsurf)
      (ptr-write-u64 ctx 64 bufcr)
      (ptr-write-u64 ctx 72 0)
      (ptr-write-u64 ctx 88 4607182418800017408)
      (ptr-write-u64 ctx 96 0)
      (ptr-write-u64 ctx 16 0)
      (ptr-write-u64 ctx 24 0)
      (ptr-write-u64 ctx 32 0)
      (ptr-write-u64 ctx 192 0)
      (ptr-write-u64 ctx 200 0)
      (ptr-write-u64 ctx 208 0)
      (ptr-write-u64 ctx 216 0)
      (ptr-write-u64 ctx 512 0)
      (ptr-write-u64 ctx 520 680)
      (ptr-write-u64 ctx 528 680)
      (ptr-write-u64 ctx 544 0)
      (ptr-write-u64 ctx 552 0)
      (ptr-write-u64 ctx 768 texttmp)
      (setq key_state_n (extern-call GetEnvironmentVariableA
                                     (data-addr env_key_state) envbuf 259))
      (if (> key_state_n 0)
          (ptr-write-u64 ctx 184 envbuf)
        (ptr-write-u64 ctx 184 (data-addr default_key_state)))
      (setq selftest_n (extern-call GetEnvironmentVariableA
                                    (data-addr env_key_selftest) (+ ctx 560) 207))
      ;; The env-gated key self-test (SUMI_KEY_SELFTEST) fired even with the
      ;; variable unset — the AOT env read was unreliable — closing the play
      ;; window immediately.  The self-test served only codex's one-off
      ;; verification, so always run the normal window path now.
      (if (= 0 0)
          (seq
           (extern-call SetProcessDPIAware)
           (extern-call gtk_init)
           (if (= (load_frame ctx (data-addr binpath)) 0)
               0
             (process_stream ctx))
           (ptr-write-u64 ctx 80 (ptr-read-u64 bufsurf 0))
           (let ((window (extern-call gtk_window_new)))
             (seq
              (ptr-write-u64 ctx 512 window)
              (extern-call gtk_window_set_title window (data-addr title))
              (extern-call gtk_window_set_decorated window 1)
              (extern-call gtk_widget_set_size_request window
                           680 680)
              (extern-call gtk_window_set_default_size window
                           680 680)
              (let ((area (extern-call gtk_drawing_area_new))
                    (keyctl (extern-call gtk_event_controller_key_new))
                    (loop (extern-call g_main_loop_new 0 0)))
                (seq
                 (ptr-write-u64 ctx 0 loop)
                 (ptr-write-u64 ctx 48 area)
                 (extern-call gtk_drawing_area_set_content_width area
                              680)
                 (extern-call gtk_drawing_area_set_content_height area
                              680)
                 (extern-call gtk_widget_set_size_request area
                              680 680)
                 (extern-call gtk_drawing_area_set_draw_func area (addr-of on_draw) ctx 0)
                 (extern-call gtk_window_set_child window area)
                 (extern-call g_signal_connect_data
                              keyctl (data-addr sig_keyprs) (addr-of on_key_pressed) ctx 0 0)
                 (extern-call g_signal_connect_data
                              keyctl (data-addr sig_keyrel) (addr-of on_key_released) ctx 0 0)
                 (extern-call gtk_widget_set_focusable area 1)
                 (extern-call gtk_widget_add_controller area keyctl)
                 (extern-call g_signal_connect_data
                              window (data-addr sig_active) (addr-of on_active_changed) ctx 0 0)
                 (extern-call g_signal_connect_data
                              window (data-addr sig_destroy) (addr-of on_destroy) ctx 0 0)
                 (extern-call g_timeout_add 16 (addr-of on_tick) ctx)
                 (extern-call g_timeout_add 1800000 (addr-of on_quit) ctx)
                 (extern-call gtk_window_present window)
                 (extern-call gtk_widget_grab_focus area)
                 (let ((hwnd (extern-call FindWindowA 0 (data-addr title))))
                   (ptr-write-u64 ctx 536 hwnd))
                 (set_output_size ctx 680 680)
                 (extern-call g_main_loop_run loop)
                 0)))))
        (run_key_selftest ctx))))))
