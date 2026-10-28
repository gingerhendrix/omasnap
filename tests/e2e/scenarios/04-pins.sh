#!/usr/bin/env bash
# Pins are floating, sticky and borderless, do not take focus from the
# editor, stack with the 12 px deck lip, stay visible on another workspace,
# and register their Sway rules once per Sway instance. After `swaymsg
# reload` drops the rules, the next pin brings them back.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 04-pins "Pins: floating, sticky, borderless, no focus steal"
card="$e2e_dir/card.png"; e2e_fixture "$card"
editor='(.name | startswith("omasnap card"))'
pin='(.name | startswith("omasnap-pin"))'

swaymsg 'focus output HEADLESS-1' >/dev/null
e2e_caption "open the windowed editor, then pin the card twice"
e2e_omasnap --editor window --file "$card"; ed=$e2e_pid
e2e_wait "editor window maps" 10 e2e_has_view "$editor"
e2e_omasnap --pin "$card"; pin1=$e2e_pid
e2e_wait "first pin maps" 10 e2e_has_view "$pin"
e2e_pause
e2e_omasnap --pin "$card"; pin2=$e2e_pid
e2e_wait "second pin maps" 10 bash -c "[[ \$(swaymsg -r -t get_tree | jq '[recurse(.nodes[]?, .floating_nodes[]?) | select(.name? // \"\" | startswith(\"omasnap-pin\"))] | length') == 2 ]]"
sleep 1
e2e_views >"$e2e_dir/views-pins.json"
e2e_check "both pins are floating" e2e_eq 2 "$(jq "[.[] | select($pin and .type == \"floating_con\")] | length" "$e2e_dir/views-pins.json")"
e2e_check "both pins are sticky" e2e_eq 2 "$(jq "[.[] | select($pin and .sticky)] | length" "$e2e_dir/views-pins.json")"
e2e_check "both pins have border none" e2e_eq 2 "$(jq "[.[] | select($pin and .border == \"none\")] | length" "$e2e_dir/views-pins.json")"
e2e_check "the editor keeps focus" e2e_has_view "$editor and .focused"
e2e_check "pins stack 12 px apart (deck lip)" e2e_eq 12 \
  "$(jq "[.[] | select($pin) | .rect.y] | sort | .[1] - .[0] | fabs" "$e2e_dir/views-pins.json")"
e2e_pause 2
e2e_still pins
e2e_stop "$ed"

e2e_caption "switch to workspace 9: sticky pins follow"
swaymsg 'workspace 9' >/dev/null
sleep 1
e2e_check "both pins are on workspace 9" e2e_eq 2 "$(swaymsg -r -t get_tree | jq \
  '[.. | objects | select(.type? == "workspace" and .name == "9") | .floating_nodes[] | select(.name | startswith("omasnap-pin"))] | length')"
e2e_pause 2
e2e_still pins-workspace-9
swaymsg 'workspace 1' >/dev/null

e2e_check "one pin rule stamp for this Sway" e2e_eq 1 \
  "$(find "$XDG_RUNTIME_DIR" -name 'sway-pin-rules-*' | wc -l)"
e2e_stop "$pin1"; e2e_stop "$pin2"

# The reload drops the no_focus and for_window rules. The first pin after
# it maps tiled and may take focus; its placement pass floats it and
# registers the rules again, so the pin after that leaves focus alone.
e2e_caption "swaymsg reload, then pin twice: the first pin restores the rules"
# The stamp written before the reload is at least 1 s older than this.
sleep 1.1
reloaded=$(date +%s)
swaymsg reload >/dev/null
sleep 1
e2e_omasnap --editor window --file "$card"; ed=$e2e_pid
e2e_wait "editor window maps after reload" 10 e2e_has_view "$editor"
e2e_omasnap --pin "$card"; pin3=$e2e_pid
e2e_wait "the first pin after reload ends floating, sticky and borderless" 10 \
  e2e_has_view "$pin and .type == \"floating_con\" and .sticky and .border == \"none\""
e2e_wait "the pin rule stamp is rewritten after the reload" 5 bash -c \
  "[[ \$(find '$XDG_RUNTIME_DIR' -name 'sway-pin-rules-*' -newermt @$reloaded | wc -l) == 1 ]]"
swaymsg "[pid=$ed] focus" >/dev/null
e2e_check "the editor has focus before the next pin" e2e_has_view "$editor and .focused"
e2e_omasnap --pin "$card"; pin4=$e2e_pid
e2e_wait "two pins after reload" 10 bash -c "[[ \$(swaymsg -r -t get_tree | jq '[recurse(.nodes[]?, .floating_nodes[]?) | select(.name? // \"\" | startswith(\"omasnap-pin\"))] | length') == 2 ]]"
sleep 1
e2e_check "the next pin leaves the editor focused (no_focus is back)" e2e_has_view "$editor and .focused"
e2e_check "both pins after reload are floating" e2e_eq 2 \
  "$(e2e_views | jq "[.[] | select($pin and .type == \"floating_con\")] | length")"
e2e_pause 2
e2e_still pins-after-reload
e2e_stop "$pin3"; e2e_stop "$pin4"; e2e_stop "$ed"

e2e_end
