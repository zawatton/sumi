//! Backend-agnostic *input* vocabulary for nelisp — the sibling of `nelisp-gui`.
//!
//! Drawing flows program → host (the `nelisp-gui` command vocabulary). Input
//! flows the other way: a shell (DOM in a webview, GTK in a native window)
//! translates native key / pointer events into a common [`InputEvent`], folds
//! them into an [`InputState`], and a nelisp program polls that state each frame —
//! e.g. [`InputState::is_down`] or the HSP-`stick`-compatible [`InputState::stick`]
//! bitmask. The web binding (`backends/input/`) mirrors these exact button names
//! and bit values so both sides agree.

/// A logical button — the directional + action set a 2D program needs, the
/// common denominator of a keyboard and a gamepad.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Button {
    Up,
    Down,
    Left,
    Right,
    A,
    B,
    X,
    Y,
    Start,
    Select,
}

impl Button {
    /// Every button, for iteration.
    pub const ALL: [Button; 10] = [
        Button::Up,
        Button::Down,
        Button::Left,
        Button::Right,
        Button::A,
        Button::B,
        Button::X,
        Button::Y,
        Button::Start,
        Button::Select,
    ];

    /// This button's bit in the HSP-`stick`-compatible mask
    /// (left=1, up=2, right=4, down=8, then action/system buttons).
    pub fn stick_bit(self) -> u32 {
        match self {
            Button::Left => 1,
            Button::Up => 2,
            Button::Right => 4,
            Button::Down => 8,
            Button::A => 16,
            Button::B => 32,
            Button::Start => 64,
            Button::Select => 128,
            Button::X => 256,
            Button::Y => 512,
        }
    }
}

/// Map a key name to a logical button. Accepts browser `KeyboardEvent.code`
/// values (`ArrowUp`, `KeyZ`, `Space`…) and bare GTK-ish key names (`Up`,
/// `space`), so the same mapping serves the web and native shells. WASD doubles
/// the arrows; Z/X/A/S are the action buttons.
pub fn button_from_key(code: &str) -> Option<Button> {
    match code {
        "ArrowUp" | "Up" | "KeyW" => Some(Button::Up),
        "ArrowDown" | "Down" | "KeyS" => Some(Button::Down),
        "ArrowLeft" | "Left" | "KeyA" => Some(Button::Left),
        "ArrowRight" | "Right" | "KeyD" => Some(Button::Right),
        "KeyZ" | "Space" | "space" => Some(Button::A),
        "KeyX" => Some(Button::B),
        "KeyC" => Some(Button::Y),
        "KeyV" => Some(Button::X),
        "Enter" | "Return" => Some(Button::Start),
        "ShiftLeft" | "ShiftRight" | "Shift_L" | "Shift_R" => Some(Button::Select),
        _ => None,
    }
}

/// One input event delivered by a shell.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InputEvent {
    ButtonDown(Button),
    ButtonUp(Button),
    PointerMove { x: i32, y: i32 },
    PointerDown,
    PointerUp,
}

/// Polled input state — what a program reads each frame. Buttons are kept as a
/// bitset of [`Button::stick_bit`] values so [`stick`](Self::stick) is O(1).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct InputState {
    held: u32,
    pub pointer: (i32, i32),
    pub pointer_down: bool,
}

impl InputState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Fold one event into the state.
    pub fn apply(&mut self, ev: &InputEvent) {
        match ev {
            InputEvent::ButtonDown(b) => self.held |= b.stick_bit(),
            InputEvent::ButtonUp(b) => self.held &= !b.stick_bit(),
            InputEvent::PointerMove { x, y } => self.pointer = (*x, *y),
            InputEvent::PointerDown => self.pointer_down = true,
            InputEvent::PointerUp => self.pointer_down = false,
        }
    }

    /// Is `button` currently held?
    pub fn is_down(&self, button: Button) -> bool {
        self.held & button.stick_bit() != 0
    }

    /// The HSP-`stick`-compatible bitmask of all held buttons.
    pub fn stick(&self) -> u32 {
        self.held
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_map_to_buttons() {
        assert_eq!(button_from_key("ArrowUp"), Some(Button::Up));
        assert_eq!(button_from_key("KeyW"), Some(Button::Up));
        assert_eq!(button_from_key("Space"), Some(Button::A));
        assert_eq!(button_from_key("Enter"), Some(Button::Start));
        assert_eq!(button_from_key("KeyQ"), None);
    }

    #[test]
    fn held_buttons_track_down_and_up() {
        let mut s = InputState::new();
        s.apply(&InputEvent::ButtonDown(Button::Up));
        s.apply(&InputEvent::ButtonDown(Button::A));
        assert!(s.is_down(Button::Up));
        assert!(s.is_down(Button::A));
        assert!(!s.is_down(Button::Down));
        // HSP mask: up=2 | a=16 = 18
        assert_eq!(s.stick(), 2 | 16);

        s.apply(&InputEvent::ButtonUp(Button::Up));
        assert!(!s.is_down(Button::Up));
        assert_eq!(s.stick(), 16);
    }

    #[test]
    fn pointer_tracks_move_and_buttons() {
        let mut s = InputState::new();
        s.apply(&InputEvent::PointerMove { x: 42, y: 7 });
        s.apply(&InputEvent::PointerDown);
        assert_eq!(s.pointer, (42, 7));
        assert!(s.pointer_down);
        s.apply(&InputEvent::PointerUp);
        assert!(!s.pointer_down);
    }

    #[test]
    fn stick_bits_are_distinct() {
        let mut seen = 0u32;
        for b in Button::ALL {
            let bit = b.stick_bit();
            assert_eq!(seen & bit, 0, "{b:?} bit overlaps another");
            seen |= bit;
        }
    }
}
