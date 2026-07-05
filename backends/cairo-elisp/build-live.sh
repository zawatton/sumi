#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND_DIR="$ROOT/backends/cairo-elisp"
MINGW_BIN="${MINGW_BIN:-/c/msys64/mingw64/bin}"
export PATH="$MINGW_BIN:$PATH"
export HOME="/tmp/sumi-emacs-home"
mkdir -p "$HOME"

to_win () { cygpath -m "$1" 2>/dev/null || echo "$1"; }

build_one () {
  local stem="$1"
  local src="$BACKEND_DIR/${stem}.el"
  local obj="$BACKEND_DIR/${stem}.o"
  local exe="$BACKEND_DIR/${stem}.exe"
  local src_win obj_win exe_win libs
  src_win="$(to_win "$src")"
  obj_win="$(to_win "$obj")"
  exe_win="$(to_win "$exe")"
  libs="$(pkg-config --libs gtk4)"

  echo "=== compile-to-object (COFF) ${src} -> ${obj_win} ==="
  emacs -Q --batch -L "$ROOT/../nelisp/lisp" -L "$ROOT/../nelisp/src" -l nelisp-aot-compiler \
    --eval "(condition-case e (progn (nelisp-aot-compile-to-object (with-temp-buffer (insert-file-contents \"${src_win}\") (goto-char (point-min)) (read (current-buffer))) \"${obj_win}\" :format 'coff) (princ \"OBJ-OK\\n\")) (error (princ (format \"OBJ-ERR %S\\n\" e)) (kill-emacs 1)))"

  echo "=== link (mingw gcc, libs=[${libs}]) -> ${exe_win} ==="
  gcc "$obj_win" $libs -o "$exe_win"
}

build_one "sumi-sprite-live"
build_one "sumi-sprite-dump"
