;;; sumi-cairo.el --- Pure-elisp Cairo backend for sumi (NeLisp native) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 zawatton

;; SPDX-License-Identifier: CC0-1.0

;;; Commentary:

;; The native sumi backend for NeLisp: a *pure elisp* binding that draws the
;; sumi vocabulary by calling libcairo directly through NeLisp's dynamic FFI
;; (`emacs-ffi-call').  This first cut
;; renders to an in-memory Cairo image surface and writes a PNG.
;;
;; Status: READY-TO-TEST, pending one runtime feature.  Cairo's drawing API is
;; double-heavy (`cairo_set_source_rgb', `cairo_rectangle', `cairo_set_font_size'
;; all take C `double's, passed in XMM registers per the SysV/Win64 ABI).  The
;; current `nl-ffi-call' marshals :sint32 / :sint64 / :string / :pointer but not
;; :double (f64) yet.  Every double arg below is declared `:double'; the moment
;; the dynamic FFI gains f64 support, `sumi-cairo-demo' should produce a PNG with
;; no further changes here.
;;
;; libcairo path: Windows/MSYS2 => C:/msys64/mingw64/bin/libcairo-2.dll
;;                Linux          => libcairo.so.2 ; macOS => libcairo.2.dylib
;; Override with `sumi-cairo-library' or the SUMI_CAIRO_LIBRARY env var.

;;; Code:

(require 'emacs-ffi)

(defun sumi-cairo--default-library ()
  "Resolve the default libcairo shared-library path for the host."
  (or (and (fboundp 'getenv) (getenv "SUMI_CAIRO_LIBRARY"))
      (cond
       ((eq system-type 'windows-nt) "C:/msys64/mingw64/bin/libcairo-2.dll")
       ((eq system-type 'darwin) "libcairo.2.dylib")
       (t "libcairo.so.2"))))

(defvar sumi-cairo-library (sumi-cairo--default-library)
  "Absolute path or loader name of the Cairo shared library.")

;; Cairo enum constants used below.
(defconst sumi-cairo-format-argb32 0 "CAIRO_FORMAT_ARGB32.")
(defconst sumi-cairo-font-slant-normal 0 "CAIRO_FONT_SLANT_NORMAL.")
(defconst sumi-cairo-font-weight-normal 0 "CAIRO_FONT_WEIGHT_NORMAL.")
(defconst sumi-cairo-status-success 0 "CAIRO_STATUS_SUCCESS.")

(defun sumi-cairo--call (function signature &rest args)
  "Call cairo FUNCTION (SIGNATURE + ARGS) through the dynamic FFI."
  (apply #'emacs-ffi-call sumi-cairo-library function signature args))

;;;; --- thin cairo wrappers ------------------------------------------------
;; SIGNATURE convention: [RETURN-TYPE ARG-TYPE...].  Pointers (cairo_t*,
;; cairo_surface_t*) are :pointer; cairo doubles are :double.
;;
;; `nl-ffi-call' requires a concrete return type in slot 0 and has no :void,
;; so void-returning cairo functions declare a dummy :sint64 return whose
;; (garbage) value is ignored -- the same pattern emacs-sqlite-ffi.el uses.

(defun sumi-cairo-image-surface-create (width height)
  "Create an ARGB32 image surface of WIDTH x HEIGHT.  Returns a surface pointer."
  (sumi-cairo--call "cairo_image_surface_create"
                    [:pointer :sint32 :sint32 :sint32]
                    sumi-cairo-format-argb32 width height))

(defun sumi-cairo-create (surface)
  "Create a drawing context for SURFACE.  Returns a cairo_t pointer."
  (sumi-cairo--call "cairo_create" [:pointer :pointer] surface))

(defun sumi-cairo-set-source-rgb (cr r g b)
  "Set CR's source colour to (R G B), each a float in [0.0, 1.0]."
  (sumi-cairo--call "cairo_set_source_rgb"
                    [:sint64 :pointer :double :double :double]
                    cr (float r) (float g) (float b)))

(defun sumi-cairo-rectangle (cr x y w h)
  "Add a W x H rectangle at (X Y) to CR's path."
  (sumi-cairo--call "cairo_rectangle"
                    [:sint64 :pointer :double :double :double :double]
                    cr (float x) (float y) (float w) (float h)))

(defun sumi-cairo-fill (cr)
  "Fill CR's current path."
  (sumi-cairo--call "cairo_fill" [:sint64 :pointer] cr))

(defun sumi-cairo-select-font-face (cr family)
  "Select FAMILY (normal slant/weight) for text on CR."
  (sumi-cairo--call "cairo_select_font_face"
                    [:sint64 :pointer :string :sint32 :sint32]
                    cr family sumi-cairo-font-slant-normal sumi-cairo-font-weight-normal))

(defun sumi-cairo-set-font-size (cr size)
  "Set the font SIZE (a float) on CR."
  (sumi-cairo--call "cairo_set_font_size" [:sint64 :pointer :double] cr (float size)))

(defun sumi-cairo-move-to (cr x y)
  "Move CR's text cursor to (X Y)."
  (sumi-cairo--call "cairo_move_to" [:sint64 :pointer :double :double]
                    cr (float x) (float y)))

(defun sumi-cairo-show-text (cr text)
  "Draw TEXT at CR's cursor."
  (sumi-cairo--call "cairo_show_text" [:sint64 :pointer :string] cr text))

(defun sumi-cairo-destroy (cr)
  "Destroy the cairo context CR."
  (sumi-cairo--call "cairo_destroy" [:sint64 :pointer] cr))

(defun sumi-cairo-surface-write-to-png (surface path)
  "Write SURFACE to PATH as PNG.  Returns a cairo status (0 = success)."
  (sumi-cairo--call "cairo_surface_write_to_png" [:sint32 :pointer :string] surface path))

(defun sumi-cairo-surface-destroy (surface)
  "Destroy the cairo SURFACE."
  (sumi-cairo--call "cairo_surface_destroy" [:sint64 :pointer] surface))

;;;; --- demo: draw one frame to a PNG --------------------------------------

(defun sumi-cairo-demo (&optional path)
  "Draw a dark panel with the word \"sumi\" and write it to PATH.
Returns the cairo write status (0 = success).  This is the smallest
end-to-end proof that NeLisp elisp drives Cairo natively over the FFI."
  (let* ((path (or path "sumi-cairo-elisp.png"))
         (w 240) (h 120)
         (surface (sumi-cairo-image-surface-create w h))
         (cr (sumi-cairo-create surface)))
    ;; dark navy background
    (sumi-cairo-set-source-rgb cr 0.07 0.07 0.17)
    (sumi-cairo-rectangle cr 0 0 w h)
    (sumi-cairo-fill cr)
    ;; yellow title text
    (sumi-cairo-set-source-rgb cr 0.94 0.86 0.24)
    (sumi-cairo-select-font-face cr "sans")
    (sumi-cairo-set-font-size cr 48)
    (sumi-cairo-move-to cr 24 78)
    (sumi-cairo-show-text cr "sumi")
    (let ((status (sumi-cairo-surface-write-to-png surface path)))
      (sumi-cairo-destroy cr)
      (sumi-cairo-surface-destroy surface)
      status)))

(provide 'sumi-cairo)

;;; sumi-cairo.el ends here
