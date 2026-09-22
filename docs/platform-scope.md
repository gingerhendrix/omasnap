# Platform scope: Wayland + Sway, on purpose

This fork targets one platform: **Wayland, on Sway, on vanilla Arch Linux.**
Upstream Omasnap targets Hyprland on Omarchy. Upstream's own scope document
says a port that adds compositor branching belongs in a fork. This is that
fork. It replaces the Hyprland integration and does not keep both.

## What "Sway-only" means concretely

- Output and window discovery go through Sway IPC:
  `swaymsg -t get_outputs` and `swaymsg -t get_tree` (see
  `src/capture.cpp`). The tree walk covers tiled and floating containers,
  named workspaces, and Xwayland views, and clips each container to the
  focused output.
- Window capture crops the frozen output frame. It needs no
  foreign-toplevel capture source, which Sway 1.11 does not provide.
- Pins and the windowed editor are placed with `[con_id=N]` commands
  through `swaymsg` (`src/sway-ipc.cpp`, `src/pin.cpp`, `src/main.cpp`).
  Pins float, stay sticky, and lose their border. A `no_focus` rule and a
  quoted `for_window` rule are registered once per Sway session so a new
  pin never takes focus. The stack's work area is the visible workspace
  rectangle, so bars on any edge are respected.
- Notifications use freedesktop `notify-send` with an image hint.

## Known differences from upstream on Hyprland

- Sway has no always-on-top state for floating windows. Sway raises a
  floating window only by focusing it, so a focused floating window can
  cover pins. Restoring the idle deck order focuses each card and then
  hands focus back to the window that held it.
- Sway has no cursor-position query. The fan-out closes when the pointer
  leaves the pin that owns it and no other card takes ownership within a
  short delay. Upstream measures the pointer against the whole stack.
- Sway rules are not named and cannot be withdrawn. The windowed editor is
  floated after it maps and can show tiled for one frame. After
  `swaymsg reload`, the pin rules are gone until the next Sway session;
  pins still float and stick but can take focus when created.
- Auto scroll capture always uses the wlr virtual pointer. Sway applies
  natural scrolling per input device, so the policy an injected uinput
  mouse would get is unknown.
- `notify-send` has no click command, so saved-capture notifications
  carry no reopen action. Use `omasnap <path>` to reopen a saved file.

## What is generic

The capture and injection mechanisms are standard Wayland protocols:
`ext-image-copy-capture` for reading pixels (`src/surface-capture.cpp`),
`zwlr_virtual_pointer_v1` for injected scroll input
(`src/scroll-inject.cpp`), and `layer-shell` for the capture overlay and
the overlay editor. Some keyboard-grab comments in `src/scroll-capture.cpp`
describe Hyprland behaviour observed upstream; the code paths are kept
unchanged.

## Changes in this fork

- Keep compositor code on the Sway path only. Do not add compositor
  detection, a second backend, or a flag that selects one.
- Do not reintroduce `hyprctl`, Hyprland Lua rules, or Omarchy tools.
- Sync upstream by rebuilding the Sway line on a release tag and adapting
  behaviour, not by replaying old patches.

## X11, macOS, Windows

Not supported and not planned.
