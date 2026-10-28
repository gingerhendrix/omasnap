#!/usr/bin/env bash
# Quick output: --save writes a native-resolution PNG with its logical size,
# and --copy puts a PNG on the Wayland clipboard. Both use the in-process
# ext-image-copy-capture path on a 1.5-scale output.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 01-quick-capture "Quick capture: --save and --copy on a 1.5-scale output"

e2e_caption "omasnap --capture-fullscreen --save on HEADLESS-1"
swaymsg 'focus output HEADLESS-1' >/dev/null
"$OMASNAP_BIN" --capture-fullscreen --save >>"$e2e_dir/clients.log" 2>&1
e2e_check "--save exits 0" e2e_eq 0 "$?"
shot=$(find "$e2e_dir/shots" -name '*.png' | head -n1)
e2e_check "--save writes exactly one PNG" e2e_eq 1 "$(e2e_png_count "$e2e_dir/shots")"
e2e_check "PNG has the native 1920x1080 pixels" e2e_eq 1920x1080 "$(e2e_png_size "$shot")"
e2e_check "PNG records logical size 1280x720" e2e_eq 1280x720 "$(e2e_png_logical_size "$shot")"
e2e_pause

e2e_caption "the saved capture, shown in a pin"
e2e_omasnap --pin "$shot"; pin=$e2e_pid
e2e_wait "pin window maps" 10 e2e_has_view '.name | startswith("omasnap-pin")'
e2e_pause 2
e2e_stop "$pin"

e2e_caption "omasnap --capture-fullscreen --copy on HEADLESS-2"
e2e_clipboard_clear
swaymsg 'focus output HEADLESS-2' >/dev/null
"$OMASNAP_BIN" --capture-fullscreen --copy >>"$e2e_dir/clients.log" 2>&1
e2e_check "--copy exits 0" e2e_eq 0 "$?"
e2e_wait "clipboard offers image/png" 5 e2e_clipboard_has_png
e2e_check "clipboard PNG is 1920x1080" e2e_eq 1920x1080 "$(e2e_clipboard_png_size)"
e2e_check "--copy writes no file" e2e_eq 1 "$(e2e_png_count "$e2e_dir/shots")"
e2e_pause

e2e_end
