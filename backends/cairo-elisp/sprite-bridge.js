#!/usr/bin/env node
// sprite-bridge.js — bridge a running game's sumi command stream (WITH sprites)
// to the NeLisp AOT live sprite renderer (sumi-sprite-live.el).
//
// The game (newDTW, src/renderer/adapter/sumiBackend.ts with SUMI_STREAM_TCP)
// CONNECTS out and writes one frame per line: JSON.stringify({name,nums,text?}[])
// + '\n'.  This is a TCP *server*: it parses each line into a frame and packs it
// to the 96-byte sprite .bin sumi-sprite-live.el reads.
//
// Sprites load once but blit every frame, while the per-frame stream only
// carries load-image in the startup frame(s).  So this bridge keeps a CUMULATIVE
// setup (every gui-screen / gui-load-image seen, keyed by buffer id) and PREPENDS
// it to every packed frame.  The renderer keeps buffers persistent and skips
// screen/load-image once created, so each frame is self-contained yet PNGs decode
// only once -- even if a tick misses the exact frame a sprite first appeared in.
//
//   node sprite-bridge.js [port=9099] [out.bin=sumi-sprite.bin] [assets/img dir]
//   # then:  SUMI_STREAM_TCP=<port> <run the game>   and   sumi-sprite-live.exe
'use strict';
const net = require('net');
const fs = require('fs');
const path = require('path');
const PORT = Number(process.argv[2]) || 9099;
const outPath = process.argv[3] || path.join(__dirname, 'sumi-sprite.bin');
const imgDir = process.argv[4] ||
  path.resolve(__dirname, '../../../newDTW-nelisp/assets/img');
const tmp = outPath + '.tmp';
const headPath = path.join(path.dirname(outPath), 'sumi-sprite-head.txt');
const headTmp = headPath + '.tmp';
const seqPrefix = path.join(path.dirname(outPath), 'sumi-sprite-');

const f64 = (x) => { const b = Buffer.alloc(8); b.writeDoubleLE(Number(x) || 0, 0); return b.readBigUInt64LE(0); };
const u64 = (x) => BigInt.asUintN(64, BigInt(Math.trunc(Number(x) || 0)));

// pack a flat command array (sprite vocabulary) into the 96-byte .bin.
function pack(cmds) {
  const blobParts = []; let blobLen = 0; const strOff = new Map();
  const intern = (s) => {
    s = String(s); if (strOff.has(s)) return strOff.get(s);
    const off = blobLen + 1; const by = Buffer.from(s + '\0', 'utf8');
    blobParts.push(by); blobLen += by.length; strOff.set(s, off); return off;
  };
  let W = 0, H = 0, px = 0, py = 0; const recs = [];
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
      case 'gui-screen': case 'dtw-screen': {
        const id = n[0] | 0, w = n[1] | 0, h = n[2] | 0;
        if (id === 0) { W = w; H = h; }
        rec(9, [u64(id), u64(w), u64(h)]); break;
      }
      case 'gui-select-buffer': case 'gui-buffer-select': case 'dtw-select-buffer':
        rec(1, [u64(n[0])]); break;
      case 'gui-load-image': case 'dtw-load-image': {
        const p = path.join(imgDir, (c.text || '') + '.png').replace(/\\/g, '/');
        rec(10, [u64(n[0])], p); break;
      }
      case 'gui-set-color': case 'dtw-set-color':
        rec(2, [f64(n[0] / 255), f64(n[1] / 255), f64(n[2] / 255)]); break;
      case 'gui-set-font': case 'dtw-set-font':
        rec(3, [f64(n[0] || 12)], 'Meiryo'); break;
      case 'gui-set-position': case 'dtw-set-position':
        px = n[0] | 0; py = n[1] | 0; break;
      case 'gui-fill-rect': case 'dtw-fill-rect':
        // the game sends [left, top, right, bottom] (two corners), not x/y/w/h.
        rec(5, [f64(n[0]), f64(n[1]), f64(n[2] - n[0]), f64(n[3] - n[1])]); break;
      case 'gui-draw-line': case 'dtw-draw-line':
        rec(6, [f64(n[0]), f64(n[1]), f64(n[2]), f64(n[3])]); break;
      case 'gui-draw-point': case 'dtw-draw-point':
        rec(7, [f64(n[0]), f64(n[1])]); break;
      case 'gui-set-alpha': case 'dtw-set-alpha':
        rec(13, [f64((n[0] == null ? 255 : n[0]) / 255)]); break;
      case 'gui-draw-text': case 'dtw-draw-text':
        rec(8, [f64(px), f64(py)], c.text || ''); break;
      case 'gui-draw-image': case 'dtw-draw-image': {
        const src = n[0] | 0, sx = n[1] | 0, sy = n[2] | 0, w = n[3] | 0, h = n[4] | 0, dx = n[5] | 0, dy = n[6] | 0;
        rec(12, [u64(src), f64(dx), f64(dy), f64(-sx), f64(-sy), f64(w), f64(h), f64(1), f64(1)]); break;
      }
      case 'gui-draw-image-scaled': case 'dtw-draw-image-scaled': {
        const src = n[0] | 0, sx = n[1] | 0, sy = n[2] | 0, sw = n[3] | 0, sh = n[4] | 0,
              dx = n[5] | 0, dy = n[6] | 0, dw = n[7] | 0, dh = n[8] | 0;
        const scx = sw ? dw / sw : 1, scy = sh ? dh / sh : 1;
        rec(12, [u64(src), f64(dx), f64(dy), f64(-sx), f64(-sy), f64(sw), f64(sh), f64(scx), f64(scy)]); break;
      }
      default: break;
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
  return Buffer.concat([hdr, blob, cb]);
}

