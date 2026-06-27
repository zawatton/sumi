#!/usr/bin/env bash
# One-command verification for sumi: every backend's tests, green or bust.
# Used by the autonomous dev loop and mirrored by CI (.github/workflows/ci.yml).
#
#   scripts/check.sh
#
# Env:
#   SKIP_CAIRO=1   skip the Cairo/GTK4 backend (e.g. no GTK4 toolchain present)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== core + skia + input (default toolchain) =="
cargo test -p sumi-core -p sumi-skia -p sumi-input

if [ "${SKIP_CAIRO:-0}" = "1" ]; then
  echo "== cairo/gtk4: skipped (SKIP_CAIRO=1) =="
elif [ -d /c/msys64/mingw64 ]; then
  # Windows + MSYS2 GTK4: GNU toolchain, mingw64 on PATH/PKG_CONFIG_PATH
  echo "== cairo/gtk4 (windows: gnu toolchain + msys2) =="
  PKG_CONFIG_PATH=/c/msys64/mingw64/lib/pkgconfig PATH="/c/msys64/mingw64/bin:$PATH" \
    cargo +stable-x86_64-pc-windows-gnu test -p sumi-cairo
else
  # Linux / macOS with system GTK4 (libgtk-4-dev / brew gtk4)
  echo "== cairo/gtk4 (system gtk4) =="
  cargo test -p sumi-cairo
fi

echo "== canvas (node) =="
( cd backends/canvas && node --test )

echo "== input (node) =="
( cd backends/input && node --test )

echo "ALL GREEN"
