#!/usr/bin/env bash
# The windowed editor floats and centres in the focused output's work area,
# and --handoff-monitor moves it to the named output.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 03-window-editor "Windowed editor: floats, centres, follows --handoff-monitor"
card="$e2e_dir/card.png"; e2e_fixture "$card"
editor='.app_id == "omasnap" and (.name | startswith("omasnap card"))'

e2e_caption "omasnap --editor window --file card.png on HEADLESS-1"
swaymsg 'focus output HEADLESS-1' >/dev/null
e2e_omasnap --editor window --file "$card"; ed=$e2e_pid
e2e_wait "editor window maps" 10 e2e_has_view "$editor"
e2e_check "editor is on HEADLESS-1" e2e_has_view "$editor and .output == \"HEADLESS-1\""
e2e_check "editor is floating" e2e_has_view "$editor and .type == \"floating_con\""
e2e_check "editor is centred in the work area" e2e_centred "$editor"
e2e_check "editor has focus" e2e_has_view "$editor and .focused"
e2e_pause 2
e2e_still editor-HEADLESS-1
e2e_stop "$ed"

e2e_caption "--handoff-monitor HEADLESS-2 while HEADLESS-1 is focused"
swaymsg 'focus output HEADLESS-1' >/dev/null
e2e_omasnap --editor window --file "$card" --handoff-monitor HEADLESS-2; ed=$e2e_pid
e2e_wait "editor window maps" 10 e2e_has_view "$editor"
e2e_check "editor opens on HEADLESS-2" e2e_has_view "$editor and .output == \"HEADLESS-2\""
e2e_check "editor is floating" e2e_has_view "$editor and .type == \"floating_con\""
e2e_check "editor is centred in the HEADLESS-2 work area" e2e_centred "$editor"
e2e_pause 2
e2e_still editor-HEADLESS-2
e2e_stop "$ed"

e2e_end
