#!/usr/bin/env node
// sprite-animate-bin.js — per-frame sprite stand-in for the LIVE native renderer.
//
// Unlike sprite-to-bin.js (which packs ONE cumulative captured stream), this
// rewrites sumi-sprite.bin every ~50 ms with a single self-contained FRAME:
// declare the screen, (re)load one sprite PNG, then clear + blit a moving box
// and a moving sprite.  The live renderer (sumi-sprite-live.el) keeps buffers
// PERSISTENT and skips screen/load-image once created, so the PNG decodes once
// while the per-frame clear+blits re-run — exactly the real game's frame shape.
// If a sprite PNG move proves out here, the renderer is ready for the real game.
//
//   node sprite-animate-bin.js [out.bin] [seconds] [png]
'use strict';
const fs = require('fs');
const path = require('path');
const outPath = process.argv[2] || path.join(__dirname, 'sumi-sprite.bin');
const seconds = Number(process.argv[3]) || 25;
const png = (process.argv[4] ||
  'C:/Users/kuroz/Cowork/Notes/dev/newDTW-nelisp/assets/img/img_mychara.gif.png').replace(/\\/g, '/');
const W = 420, H = 420;

const f64 = (x) => { const b = Buffer.alloc(8); b.writeDoubleLE(Number(x) || 0, 0); return b.readBigUInt64LE(0); };
const u64 = (x) => BigInt.asUintN(64, BigInt(Math.trunc(Number(x) || 0)));

function pack(cmds) {
  const blobParts = []; let blobLen = 0; const strOff = new Map();
  const intern = (s) => {
    s = String(s); if (strOff.has(s)) return strOff.get(s);
    const off = blobLen + 1; const by = Buffer.from(s + '\0', 'utf8');
    blobParts.push(by); blobLen += by.length; strOff.set(s, off); return off;
  };
  const recs = [];
  const rec = (op, a = [], text = null) => {
    const r = new Array(12).fill(0n);
    r[0] = u64(op);
    for (let i = 0; i < a.length; i++) r[i + 1] = a[i];
    if (text != null) r[11] = BigInt(intern(text));
    recs.push(r);
  };
  for (const c of cmds) {
    const n = c.nums || [];
    switch (c.name) {
      case 'screen':       rec(9,  [u64(n[0]), u64(n[1]), u64(n[2])]); break;
      case 'load-image':   rec(10, [u64(n[0])], c.text); break;
      case 'select-buffer':rec(1,  [u64(n[0])]); break;
      case 'set-color':    rec(2,  [f64(n[0]), f64(n[1]), f64(n[2])]); break;
      case 'fill-rect':    rec(5,  [f64(n[0]), f64(n[1]), f64(n[2]), f64(n[3])]); break;
      case 'draw-image-scaled': {
        const src = n[0] | 0, dx = n[1], dy = n[2], sx = n[3], sy = n[4],
              sw = n[5], sh = n[6], dw = n[7], dh = n[8];
        const scx = sw ? dw / sw : 1, scy = sh ? dh / sh : 1;
        rec(12, [u64(src), f64(dx), f64(dy), f64(-sx), f64(-sy), f64(sw), f64(sh), f64(scx), f64(scy)]);
        break;
      }
      default: break;
    }
  }
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
  return Buffer.concat([hdr, blob, cb]);
}

function frameAt(t) {
  const span = W - 120, period = 2.4;
  const u = Math.abs(((t / period) % 2) - 1);
  const bx = Math.round(20 + u * span);
  const by = Math.round(H / 2 - 40 + 80 * Math.sin(t * 1.8));
  const spx = Math.round(20 + (1 - u) * span);
  const spy = Math.round(H / 2 - 40 + 80 * Math.cos(t * 1.8));
  return [
    { name: 'screen', nums: [0, W, H] },
    { name: 'load-image', nums: [1], text: png },
    { name: 'select-buffer', nums: [0] },
    { name: 'set-color', nums: [0.08, 0.09, 0.16] },
    { name: 'fill-rect', nums: [0, 0, W, H] },
    { name: 'set-color', nums: [0.95, 0.82, 0.20] },
    { name: 'fill-rect', nums: [bx, by, 64, 64] },
    // blit a 96x96 region of the sprite sheet, 1:1, moving the opposite way
    { name: 'draw-image-scaled', nums: [1, spx, spy, 0, 0, 96, 96, 96, 96] },
  ];
}

const tmp = outPath + '.tmp';
const t0 = Date.now();
let frames = 0;
const iv = setInterval(() => {
  const t = (Date.now() - t0) / 1000;
  if (t >= seconds) { clearInterval(iv); console.error(`done: ${frames} frames`); process.exit(0); }
  // Windows: the renderer holds the .bin open (read) each tick, so a rename over
  // it can fail with EPERM; skip that frame and retry next tick (like the bridge).
  try { fs.writeFileSync(tmp, pack(frameAt(t))); fs.renameSync(tmp, outPath); frames++; }
  catch (_e) { /* transient sharing violation — retry next tick */ }
}, 50);
console.error(`sprite-animating ${outPath} for ${seconds}s (png=${png}) ...`);
