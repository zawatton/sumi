// The nelisp-gui drawing vocabulary, parsed into plain command objects.
//
// This is the JavaScript mirror of the Rust `nelisp_gui_core::parse` — the one
// contract every backend shares. A nelisp program emits `(name, [i32…], text?)`
// tuples (the same shape that arrives on the state-diff event stream); `parse`
// turns each into a tagged command object the Canvas backend renders.
//
// Both the general `gui-*` names and the game's `dtw-*` aliases are accepted, so
// a captured game frame (frame.json) and a hand-written `gui-*` program both run.

/**
 * @typedef {(
 *   | { kind: 'screen', id: number, w: number, h: number, mode: number }
 *   | { kind: 'buffer-select', id: number }
 *   | { kind: 'set-color', r: number, g: number, b: number }
 *   | { kind: 'set-blend-mode', op: string }
 *   | { kind: 'set-font', name: string, size: number, style: number }
 *   | { kind: 'set-position', x: number, y: number }
 *   | { kind: 'fill-rect', x1: number, y1: number, x2: number, y2: number }
 *   | { kind: 'draw-line', x1: number, y1: number, x2: number, y2: number }
 *   | { kind: 'draw-point', x: number, y: number }
 *   | { kind: 'draw-text', text: string }
 *   | { kind: 'draw-image', src: number, sx: number, sy: number, w: number, h: number, dx: number, dy: number }
 *   | { kind: 'draw-image-scaled', src: number, sx: number, sy: number, sw: number, sh: number, dx: number, dy: number, dw: number, dh: number }
 *   | { kind: 'object-size', w: number, h: number }
 *   | { kind: 'present' }
 * )} Command
 */

/**
 * Map an HSP-style blend mode integer onto a Canvas `globalCompositeOperation`.
 * A small portable subset: additive modes → `lighter`, everything else composits
 * normally (sprite alpha comes from the source alpha channel).
 * @param {number} mode
 * @returns {string}
 */
function blendOp(mode) {
  switch (mode) {
    case 3: // HSP gmode add
    case 5:
      return 'lighter';
    default:
      return 'source-over';
  }
}

/**
 * Parse one `(name, nums, text)` tuple into a {@link Command}, or `null` for an
 * unknown name (e.g. a vocabulary the program doesn't target).
 * @param {string} name
 * @param {number[]} [nums]
 * @param {string|null} [text]
 * @returns {Command|null}
 */
export function parse(name, nums = [], text = null) {
  const n = (i) => (nums[i] ?? 0) | 0;
  switch (name) {
    case 'gui-screen':
    case 'dtw-screen':
      return { kind: 'screen', id: n(0), w: n(1), h: n(2), mode: n(3) };
    case 'gui-buffer-select':
    case 'dtw-select-buffer':
      return { kind: 'buffer-select', id: n(0) };
    case 'gui-set-color':
    case 'dtw-set-color':
      return { kind: 'set-color', r: n(0) & 255, g: n(1) & 255, b: n(2) & 255 };
    case 'gui-set-blend-mode':
    case 'dtw-set-blend-mode':
      return { kind: 'set-blend-mode', op: blendOp(n(0)) };
    case 'gui-set-font':
    case 'dtw-set-font':
      return { kind: 'set-font', name: text ?? 'sans', size: n(0), style: n(1) };
    case 'gui-set-position':
    case 'dtw-set-position':
      return { kind: 'set-position', x: n(0), y: n(1) };
    case 'gui-fill-rect':
    case 'dtw-fill-rect':
      return { kind: 'fill-rect', x1: n(0), y1: n(1), x2: n(2), y2: n(3) };
    case 'gui-draw-line':
    case 'dtw-draw-line':
      return { kind: 'draw-line', x1: n(0), y1: n(1), x2: n(2), y2: n(3) };
    case 'gui-draw-point':
    case 'dtw-draw-point':
      return { kind: 'draw-point', x: n(0), y: n(1) };
    case 'gui-draw-text':
    case 'dtw-draw-text':
      return { kind: 'draw-text', text: text ?? '' };
    case 'gui-draw-image':
    case 'dtw-draw-image':
      return { kind: 'draw-image', src: n(0), sx: n(1), sy: n(2), w: n(3), h: n(4), dx: n(5), dy: n(6) };
    case 'gui-draw-image-scaled':
    case 'dtw-draw-image-scaled':
      return { kind: 'draw-image-scaled', src: n(0), sx: n(1), sy: n(2), sw: n(3), sh: n(4), dx: n(5), dy: n(6), dw: n(7), dh: n(8) };
    case 'gui-object-size':
    case 'dtw-object-size':
      return { kind: 'object-size', w: n(0), h: n(1) };
    case 'gui-present':
    case 'dtw-redraw':
      return { kind: 'present' };
    default:
      return null;
  }
}

/**
 * Convenience: parse a captured-frame array (`[{name, nums, text?}, …]`, the
 * shape `capture_gui_frame.js` writes) into a list of commands, dropping any
 * unknown entries.
 * @param {Array<{name: string, nums?: number[], text?: string|null}>} entries
 * @returns {Command[]}
 */
export function parseFrame(entries) {
  const out = [];
  for (const e of entries) {
    const c = parse(e.name, e.nums ?? [], e.text ?? null);
    if (c) out.push(c);
  }
  return out;
}
