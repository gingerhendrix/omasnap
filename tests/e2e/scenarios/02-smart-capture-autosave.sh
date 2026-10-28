#!/usr/bin/env bash
# The capture overlay maps as a layer-shell surface, a click on open space
# captures the focused monitor, and autosave (on by default since v1.22.0)
# writes one PNG. With [output] autosave = false the same click only copies.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 02-smart-capture-autosave "Smart capture: overlay, click to capture, autosave on and off"
swaymsg 'focus output HEADLESS-1' >/dev/null
grim -o HEADLESS-1 "$e2e_dir/frames/desktop-HEADLESS-1.png"

capture_by_click() {
  e2e_omasnap; overlay=$e2e_pid
  e2e_wait "capture overlay covers HEADLESS-1" 10 \
    e2e_output_changed HEADLESS-1 "$e2e_dir/frames/desktop-HEADLESS-1.png"
  e2e_pause
  e2e_caption "$1"
  e2e_pointer glide 640 400 500 sleep 200 click
}

e2e_caption "autosave default: omasnap, then click open space"
e2e_clipboard_clear
capture_by_click "click open space: capture the whole monitor"
e2e_wait "autosave writes one PNG" 10 bash -c "[[ \$(find '$e2e_dir/shots' -name '*.png' | wc -l) == 1 ]]"
e2e_wait "clipboard offers image/png" 5 e2e_clipboard_has_png
e2e_check "clipboard PNG is 1920x1080" e2e_eq 1920x1080 "$(e2e_clipboard_png_size)"
e2e_pause 2
e2e_still autosave-on
e2e_stop "$overlay"

e2e_caption "autosave = false: the same click copies and saves nothing"
e2e_set_config "[output]
directory = $e2e_dir/shots
autosave = false"
e2e_clipboard_clear
capture_by_click "click open space with autosave = false"
e2e_wait "clipboard offers image/png" 5 e2e_clipboard_has_png
sleep 2
e2e_check "no new PNG with autosave = false" e2e_eq 1 "$(e2e_png_count "$e2e_dir/shots")"
e2e_pause 2
e2e_still autosave-off
e2e_stop "$overlay"

e2e_end
