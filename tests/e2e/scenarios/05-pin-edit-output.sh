#!/usr/bin/env bash
# A real click on the Edit control of a pin on HEADLESS-2, while HEADLESS-1
# has focus, opens the editor on HEADLESS-2 (the fork's Sway IPC lookup in
# pinEditorArguments, in place of upstream #165's Qt screen).
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 05-pin-edit-output "Pin Edit: the editor opens on the pin's output"
card="$e2e_dir/card.png"; e2e_fixture "$card"

e2e_caption "pin the card on HEADLESS-2"
swaymsg 'focus output HEADLESS-2' >/dev/null
e2e_omasnap --pin "$card"; pin=$e2e_pid
e2e_wait "pin maps on HEADLESS-2" 10 e2e_has_view '(.name | startswith("omasnap-pin")) and .output == "HEADLESS-2"'
swaymsg 'focus output HEADLESS-1' >/dev/null
e2e_check "HEADLESS-1 has focus before the click" e2e_eq HEADLESS-1 "$(e2e_focused_output)"
sleep 1
for o in HEADLESS-1 HEADLESS-2; do grim -o "$o" "$e2e_dir/frames/before-edit-$o.png"; done
e2e_pause

pin_json=$(swaymsg -r -t get_tree | jq -c '[recurse(.nodes[]?, .floating_nodes[]?) | select(.name? // "" | startswith("omasnap-pin"))][0] | {rect, window_rect}')
read -r px py pw ph < <(jq -r '"\(.rect.x + .window_rect.x) \(.rect.y + .window_rect.y) \(.window_rect.width) \(.window_rect.height)"' <<<"$pin_json")
# Edit control (pinControlRect index 3) centre: (w-6)/2-52+26, max((h-26)/2,36)+13.
ex=$(( px + (pw - 6) / 2 - 26 )); ey=$(( py + ( (ph - 26) / 2 > 36 ? (ph - 26) / 2 : 36 ) + 13 ))
e2e_caption "hover the pin, then click Edit at $ex,$ey"
e2e_pointer move 900 400 glide "$((px + pw / 2))" "$((py + ph / 2))" 600 sleep 600 glide "$ex" "$ey" 300 sleep 400 click

edit_child_started() { e2e_omasnap_argv | grep -q -- '--pin-document.*--handoff-monitor HEADLESS-2'; }
e2e_wait "an editor child starts with --handoff-monitor HEADLESS-2" 10 edit_child_started
e2e_omasnap_argv >"$e2e_dir/argv-after-click.txt"
e2e_wait "the editor overlay appears on HEADLESS-2" 10 \
  e2e_output_changed HEADLESS-2 "$e2e_dir/frames/before-edit-HEADLESS-2.png"
h1_unchanged() { ! e2e_output_changed HEADLESS-1 "$e2e_dir/frames/before-edit-HEADLESS-1.png"; }
e2e_check "HEADLESS-1 stays unchanged" h1_unchanged
e2e_pause 2
e2e_still after-edit

e2e_end
