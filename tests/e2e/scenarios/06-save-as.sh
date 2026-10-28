#!/usr/bin/env bash
# Save As (Ctrl+Shift+S) from the overlay editor opens a chooser that floats
# and centres through the fork's Sway for_window rule (commit 57564b7).
# `swaymsg reload` drops runtime rules but not omasnap's stamp. The first
# chooser after it maps tiled, and omasnap floats it, centres it and
# registers the rule again, so the next chooser maps floating by the rule.
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
# The stamp written before the reload is at least 1 s older than this.
sleep 1.1
reloaded=$(date +%s)
swaymsg reload >/dev/null
sleep 1
swaymsg 'focus output HEADLESS-1' >/dev/null
open_chooser "overlay editor after reload, then Ctrl+Shift+S"
e2e_check "the Save As chooser maps after reload" e2e_has_view "$chooser"
e2e_wait "omasnap floats the chooser after swaymsg reload" 3 \
  e2e_has_view "$chooser and .type == \"floating_con\""
e2e_check "the repaired chooser is centred" e2e_centred "$chooser" 16
e2e_check "still one Save As rule stamp" e2e_eq 1 \
  "$(find "$XDG_RUNTIME_DIR" -name 'sway-save-as-rule-*' | wc -l)"
# The stamp is written only after the rule commands succeed, so a stamp
# newer than the reload shows the rule was registered again.
e2e_check "the rule stamp was rewritten after the reload" e2e_eq 1 \
  "$(find "$XDG_RUNTIME_DIR" -name 'sway-save-as-rule-*' -newermt "@$reloaded" | wc -l)"
e2e_pause 2
e2e_still chooser-after-reload
e2e_stop "$ed"

e2e_caption "a second chooser floats by the re-registered rule"
open_chooser "overlay editor, then Ctrl+Shift+S again"
e2e_check "the next chooser is floating" e2e_has_view "$chooser and .type == \"floating_con\""
e2e_pause 2
e2e_stop "$ed"

e2e_end
