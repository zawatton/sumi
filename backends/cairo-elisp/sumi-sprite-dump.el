;; sumi-sprite-dump.el — headless variant of the live renderer: read the current
;; sumi-sprite.bin, run the SAME process_stream once into persistent buffers, then
;; write buffer 0 to buffer0.png so the actual composited screen can be inspected.
;; ctx: 0 -  8 buf  16 blob_base  24 cmd_base  32 num_cmds  40 i
;;      56 bufsurf[1024]  64 bufcr[1024]  72 cur_cr
(seq
 (data-blob binpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/sumi-sprite.bin\0" rodata)
 (data-blob outpath "C:/Users/kuroz/Cowork/Notes/dev/sumi/backends/cairo-elisp/buffer0.png\0" rodata)
 (data-blob mode_rb "rb\0" rodata)
 (data-blob font_meiryo "Meiryo\0" rodata)

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

 (defun main ()
   (seq
    (extern-call gtk_init)
    (let ((ctx (extern-call malloc 96))
          (buf (extern-call malloc 4194304))
          (bufsurf (extern-call calloc 1024 8))
          (bufcr (extern-call calloc 1024 8)))
      (seq
       (ptr-write-u64 ctx 8 buf)
       (ptr-write-u64 ctx 56 bufsurf)
       (ptr-write-u64 ctx 64 bufcr)
       (ptr-write-u64 ctx 72 0)
       (ptr-write-u64 ctx 88 4607182418800017408)
       (load_frame ctx)
       (process_stream ctx)
       (process_stream ctx)
       (process_stream ctx)
       (process_stream ctx)
       (process_stream ctx)
       (let ((s0 (ptr-read-u64 bufsurf 0)))
         (seq
          (extern-call cairo_surface_flush s0)
          (extern-call cairo_surface_write_to_png s0 (data-addr outpath))
          0)))))))
