;;; build-live.el --- Build cairo-elisp live renderer -*- lexical-binding: t; -*-

(require 'cl-lib)

(defconst sumi-build-root
  (expand-file-name "../.." (file-name-directory (or load-file-name buffer-file-name))))

(defconst sumi-build-backend-dir
  (expand-file-name "backends/cairo-elisp" sumi-build-root))

(defconst sumi-build-nelisp-root
  (expand-file-name "../nelisp" sumi-build-root))

(defun sumi-build-env-or (name fallback)
  "Return environment NAME unless it is empty, otherwise FALLBACK."
  (let ((value (getenv name)))
    (if (and value (not (string-empty-p value))) value fallback)))

(defconst sumi-build-mingw-bin
  (sumi-build-env-or "MINGW_BIN" "C:/msys64/mingw64/bin"))

(defconst sumi-build-pkg-config-path
  (sumi-build-env-or "PKG_CONFIG_PATH" "/c/msys64/mingw64/lib/pkgconfig"))

(defun sumi-build-prepend-path (path)
  "Prepend PATH to the process PATH."
  (setenv "PATH" (concat path path-separator (or (getenv "PATH") ""))))

(defun sumi-build-process-lines (program &rest args)
  "Run PROGRAM with ARGS and return output lines."
  (with-temp-buffer
    (let ((status (apply #'call-process program nil t nil args)))
      (unless (eq status 0)
        (error "%s %s failed: %s" program (mapconcat #'identity args " ") (buffer-string)))
      (split-string (string-trim (buffer-string)) "[\r\n]+" t))))

(defun sumi-build-compile-to-object (src obj)
  "Compile Elisp SRC to COFF object OBJ with the NeLisp AOT compiler."
  (add-to-list 'load-path (expand-file-name "lisp" sumi-build-nelisp-root))
  (add-to-list 'load-path (expand-file-name "src" sumi-build-nelisp-root))
  (require 'nelisp-aot-compiler)
  (with-temp-buffer
    (insert-file-contents src)
    (goto-char (point-min))
    (nelisp-aot-compile-to-object (read (current-buffer)) obj :format 'coff)))

(defun sumi-build-link-exe (obj exe libs)
  "Link OBJ to EXE using gcc and LIBS."
  (let ((status (apply #'call-process "gcc" nil t nil obj (append libs (list "-o" exe)))))
    (unless (eq status 0)
      (error "gcc link failed for %s" exe))))

(defun sumi-build-one (stem libs)
  "Build renderer source STEM using LIBS."
  (let* ((src (expand-file-name (concat stem ".el") sumi-build-backend-dir))
         (obj (expand-file-name (concat stem ".o") sumi-build-backend-dir))
         (exe (expand-file-name (concat stem ".exe") sumi-build-backend-dir)))
    (princ (format "=== compile-to-object %s -> %s ===\n" src obj))
    (condition-case err
        (progn
          (sumi-build-compile-to-object src obj)
          (princ "OBJ-OK\n"))
      (error
       (princ (format "OBJ-ERR %S\n" err))
       (kill-emacs 1)))
    (princ (format "=== link -> %s ===\n" exe))
    (sumi-build-link-exe obj exe libs)
    exe))

(defun sumi-build-main ()
  "Build live and dump renderer executables."
  (sumi-build-prepend-path sumi-build-mingw-bin)
  (setenv "PKG_CONFIG_PATH" sumi-build-pkg-config-path)
  (setenv "HOME" (expand-file-name ".tmp-home/sumi-emacs-home" sumi-build-backend-dir))
  (make-directory (getenv "HOME") t)
  (let ((libs (split-string (car (sumi-build-process-lines "pkg-config" "--libs" "gtk4")) " " t)))
    (sumi-build-one "sumi-sprite-live" libs)
    (sumi-build-one "sumi-sprite-dump" libs)
    (princ "BUILD-LIVE-OK\n")))

(when noninteractive
  (sumi-build-main))

;;; build-live.el ends here
