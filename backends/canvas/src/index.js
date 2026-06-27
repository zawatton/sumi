// sumi Canvas 2D backend — public entry point.
//
// Usage (browser / Electron / Tauri webview):
//
//   import { CanvasBackend, parseFrame } from 'sumi-canvas';
//   const make = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
//   const backend = new CanvasBackend(make);
//   backend.applyAll(parseFrame(frameJson));        // render the frame off-screen
//   document.body.querySelector('canvas')
//     .getContext('2d').drawImage(backend.surface(0), 0, 0);   // present buffer 0

export { parse, parseFrame } from './vocabulary.js';
export { CanvasBackend } from './canvasBackend.js';
