#!/usr/bin/env node
// sprite-to-bin.js — pack a CAPTURED sumi command stream (a full frame incl.
// sprite ops: gui-screen / gui-load-image / gui-select-buffer / gui-set-color /
// gui-fill-rect / gui-set-font / gui-set-position / gui-draw-text /
// gui-draw-image / gui-draw-image-scaled) into the .bin the AOT sprite
// interpreter (sumi-sprite.el) replays.  All numeric args become f64 BITS here
// (colours /255, scale factors dw/sw pre-divided — the AOT side has no f64
// arithmetic).  load-image's text is resolved to the PNG's absolute path.
//
//   node sprite-to-bin.js <stream.json> [out.bin] [assets/img dir]
//
// Record (96B, 12 u64 LE): op a0..a9 toff.  Layout per opcode:
//   1 select-buffer : a0=id
//   2 set-color     : a0,a1,a2 = r,g,b (f64 in 0..1)
//   3 set-font      : a0=size(f64) ; toff=family
//   5 fill-rect     : a0..a3 = x,y,w,h (f64)
//   8 draw-text     : a0,a1 = x,y (f64) ; toff=text
//   9 screen        : a0=id a1=w a2=h (ints)
//  10 load-image    : a0=id ; toff=png-path
//  12 draw-image-sc : a0=src(int) a1=dx a2=dy a3=sx a4=sy a5=sw a6=sh
//                     a7=scale_x a8=scale_y (f64)
'use strict';
const fs = require('fs');
const path = require('path');
const inPath  = process.argv[2] || 'sumi-title-stream.json';
const outPath = process.argv[3] || 'sumi-sprite.bin';
const imgDir  = process.argv[4] ||
  path.resolve(__dirname, '../../../newDTW-nelisp/assets/img');
const frame = JSON.parse(fs.readFileSync(inPath, 'utf8'));

const f64 = (x) => { const b = Buffer.alloc(8); b.writeDoubleLE(Number(x) || 0, 0); return b.readBigUInt64LE(0); };
const I = (x) => BigInt((x | 0) >>> 0 | 0) & 0xFFFFFFFFFFFFFFFFn; // unsigned-ish int slot
const u64 = (x) => BigInt.asUintN(64, BigInt(Math.trunc(Number(x) || 0)));

const blobParts = []; let blobLen = 0; const strOff = new Map();
function intern(s) {
  s = String(s); if (strOff.has(s)) return strOff.get(s);
  const off = blobLen + 1; const by = Buffer.from(s + '\0', 'utf8');
  blobParts.push(by); blobLen += by.length; strOff.set(s, off); return off;
}

let W = 0, H = 0, px = 0, py = 0;
const recs = [];
function rec(op, a = []) {
  const r = new Array(12).fill(0n);
  r[0] = u64(op);
  for (let i = 0; i < a.length; i++) r[i + 1] = a[i];          // a0..a9 -> slots 1..10
  recs.push(r);
}
for (const c of frame) {
  const n = c.nums || [];
  switch (c.name) {
    case 'gui-screen': case 'dtw-screen': {
      const id = n[0] | 0, w = n[1] | 0, h = n[2] | 0;
      if (id === 0) { W = w; H = h; }
      rec(9, [u64(id), u64(w), u64(h)]); break;
    }
    case 'gui-select-buffer': case 'gui-buffer-select': case 'dtw-select-buffer':
      rec(1, [u64(n[0])]); break;
    case 'gui-load-image': case 'dtw-load-image': {
      const p = path.join(imgDir, (c.text || '') + '.png').replace(/\\/g, '/');
      rec(10, [u64(n[0])]); recs[recs.length - 1][11] = BigInt(intern(p)); break;
    }
    case 'gui-set-color': case 'dtw-set-color':
      rec(2, [f64(n[0] / 255), f64(n[1] / 255), f64(n[2] / 255)]); break;
    case 'gui-set-font': case 'dtw-set-font':
      rec(3, [f64(n[0] || 12)]); recs[recs.length - 1][11] = BigInt(intern('Meiryo')); break;
    case 'gui-set-position': case 'dtw-set-position':
      px = n[0] | 0; py = n[1] | 0; break;
    case 'gui-fill-rect': case 'dtw-fill-rect':
      rec(5, [f64(n[0]), f64(n[1]), f64(n[2]), f64(n[3])]); break;
    case 'gui-draw-text': case 'dtw-draw-text':
      rec(8, [f64(px), f64(py)]); recs[recs.length - 1][11] = BigInt(intern(c.text || '')); break;
    case 'gui-draw-image': case 'dtw-draw-image': {
      // unscaled: src sx sy w h dx dy  -> treat as scaled 1:1
      const src = n[0] | 0, sx = n[1] | 0, sy = n[2] | 0, w = n[3] | 0, h = n[4] | 0, dx = n[5] | 0, dy = n[6] | 0;
      rec(12, [u64(src), f64(dx), f64(dy), f64(-sx), f64(-sy), f64(w), f64(h), f64(1), f64(1)]); break;
    }
    case 'gui-draw-image-scaled': case 'dtw-draw-image-scaled': {
      const src = n[0] | 0, sx = n[1] | 0, sy = n[2] | 0, sw = n[3] | 0, sh = n[4] | 0,
            dx = n[5] | 0, dy = n[6] | 0, dw = n[7] | 0, dh = n[8] | 0;
      const scx = sw ? dw / sw : 1, scy = sh ? dh / sh : 1;
      rec(12, [u64(src), f64(dx), f64(dy), f64(-sx), f64(-sy), f64(sw), f64(sh), f64(scx), f64(scy)]); break;
    }
    default: break;        // present/object-size/blend: ignored
  }
}
if (!W) { W = 680; H = 680; }

const pad8 = (l) => (8 - (l % 8)) % 8;
let blob = Buffer.concat(blobParts);
blob = Buffer.concat([blob, Buffer.alloc(pad8(blob.length))]);
const blobOff = 40, cmdOff = blobOff + blob.length;
const hdr = Buffer.alloc(40);
hdr.writeBigUInt64LE(BigInt(recs.length), 0);
hdr.writeBigUInt64LE(BigInt(W), 8);
hdr.writeBigUInt64LE(BigInt(H), 16);
hdr.writeBigUInt64LE(BigInt(blobOff), 24);
hdr.writeBigUInt64LE(BigInt(cmdOff), 32);
const cb = Buffer.alloc(recs.length * 96);
recs.forEach((r, i) => { const o = i * 96; for (let s = 0; s < 12; s++) cb.writeBigUInt64LE(r[s], o + s * 8); });
fs.writeFileSync(outPath, Buffer.concat([hdr, blob, cb]));
console.error(`OK: ${recs.length} recs, blob ${blob.length}B, ${W}x${H} -> ${outPath} (${hdr.length + blob.length + cb.length}B)`);
