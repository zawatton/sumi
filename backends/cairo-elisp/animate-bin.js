#!/usr/bin/env node
// animate-bin.js — drive the live native renderer by rewriting sumi-frame.bin.
//
// A stand-in for the real game's frame source: every ~33 ms it builds a sumi
// command frame (a box bouncing across the canvas + a title) and writes it to
// sumi-frame.bin ATOMICALLY (write tmp, rename) so the watching sumi-live
// interpreter always reads a complete frame.  Proves live native rendering
// driven by external frame data — swap this generator for a game-JSON bridge.
//
//   node animate-bin.js [out.bin] [seconds]
'use strict';
const fs = require('fs');
const path = require('path');
const outPath = process.argv[2] || path.join(__dirname, 'sumi-frame.bin');
const seconds = Number(process.argv[3]) || 25;
const W = 480, H = 320;

const f64bits = (x) => { const b = Buffer.alloc(8); b.writeDoubleLE(Number(x) || 0, 0); return b.readBigUInt64LE(0); };

// pack a command list (the frame-to-bin format) into a Buffer.
function pack(cmds) {
  const blobParts = []; let blobLen = 0; const strOff = new Map();
  const intern = (s) => {
    s = String(s); if (strOff.has(s)) return strOff.get(s);
    const off = blobLen + 1; const by = Buffer.from(s + '\0', 'utf8');
    blobParts.push(by); blobLen += by.length; strOff.set(s, off); return off;
  };
  let w = W, h = H, px = 0, py = 0; const recs = [];
  const rec = (op, a0 = 0, a1 = 0, a2 = 0, a3 = 0, toff = 0) =>
    recs.push({ op, a0: f64bits(a0), a1: f64bits(a1), a2: f64bits(a2), a3: f64bits(a3), toff });
  for (const c of cmds) {
    const n = c.nums || [];
    switch (c.name) {
      case 'dtw-screen': w = n[1] | 0; h = n[2] | 0; break;
      case 'dtw-set-color': rec(2, n[0] / 255, n[1] / 255, n[2] / 255); break;
      case 'dtw-set-font': rec(3, n[0] || 12, 0, 0, 0, intern(c.text || 'sans')); break;
      case 'dtw-set-position': px = n[0] | 0; py = n[1] | 0; break;
      case 'dtw-fill-rect': rec(5, n[0], n[1], n[2], n[3]); break;
      case 'dtw-draw-line': rec(6, n[0], n[1], n[2], n[3]); break;
      case 'dtw-draw-text': rec(8, px, py, 0, 0, intern(c.text || '')); break;
      default: break;
    }
  }
  const pad8 = (l) => (8 - (l % 8)) % 8;
  let blob = Buffer.concat(blobParts);
  blob = Buffer.concat([blob, Buffer.alloc(pad8(blob.length))]);
  const blobOff = 40, cmdOff = blobOff + blob.length;
  const hdr = Buffer.alloc(40);
  hdr.writeBigUInt64LE(BigInt(recs.length), 0);
  hdr.writeBigUInt64LE(BigInt(w), 8);
  hdr.writeBigUInt64LE(BigInt(h), 16);
  hdr.writeBigUInt64LE(BigInt(blobOff), 24);
  hdr.writeBigUInt64LE(BigInt(cmdOff), 32);
  const cb = Buffer.alloc(recs.length * 48);
  recs.forEach((r, i) => {
    const o = i * 48;
    cb.writeBigUInt64LE(BigInt(r.op), o);
    cb.writeBigUInt64LE(r.a0, o + 8); cb.writeBigUInt64LE(r.a1, o + 16);
    cb.writeBigUInt64LE(r.a2, o + 24); cb.writeBigUInt64LE(r.a3, o + 32);
    cb.writeBigUInt64LE(BigInt(r.toff), o + 40);
  });
  return Buffer.concat([hdr, blob, cb]);
}

function frameAt(t) {
  // box ping-pongs across the canvas
  const span = W - 90, period = 2.2;
  const u = Math.abs(((t / period) % 2) - 1);          // 0..1..0 triangle
  const bx = Math.round(15 + u * span);
  const by = Math.round(H / 2 - 30 + 40 * Math.sin(t * 2));
  const hue = (Math.floor(t * 60) % 4);
  const cols = [[240, 220, 60], [235, 80, 80], [80, 210, 210], [110, 220, 120]];
  const c = cols[hue];
  return [
    { name: 'dtw-screen', nums: [0, W, H, 0] },
    { name: 'dtw-set-color', nums: [15, 15, 30] },
    { name: 'dtw-fill-rect', nums: [0, 0, W, H] },
    { name: 'dtw-set-color', nums: c },
    { name: 'dtw-fill-rect', nums: [bx, by, 60, 60] },
    { name: 'dtw-set-color', nums: [200, 210, 240] },
    { name: 'dtw-set-font', nums: [22, 0], text: 'sans' },
    { name: 'dtw-set-position', nums: [16, 28] },
    { name: 'dtw-draw-text', nums: [], text: 'sumi-live: native GTK4 from a .bin stream' },
  ];
}

const tmp = outPath + '.tmp';
const t0 = Date.now();
let frames = 0;
const iv = setInterval(() => {
  const t = (Date.now() - t0) / 1000;
  if (t >= seconds) { clearInterval(iv); console.error(`done: ${frames} frames`); process.exit(0); }
  fs.writeFileSync(tmp, pack(frameAt(t)));
  fs.renameSync(tmp, outPath);               // atomic swap
  frames++;
}, 33);
console.error(`animating ${outPath} for ${seconds}s ...`);
