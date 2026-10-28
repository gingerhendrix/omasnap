#!/usr/bin/env bash
# OCR on a real capture: a foot terminal shows known text, omasnap captures
# the monitor, and O in the windowed editor runs tesseract (one thread) and
# copies the recognised text to the clipboard.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 08-ocr "OCR: recognise text from a real capture"
command -v foot >/dev/null || { e2e_record_result FAIL "foot is installed"; e2e_fails=1; e2e_end; }

swaymsg 'focus output HEADLESS-1' >/dev/null
e2e_caption "foot shows a known line of text"
e2e_spawn foot --app-id e2e-text --font 'DejaVu Sans Mono:size=26' \
  sh -c 'printf "\n  OMASNAP OCR CHECK 4217\n  the quick brown fox\n"; exec sleep 600'
e2e_wait "foot window maps" 10 e2e_has_view '.app_id == "e2e-text"'
sleep 1
e2e_pause

e2e_caption "capture the monitor with --save"
"$OMASNAP_BIN" --capture-fullscreen --save >>"$e2e_dir/clients.log" 2>&1
shot=$(find "$e2e_dir/shots" -name '*.png' | head -n1)
e2e_check "capture saved" test -s "$shot"

e2e_caption "open the capture in the windowed editor and press O"
e2e_clipboard_clear
e2e_omasnap --editor window --file "$shot"; ed=$e2e_pid
e2e_wait "editor window maps" 10 e2e_has_view '.app_id == "omasnap" and .focused'
sleep 1
ocr_copied() { wl-paste --no-newline 2>/dev/null | grep -q 'OMASNAP OCR CHECK 4217'; }
e2e_keys_until 3 15 ocr_copied -- o
e2e_check "clipboard holds the recognised line" ocr_copied
wl-paste --no-newline >"$e2e_dir/ocr-text.txt" 2>/dev/null
e2e_check "clipboard holds the second line" grep -q 'quick brown fox' "$e2e_dir/ocr-text.txt"
e2e_pause 3
e2e_still ocr
e2e_stop "$ed"

e2e_end
