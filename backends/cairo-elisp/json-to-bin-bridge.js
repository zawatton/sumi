#!/usr/bin/env node
// json-to-bin-bridge.js — bridge the running game's sumi command stream to the
// NeLisp AOT native renderer.
//
// The game (newDTW, src/renderer/adapter/sumiBackend.ts with SUMI_STREAM_TCP)
// CONNECTS out and writes one frame per line: JSON.stringify({name,nums,text?}[])
// + '\n'.  So this is a TCP *server*: it accepts the game, parses each line into
// a frame, packs it to the .bin format sumi-live.el reads, and writes
// sumi-frame.bin atomically (tmp+rename) so the watching renderer always sees a
// complete frame.  Text fonts are remapped to a CJK-capable family (Meiryo) so
// the game's Japanese renders natively.
//
//   node json-to-bin-bridge.js [port=9099] [out.bin]
//   # then:  SUMI_STREAM_TCP=<port> <run the game>   and   sumi-live.exe
'use strict';
const net = require('net');
const fs = require('fs');
const path = require('path');
const PORT = Number(process.argv[2]) || 9099;
const outPath = process.argv[3] || path.join(__dirname, 'sumi-frame.bin');
const tmp = outPath + '.tmp';
const FONT = 'Meiryo';                 // CJK-capable; the game emits "sans"/etc.

const f64bits = (x) => { const b = Buffer.alloc(8); b.writeDoubleLE(Number(x) || 0, 0); return b.readBigUInt64LE(0); };

function pack(cmds) {
  const blobParts = []; let blobLen = 0; const strOff = new Map();
  const intern = (s) => {
    s = String(s); if (strOff.has(s)) return strOff.get(s);
    const off = blobLen + 1; const by = Buffer.from(s + '\0', 'utf8');
    blobParts.push(by); blobLen += by.length; strOff.set(s, off); return off;
  };
  let w = 480, h = 320, px = 0, py = 0; const recs = [];
  const rec = (op, a0 = 0, a1 = 0, a2 = 0, a3 = 0, toff = 0) =>
    recs.push({ op, a0: f64bits(a0), a1: f64bits(a1), a2: f64bits(a2), a3: f64bits(a3), toff });
  for (const c of cmds) {
    const n = c.nums || [];
    switch (c.name) {
      case 'gui-screen': case 'dtw-screen': w = n[1] | 0; h = n[2] | 0; break;
      case 'gui-set-color': case 'dtw-set-color': rec(2, n[0] / 255, n[1] / 255, n[2] / 255); break;
      case 'gui-set-font': case 'dtw-set-font': rec(3, n[0] || 12, 0, 0, 0, intern(FONT)); break;
      case 'gui-set-position': case 'dtw-set-position': px = n[0] | 0; py = n[1] | 0; break;
      case 'gui-fill-rect': case 'dtw-fill-rect': rec(5, n[0], n[1], n[2], n[3]); break;
      case 'gui-draw-line': case 'dtw-draw-line': rec(6, n[0], n[1], n[2], n[3]); break;
      case 'gui-draw-point': case 'dtw-draw-point': rec(7, n[0], n[1]); break;
      case 'gui-draw-text': case 'dtw-draw-text': rec(8, px, py, 0, 0, intern(c.text || '')); break;
      default: break;                  // gui-load-image / draw-image: skipped (no sprites yet)
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

let frames = 0, last = 0;
function writeFrame(cmds) {
  const now = Date.now();
  if (now - last < 30) return;          // throttle to ~30 fps
  last = now;
  try { fs.writeFileSync(tmp, pack(cmds)); fs.renameSync(tmp, outPath); frames++; }
  catch (_e) { /* drop on error */ }
}

const server = net.createServer((sock) => {
  console.error(`game connected from ${sock.remoteAddress}:${sock.remotePort}`);
  let buf = '';
  sock.on('data', (chunk) => {
    buf += chunk.toString('utf8');
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl); buf = buf.slice(nl + 1);
      if (!line.trim()) continue;
      try { writeFrame(JSON.parse(line)); }
      catch (_e) { /* skip malformed line */ }
    }
  });
  sock.on('close', () => console.error(`game disconnected (${frames} frames written)`));
  sock.on('error', (e) => console.error('sock error:', e.message));
});
server.on('error', (e) => { console.error('server error:', e.message); process.exit(1); });
server.listen(PORT, '127.0.0.1', () => console.error(`bridge listening on 127.0.0.1:${PORT} -> ${outPath}`));
