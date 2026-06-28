#!/usr/bin/env node
// frame-to-bin.js — pack a sumi command frame (frame.json: a JSON array of
// { name, nums, text? }) into a flat little-endian binary the NeLisp AOT
// runtime interpreter (sumi-render.el) reads at run time.  All numeric args are
// converted to IEEE-754 f64 BITS *here* (colours pre-divided by 255, coords as
// doubles), so the interpreter needs no f64 arithmetic — just bits-to-f64.
//
//   node frame-to-bin.js [frame.json] [out.bin]
//
// Layout (all u64 LE, offsets in bytes):
//   [0]  num_cmds   [8]  W   [16] H   [24] blob_off(=40)   [32] cmd_off
//   [40] string blob (NUL-terminated UTF-8 strings, padded to 8)
//   [cmd_off] num_cmds records, 48 bytes each:
//       u64 opcode | u64 a0 a1 a2 a3 (f64 bits) | u64 text_off (into blob, 0=none)
//
// opcodes: 2 set-color  3 set-font  4 set-position  5 fill-rect  6 draw-line
//          7 draw-point 8 draw-text   (0 screen / 1 select-buffer handled here)
'use strict';
const fs = require('fs');
const inPath  = process.argv[2] || 'frame.json';
const outPath = process.argv[3] || 'sumi-frame.bin';
const frame = JSON.parse(fs.readFileSync(inPath, 'utf8'));

const f64bits = (x) => { const b = Buffer.alloc(8); b.writeDoubleLE(Number(x) || 0, 0); return b.readBigUInt64LE(0); };

// ---- intern strings into the blob ---------------------------------------
const blobParts = [];
let blobLen = 0;
const strOff = new Map();          // string -> offset (1-based so 0 = "none")
function intern(s) {
  s = String(s);
  if (strOff.has(s)) return strOff.get(s);
  const off = blobLen + 1;         // reserve 0 for "no text"; real offsets are blobLen+1
  const bytes = Buffer.from(s + '\0', 'utf8');
  blobParts.push(bytes);
  blobLen += bytes.length;
  strOff.set(s, off);
  return off;
}

// ---- walk the stream into records ---------------------------------------
let W = 240, H = 120, px = 0, py = 0;
const recs = [];
const rec = (op, a0 = 0, a1 = 0, a2 = 0, a3 = 0, toff = 0) =>
  recs.push({ op, a0: f64bits(a0), a1: f64bits(a1), a2: f64bits(a2), a3: f64bits(a3), toff });
for (const c of frame) {
  const n = c.nums || [];
  switch (c.name) {
    case 'gui-screen': case 'dtw-screen': W = n[1] | 0; H = n[2] | 0; break;
    case 'gui-buffer-select': case 'dtw-select-buffer': break;
    case 'gui-set-color': case 'dtw-set-color':
      rec(2, n[0] / 255, n[1] / 255, n[2] / 255); break;
    case 'gui-set-font': case 'dtw-set-font':
      rec(3, n[0] || 12, 0, 0, 0, intern(c.text || 'sans')); break;
    case 'gui-set-position': case 'dtw-set-position':
      px = n[0] | 0; py = n[1] | 0; break;            // applied at draw-text
    case 'gui-fill-rect': case 'dtw-fill-rect':
      rec(5, n[0], n[1], n[2], n[3]); break;
    case 'gui-draw-line': case 'dtw-draw-line':
      rec(6, n[0], n[1], n[2], n[3]); break;
    case 'gui-draw-point': case 'dtw-draw-point':
      rec(7, n[0], n[1]); break;
    case 'gui-draw-text': case 'dtw-draw-text':
      rec(8, px, py, 0, 0, intern(c.text || '')); break;
    default: break;                                   // image/etc skipped
  }
}

// ---- serialise -----------------------------------------------------------
const pad8 = (len) => (8 - (len % 8)) % 8;
let blob = Buffer.concat(blobParts);
blob = Buffer.concat([blob, Buffer.alloc(pad8(blob.length))]);
const blobOff = 40;
const cmdOff  = blobOff + blob.length;
const header = Buffer.alloc(40);
header.writeBigUInt64LE(BigInt(recs.length), 0);
header.writeBigUInt64LE(BigInt(W), 8);
header.writeBigUInt64LE(BigInt(H), 16);
header.writeBigUInt64LE(BigInt(blobOff), 24);
header.writeBigUInt64LE(BigInt(cmdOff), 32);
const cmds = Buffer.alloc(recs.length * 48);
recs.forEach((r, i) => {
  const o = i * 48;
  cmds.writeBigUInt64LE(BigInt(r.op), o);
  cmds.writeBigUInt64LE(r.a0, o + 8);
  cmds.writeBigUInt64LE(r.a1, o + 16);
  cmds.writeBigUInt64LE(r.a2, o + 24);
  cmds.writeBigUInt64LE(r.a3, o + 32);
  cmds.writeBigUInt64LE(BigInt(r.toff), o + 40);
});
fs.writeFileSync(outPath, Buffer.concat([header, blob, cmds]));
console.error(`OK: ${recs.length} cmds, blob ${blob.length}B, ${W}x${H} -> ${outPath} (${header.length + blob.length + cmds.length}B)`);
