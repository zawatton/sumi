// sumi-input — web (DOM) binding of the backend-agnostic input vocabulary.
//
// The sibling of the Canvas drawing backend: it translates DOM keyboard / pointer
// events into the same logical buttons + HSP-style stick bitmask the Rust core
// (`crates/sumi-input`) defines, so the web and native shells agree. A program
// polls `InputState` each frame (isDown / stick) just like on the native side.

/** @typedef {'Up'|'Down'|'Left'|'Right'|'A'|'B'|'X'|'Y'|'Start'|'Select'} Button */

/** Logical buttons (mirrors Rust `Button`). */
export const Button = {
  Up: 'Up', Down: 'Down', Left: 'Left', Right: 'Right',
  A: 'A', B: 'B', X: 'X', Y: 'Y', Start: 'Start', Select: 'Select',
};

/** HSP-`stick`-compatible bit per button (mirrors Rust `Button::stick_bit`). */
export const STICK_BIT = {
  Left: 1, Up: 2, Right: 4, Down: 8,
  A: 16, B: 32, Start: 64, Select: 128, X: 256, Y: 512,
};

// KeyboardEvent.code -> Button (mirrors Rust `button_from_key`)
const KEYMAP = {
  ArrowUp: 'Up', Up: 'Up', KeyW: 'Up',
  ArrowDown: 'Down', Down: 'Down', KeyS: 'Down',
  ArrowLeft: 'Left', Left: 'Left', KeyA: 'Left',
  ArrowRight: 'Right', Right: 'Right', KeyD: 'Right',
  KeyZ: 'A', Space: 'A', space: 'A',
  KeyX: 'B',
  KeyC: 'Y',
  KeyV: 'X',
  Enter: 'Start', Return: 'Start',
  ShiftLeft: 'Select', ShiftRight: 'Select',
};

/**
 * Map a `KeyboardEvent.code` to a logical button, or `null`.
 * @param {string} code
 * @returns {Button|null}
 */
export function buttonFromKey(code) {
  return KEYMAP[code] ?? null;
}

/**
 * @typedef {(
 *   | { kind: 'button-down', button: Button }
 *   | { kind: 'button-up', button: Button }
 *   | { kind: 'pointer-move', x: number, y: number }
 *   | { kind: 'pointer-down' }
 *   | { kind: 'pointer-up' }
 * )} InputEvent
 */

/** Polled input state — mirrors Rust `InputState`. */
export class InputState {
  constructor() {
    this.held = 0;
    this.pointer = { x: 0, y: 0 };
    this.pointerDown = false;
  }

  /** Fold one event into the state. @param {InputEvent} ev */
  apply(ev) {
    switch (ev.kind) {
      case 'button-down': this.held |= STICK_BIT[ev.button]; break;
      case 'button-up': this.held &= ~STICK_BIT[ev.button]; break;
      case 'pointer-move': this.pointer = { x: ev.x, y: ev.y }; break;
      case 'pointer-down': this.pointerDown = true; break;
      case 'pointer-up': this.pointerDown = false; break;
    }
  }

  /** Is `button` currently held? @param {Button} button */
  isDown(button) {
    return (this.held & STICK_BIT[button]) !== 0;
  }

  /** The HSP-`stick`-compatible bitmask of all held buttons. */
  stick() {
    return this.held;
  }
}

/**
 * Attach DOM listeners that drive `state` from a target's keyboard + pointer
 * events. `onEvent` (optional) is called with each {@link InputEvent}. Returns a
 * detach function.
 * @param {EventTarget} target  e.g. window, or a canvas element
 * @param {InputState} state
 * @param {(ev: InputEvent) => void} [onEvent]
 * @returns {() => void} detach
 */
export function attach(target, state, onEvent) {
  const emit = (ev) => { state.apply(ev); if (onEvent) onEvent(ev); };
  const onKeyDown = (e) => { const b = buttonFromKey(e.code); if (b) emit({ kind: 'button-down', button: b }); };
  const onKeyUp = (e) => { const b = buttonFromKey(e.code); if (b) emit({ kind: 'button-up', button: b }); };
  const onMove = (e) => emit({ kind: 'pointer-move', x: e.offsetX | 0, y: e.offsetY | 0 });
  const onDown = () => emit({ kind: 'pointer-down' });
  const onUp = () => emit({ kind: 'pointer-up' });

  target.addEventListener('keydown', onKeyDown);
  target.addEventListener('keyup', onKeyUp);
  target.addEventListener('pointermove', onMove);
  target.addEventListener('pointerdown', onDown);
  target.addEventListener('pointerup', onUp);

  return () => {
    target.removeEventListener('keydown', onKeyDown);
    target.removeEventListener('keyup', onKeyUp);
    target.removeEventListener('pointermove', onMove);
    target.removeEventListener('pointerdown', onDown);
    target.removeEventListener('pointerup', onUp);
  };
}