function isBusyRenameError(err) {
  return err && (err.code === 'EPERM' || err.code === 'EBUSY');
}

function renameWithRetry(from, to, attempts = 8) {
  for (let i = 0; i < attempts; i++) {
    try {
      fs.renameSync(from, to);
      return true;
    } catch (err) {
      if (!isBusyRenameError(err) || i === attempts - 1) throw err;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10);
    }
  }
  return false;
}

function writeHead(seq) {
  fs.writeFileSync(headTmp, `${seq}\n`);
  renameWithRetry(headTmp, headPath);
}

function pruneBins(head) {
  // Keep a deep horizon: scenes compose into work canvases across frames,
  // so a window that (re)joins mid-session must replay from bin 1 or it
  // shows empty canvases (gray screen).  ~20k bins x ~10KB ≈ 200MB max,
  // and the window catches up at ~1280 bins/s.
  const cutoff = head - 20000;
  if (cutoff <= 0) return;
  const prunePath = `${seqPrefix}${String(cutoff).padStart(6, '0')}.bin`;
  try { fs.unlinkSync(prunePath); } catch (_err) { /* ignore best-effort prune */ }
}

// cumulative setup, keyed by buffer id, prepended to every frame.
const screens = new Map();   // id -> {name,nums}
const images = new Map();    // id -> {name,nums,text}
function setupCmds() {
  const out = [];
  // A buffer that has a loaded image IS that image.  Don't also emit its
  // (earlier, blank) screen op: the renderer would create a blank surface first
  // and then skip the image load (skip-if-exists), leaving the sprite source
  // empty.  So emit screens only for ids that never get an image.
  for (const [id, c] of screens) if (!images.has(id)) out.push(c);
  for (const c of images.values()) out.push(c);
  return out;
}

let frames = 0, current = 0, currentAlpha = 255;
function onFrame(cmds, seq) {
  const startSel = current;             // buffer selected at end of previous frame
  const startAlpha = currentAlpha;      // alpha (gmode) carried from previous frame
  const draw = [];
  for (const c of cmds) {
    const n = c.nums || [];
    if (c.name === 'gui-screen' || c.name === 'dtw-screen') { screens.set(n[0] | 0, c); }
    else if (c.name === 'gui-load-image' || c.name === 'dtw-load-image') { images.set(n[0] | 0, c); }
    else {
      if (c.name === 'gui-select-buffer' || c.name === 'gui-buffer-select' || c.name === 'dtw-select-buffer') current = n[0] | 0;
      else if (c.name === 'gui-set-alpha' || c.name === 'dtw-set-alpha') currentAlpha = (n[0] == null ? 255 : n[0]);
      draw.push(c);
    }
  }
  // prepend the carried selection + alpha so draws before this frame's first
  // select/gmode use the state the game held at the end of the previous frame.
  const out = setupCmds();
  out.push({ name: 'gui-select-buffer', nums: [startSel] });
  out.push({ name: 'gui-set-alpha', nums: [startAlpha] });
  for (const c of draw) out.push(c);
  try {
    const packed = pack(out);
    const seqPath = `${seqPrefix}${String(seq).padStart(6, '0')}.bin`;
    fs.writeFileSync(seqPath, packed);
    fs.writeFileSync(tmp, packed);
    fs.renameSync(tmp, outPath);
    writeHead(seq);
    pruneBins(seq);
    frames++;
  }
  catch (_e) { /* transient sharing violation / drop on error */ }
}

const server = net.createServer((sock) => {
  console.error(`game connected from ${sock.remoteAddress}:${sock.remotePort}`);
  let seq = 0;
  let buf = '';
  sock.on('data', (chunk) => {
    buf += chunk.toString('utf8');
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl); buf = buf.slice(nl + 1);
      if (!line.trim()) continue;
      try {
        const frame = JSON.parse(line);
        seq += 1;
        onFrame(frame, seq);
      } catch (_e) { /* skip malformed line */ }
    }
  });
  sock.on('close', () => console.error(`game disconnected (${frames} frames, ${screens.size} screens, ${images.size} images)`));
  sock.on('error', (e) => console.error('sock error:', e.message));
});
server.on('error', (e) => { console.error('server error:', e.message); process.exit(1); });
server.listen(PORT, '127.0.0.1', () => console.error(`sprite-bridge on 127.0.0.1:${PORT} -> ${outPath} (img ${imgDir})`));
