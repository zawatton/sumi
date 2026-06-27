// HTML Canvas 2D backend for the nelisp-gui vocabulary.
//
// Implements the same contract as the Rust tiny-skia / Cairo backends, but
// against the Canvas 2D API — this is the backend the Electron and Tauri shells
// consume (both render into a webview). A nelisp program never names a backend;
// it emits the vocabulary and one of these renders it.
//
// The backend is canvas-source agnostic: it is constructed with a
// `createCanvas(w, h)` factory so it runs in a browser (`document.createElement`),
// under Electron/Tauri, or against a recording mock in tests — no DOM assumed.

/** @typedef {import('./vocabulary.js').Command} Command */

/**
 * A minimal canvas surface: anything exposing `getContext('2d')` and usable as a
 * `drawImage` source. A real `HTMLCanvasElement` / `OffscreenCanvas` satisfies it.
 * @typedef {{ width: number, height: number, getContext: (id: '2d') => any }} CanvasLike
 */

export class CanvasBackend {
  /**
   * @param {(w: number, h: number) => CanvasLike} createCanvas factory for an
   *   offscreen surface. In a browser: `(w,h)=>{const c=document.createElement('canvas');c.width=w;c.height=h;return c;}`.
   */
  constructor(createCanvas) {
    if (typeof createCanvas !== 'function') {
      throw new TypeError('CanvasBackend requires a createCanvas(w, h) factory');
    }
    this.createCanvas = createCanvas;
    /** @type {Map<number, { canvas: CanvasLike, ctx: any }>} */
    this.buffers = new Map();
    this.current = 0;
    this.cursor = { x: 0, y: 0 };
  }

  /** The 2D context of the current buffer, or null if none is selected. */
  _ctx() {
    const b = this.buffers.get(this.current);
    return b ? b.ctx : null;
  }

  /**
   * The canvas for a buffer id — e.g. to present buffer 0 onto the on-screen
   * canvas, or to inspect a render in a test.
   * @param {number} id
   * @returns {CanvasLike|undefined}
   */
  surface(id) {
    return this.buffers.get(id)?.canvas;
  }

  /**
   * Render one command.
   * @param {Command} cmd
   */
  apply(cmd) {
    switch (cmd.kind) {
      case 'screen': {
        const canvas = this.createCanvas(Math.max(1, cmd.w), Math.max(1, cmd.h));
        const ctx = canvas.getContext('2d');
        if (ctx) ctx.textBaseline = 'top'; // match HSP "mes" / Pango show_layout top-left
        this.buffers.set(cmd.id, { canvas, ctx });
        break;
      }
      case 'buffer-select':
        this.current = cmd.id;
        break;
      case 'set-color': {
        const c = this._ctx();
        if (c) {
          const s = `rgb(${cmd.r},${cmd.g},${cmd.b})`;
          c.fillStyle = s;
          c.strokeStyle = s;
        }
        break;
      }
      case 'set-blend-mode': {
        const c = this._ctx();
        if (c) c.globalCompositeOperation = cmd.op;
        break;
      }
      case 'set-font': {
        const c = this._ctx();
        if (c) c.font = `${cmd.size}px ${cmd.name}`;
        break;
      }
      case 'set-position':
        this.cursor = { x: cmd.x, y: cmd.y };
        break;
      case 'fill-rect': {
        const c = this._ctx();
        if (c) c.fillRect(cmd.x1, cmd.y1, cmd.x2 - cmd.x1, cmd.y2 - cmd.y1);
        break;
      }
      case 'draw-line': {
        const c = this._ctx();
        if (c) {
          c.lineWidth = 1;
          c.beginPath();
          c.moveTo(cmd.x1, cmd.y1);
          c.lineTo(cmd.x2, cmd.y2);
          c.stroke();
        }
        break;
      }
      case 'draw-point': {
        const c = this._ctx();
        if (c) c.fillRect(cmd.x, cmd.y, 1, 1);
        break;
      }
      case 'draw-text': {
        const c = this._ctx();
        if (c) c.fillText(cmd.text, this.cursor.x, this.cursor.y);
        break;
      }
      case 'draw-image': {
        const c = this._ctx();
        const src = this.buffers.get(cmd.src);
        // Canvas' 9-arg drawImage is itself a sub-region blit: copy only
        // (sx,sy,w,h) of the source onto (dx,dy,w,h) of the current buffer.
        if (c && src && cmd.w > 0 && cmd.h > 0) {
          c.drawImage(src.canvas, cmd.sx, cmd.sy, cmd.w, cmd.h, cmd.dx, cmd.dy, cmd.w, cmd.h);
        }
        break;
      }
      case 'draw-image-scaled': {
        const c = this._ctx();
        const src = this.buffers.get(cmd.src);
        if (c && src && cmd.sw > 0 && cmd.sh > 0) {
          c.drawImage(src.canvas, cmd.sx, cmd.sy, cmd.sw, cmd.sh, cmd.dx, cmd.dy, cmd.dw, cmd.dh);
        }
        break;
      }
      case 'object-size':
      case 'present':
        // object-size is sprite metadata; present is host-driven (rAF paint).
        break;
    }
  }

  /**
   * Render a whole frame.
   * @param {Command[]} frame
   */
  applyAll(frame) {
    for (const cmd of frame) this.apply(cmd);
  }
}
