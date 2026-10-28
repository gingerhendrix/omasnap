#!/usr/bin/env bash
# Save As (Ctrl+Shift+S) from the overlay editor opens a chooser that floats
# and centres through the fork's Sway for_window rule (commit 57564b7).
# After `swaymsg reload` Sway drops runtime rules, so the chooser tiles until
# the next Sway session: a known gap, recorded as XFAIL.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 06-save-as "Save As: the chooser floats and centres"
card="$e2e_dir/card.png"; e2e_fixture "$card"
chooser='.name == "Save screenshot as"'

open_chooser() { # <caption>
  e2e_caption "$1"
  e2e_omasnap --file "$card"; ed=$e2e_pid
  sleep 2
  # saveAs() ignores a press while its chooser is pending, so a retry cannot
  # open a second chooser.
  e2e_keys_until 6 4 "e2e_has_view '$chooser'" -- -M ctrl -M shift -P s -p s -m shift -m ctrl
}

swaymsg 'focus output HEADLESS-1' >/dev/null
open_chooser "overlay editor, then Ctrl+Shift+S"
e2e_check "the Save As chooser maps" e2e_has_view "$chooser"
e2e_check "the chooser is floating" e2e_has_view "$chooser and .type == \"floating_con\""
# Sway's `move position center` places the chooser 12.5 px below the work
# area centre on HEADLESS-1, half the 25 px bar (measured), so allow 16 px.
e2e_check "the chooser is centred in its output's work area" e2e_centred "$chooser" 16
e2e_check "one Save As rule stamp for this Sway" e2e_eq 1 \
  "$(find "$XDG_RUNTIME_DIR" -name 'sway-save-as-rule-*' | wc -l)"
e2e_pause 2
e2e_still chooser
e2e_stop "$ed"

e2e_caption "swaymsg reload drops the runtime for_window rule"
swaymsg reload >/dev/null
sleep 1
swaymsg 'focus output HEADLESS-1' >/dev/null
open_chooser "overlay editor after reload, then Ctrl+Shift+S"
e2e_check "the Save As chooser maps after reload" e2e_has_view "$chooser"
e2e_xfail "the chooser floats after swaymsg reload" e2e_has_view "$chooser and .type == \"floating_con\""
e2e_pause 2
e2e_still chooser-after-reload
e2e_stop "$ed"

e2e_end
