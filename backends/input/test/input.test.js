// Verify the web input binding folds DOM events into the same state + HSP stick
// bitmask the Rust core (crates/nelisp-input) does. No DOM: a mock EventTarget
// records listeners and dispatches synthetic events.
//
// Run:  node --test   (from backends/input/)

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { InputState, Button, STICK_BIT, buttonFromKey, attach } from '../src/index.js';

function makeTarget() {
  const listeners = {};
  return {
    addEventListener(type, fn) { (listeners[type] ||= []).push(fn); },
    removeEventListener(type, fn) { listeners[type] = (listeners[type] || []).filter((f) => f !== fn); },
    dispatch(type, ev) { for (const fn of listeners[type] || []) fn(ev); },
    count(type) { return (listeners[type] || []).length; },
  };
}

test('keys map to buttons (parity with Rust button_from_key)', () => {
  assert.equal(buttonFromKey('ArrowUp'), Button.Up);
  assert.equal(buttonFromKey('KeyW'), Button.Up);
  assert.equal(buttonFromKey('Space'), Button.A);
  assert.equal(buttonFromKey('Enter'), Button.Start);
  assert.equal(buttonFromKey('KeyQ'), null);
});

test('stick bits match the HSP-compatible layout (parity with Rust)', () => {
  assert.deepEqual(
    { Left: STICK_BIT.Left, Up: STICK_BIT.Up, Right: STICK_BIT.Right, Down: STICK_BIT.Down, A: STICK_BIT.A },
    { Left: 1, Up: 2, Right: 4, Down: 8, A: 16 },
  );
});

test('held buttons track keydown/keyup through attach', () => {
  const target = makeTarget();
  const state = new InputState();
  const detach = attach(target, state);

  target.dispatch('keydown', { code: 'ArrowUp' });
  target.dispatch('keydown', { code: 'KeyZ' }); // A
  assert.ok(state.isDown(Button.Up));
  assert.ok(state.isDown(Button.A));
  assert.ok(!state.isDown(Button.Down));
  assert.equal(state.stick(), 2 | 16); // up | a

  target.dispatch('keyup', { code: 'ArrowUp' });
  assert.ok(!state.isDown(Button.Up));
  assert.equal(state.stick(), 16);

  // unmapped keys are ignored
  target.dispatch('keydown', { code: 'KeyQ' });
  assert.equal(state.stick(), 16);

  detach();
  target.dispatch('keydown', { code: 'ArrowDown' });
  assert.ok(!state.isDown(Button.Down), 'no events after detach');
  assert.equal(target.count('keydown'), 0, 'detach removed the listener');
});

test('pointer tracks move + buttons', () => {
  const target = makeTarget();
  const state = new InputState();
  attach(target, state);

  target.dispatch('pointermove', { offsetX: 42, offsetY: 7 });
  target.dispatch('pointerdown', {});
  assert.deepEqual(state.pointer, { x: 42, y: 7 });
  assert.ok(state.pointerDown);

  target.dispatch('pointerup', {});
  assert.ok(!state.pointerDown);
});

test('onEvent callback receives each event', () => {
  const target = makeTarget();
  const state = new InputState();
  const events = [];
  attach(target, state, (ev) => events.push(ev));

  target.dispatch('keydown', { code: 'ArrowLeft' });
  target.dispatch('keyup', { code: 'ArrowLeft' });
  assert.deepEqual(events, [
    { kind: 'button-down', button: Button.Left },
    { kind: 'button-up', button: Button.Left },
  ]);
});
