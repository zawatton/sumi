// Verify the Canvas backend renders the nelisp-gui vocabulary — in particular
// that the SAME captured game frame (../../../frame.json) that the native
// Cairo/GTK4 backend renders also drives the Canvas backend. The vocabulary is
// the only contract; this is the backend-agnostic proof on the web side.
//
// No browser / DOM: the backend is driven against a recording mock canvas that
// captures every 2D-context call, so we can assert exactly what would be drawn.
//
// Run:  node --test   (from backends/canvas/)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { CanvasBackend } from '../src/canvasBackend.js';
import { parse, parseFrame } from '../src/vocabulary.js';

/** A canvas factory that records every 2D-context call instead of drawing. */
function makeRecorder() {
  const calls = [];
  let nextId = 0;
  function createCanvas(w, h) {
    const id = nextId++;
    const ctx = {
      fillStyle: '',
      strokeStyle: '',
      font: '',
      textBaseline: '',
      globalCompositeOperation: 'source-over',
      lineWidth: 1,
      fillRect: (x, y, ww, hh) => calls.push({ op: 'fillRect', canvas: id, fill: ctx.fillStyle, args: [x, y, ww, hh] }),
      beginPath: () => calls.push({ op: 'beginPath', canvas: id }),
      moveTo: (x, y) => calls.push({ op: 'moveTo', canvas: id, args: [x, y] }),
      lineTo: (x, y) => calls.push({ op: 'lineTo', canvas: id, args: [x, y] }),
      stroke: () => calls.push({ op: 'stroke', canvas: id, stroke: ctx.strokeStyle }),
      fillText: (t, x, y) => calls.push({ op: 'fillText', canvas: id, fill: ctx.fillStyle, font: ctx.font, args: [t, x, y] }),
      drawImage: (...a) => calls.push({ op: 'drawImage', canvas: id, srcId: a[0] && a[0]._id, args: a.slice(1) }),
    };
    const canvas = { width: w, height: h, _id: id, getContext: () => ctx };
    return canvas;
  }
  return { calls, createCanvas };
}

test('the captured game frame renders through the Canvas backend', () => {
  const entries = JSON.parse(readFileSync(new URL('../../../frame.json', import.meta.url), 'utf8'));
  const frame = parseFrame(entries);
  assert.equal(frame.length, entries.length, 'every captured command is in the vocabulary');

  const { calls, createCanvas } = makeRecorder();
  const backend = new CanvasBackend(createCanvas);
  backend.applyAll(frame);

  // the dark background fills the whole 680x680 buffer
  const bg = calls.find((c) => c.op === 'fillRect' && c.args[2] === 680 && c.args[3] === 680);
  assert.ok(bg, 'a full-screen background fillRect was issued');
  assert.equal(bg.fill, 'rgb(18,18,44)', 'background uses the frame colour');

  // the real Pango-rendered labels come through as fillText with the same strings
  const texts = calls.filter((c) => c.op === 'fillText').map((c) => c.args[0]);
  for (const label of [
    'nelisp-gui',
    'GTK4 / Cairo native backend',
    'STATUS',
    'RENDER',
    'one frame, emitted as dtw-* commands, rendered natively',
  ]) {
    assert.ok(texts.includes(label), `fillText drew "${label}"`);
  }

  // text is drawn from the top-left (matches the native backend's baseline)
  assert.ok(
    calls.some((c) => c.op === 'fillText' && c.args[0] === 'nelisp-gui' && c.args[1] === 24 && c.args[2] === 16),
    'the title is placed at the cursor (24,16)',
  );

  // panels + bars are fills; the title rule, HP frame and 6 accent lines are strokes
  const strokes = calls.filter((c) => c.op === 'stroke').length;
  const rects = calls.filter((c) => c.op === 'fillRect').length;
  assert.ok(strokes >= 7, `at least 7 line strokes (got ${strokes})`);
  assert.ok(rects >= 5, `several filled panels/bars (got ${rects})`);
});

test('draw-image performs a clipped sub-region blit via 9-arg drawImage', () => {
  const { calls, createCanvas } = makeRecorder();
  const backend = new CanvasBackend(createCanvas);

  // source buffer 1, filled; destination buffer 0
  backend.apply(parse('dtw-screen', [1, 4, 4, 0]));
  backend.apply(parse('dtw-select-buffer', [1]));
  backend.apply(parse('dtw-set-color', [255, 0, 0]));
  backend.apply(parse('dtw-fill-rect', [0, 0, 4, 4]));
  backend.apply(parse('dtw-screen', [0, 4, 4, 0]));
  backend.apply(parse('dtw-select-buffer', [0]));
  // blit the 2x2 region at (1,1) of src 1 onto (0,0) of dest 0
  backend.apply(parse('dtw-draw-image', [1, 1, 1, 2, 2, 0, 0]));

  const blit = calls.find((c) => c.op === 'drawImage');
  assert.ok(blit, 'a drawImage was issued');
  // 9-arg form: (img, sx, sy, sw, sh, dx, dy, dw, dh) — sub-region copy
  assert.deepEqual(blit.args, [1, 1, 2, 2, 0, 0, 2, 2], 'only the (1,1,2,2) sub-region is copied to (0,0)');
});

test('draw-image-scaled scales a sub-region to the destination size', () => {
  const { calls, createCanvas } = makeRecorder();
  const backend = new CanvasBackend(createCanvas);

  backend.apply(parse('dtw-screen', [1, 4, 4, 0]));
  backend.apply(parse('dtw-select-buffer', [1]));
  backend.apply(parse('dtw-set-color', [0, 255, 0]));
  backend.apply(parse('dtw-fill-rect', [0, 0, 4, 4]));
  backend.apply(parse('dtw-screen', [0, 8, 8, 0]));
  backend.apply(parse('dtw-select-buffer', [0]));
  // take the 1x1 texel at (0,0) and scale it to 3x3 at (2,2)
  backend.apply(parse('dtw-draw-image-scaled', [1, 0, 0, 1, 1, 2, 2, 3, 3]));

  const blit = calls.find((c) => c.op === 'drawImage');
  assert.ok(blit, 'a drawImage was issued');
  assert.deepEqual(blit.args, [0, 0, 1, 1, 2, 2, 3, 3], '1x1 source region scaled to 3x3 at (2,2)');
});
