# shellcheck shell=bash
# Shared body of the scroll capture scenarios. The scenario sets
# E2E_SCROLL_MODE to manual or auto, sources lib.sh, runs e2e_begin, and
# then sources this file.
#
# omasnap --scroll runs over a foot window whose scrollback holds a long
# file, rewound to the top. Manual: the test wheels the page through the
# overlay's input hole while omasnap grabs frames. Auto: omasnap scrolls the
# page itself through the fork's wlr virtual pointer path. Done stitches,
# and the stitched PNG on the clipboard must be much taller than the region.
command -v foot >/dev/null || { e2e_record_result FAIL "foot is installed"; e2e_fails=1; e2e_end; }

# HEADLESS-2 has scale 1, so overlay surface pixels equal layout pixels
# offset by the output's x of 1280.
swaymsg 'focus output HEADLESS-2' >/dev/null
# Lines of different lengths and words: the stitcher matches row shapes, and
# 150 lines of the same sentence repeat every line, so no step can be
# measured (each grab reads as Still).
awk 'BEGIN {
  split("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango", w, " ")
  for (i = 1; i <= 150; i++) {
    line = sprintf("%03d %*s", i, (i * 7) % 23, "")
    for (j = 0; j < 2 + (i * 5) % 9; j++) line = line " " w[1 + (i * 3 + j * 11) % 20]
    print line
  }
}' >"$e2e_dir/page.txt"
e2e_caption "foot shows a 150-line file on HEADLESS-2, rewound to the top"
e2e_spawn foot --app-id e2e-page --font 'DejaVu Sans Mono:size=14' \
  sh -c "cat '$e2e_dir/page.txt'; exec sleep 600"
e2e_wait "foot window maps" 10 e2e_has_view '.app_id == "e2e-page"'
sleep 1
# foot scrolls 3 lines a notch, so 80 notches are more than enough to reach the top.
e2e_pointer move 2240 500 wheel -80
sleep 0.5
grim -o HEADLESS-2 "$e2e_dir/frames/desktop-HEADLESS-2.png"
e2e_pause

e2e_caption "omasnap --scroll, then drag a region over the page"
e2e_clipboard_clear
mkdir -p "$e2e_dir/scroll-debug"
OMASNAP_SCROLL_DEBUG_DIR="$e2e_dir/scroll-debug" e2e_omasnap --scroll; sc=$e2e_pid
e2e_wait "scroll overlay covers HEADLESS-2" 10 \
  e2e_output_changed HEADLESS-2 "$e2e_dir/frames/desktop-HEADLESS-2.png"
e2e_pause
# Region in surface pixels: (10,150) to (1110,800). It must include the line
# numbers: the rest of each line is identical, and the stitcher needs rows
# that differ to measure each scroll step.
region_left=10; region_right=1110; region_bottom=800
e2e_pointer move $((1280 + region_left)) 150 sleep 200 down \
  glide $((1280 + region_right)) "$region_bottom" 800 sleep 200 up
sleep 1
e2e_still region

# Mode pills: five of 118x40 with 10 px gaps centred under the region at
# y = bottom + 18 (scrollOverlayPillRect). Index 0 is Manual down, index 1
# Auto down.
region_cx=$(( (region_left + region_right) / 2 ))
pill_left=$(( 1280 + region_cx - (5 * 118 + 4 * 10) / 2 ))
manual_x=$(( pill_left + 59 ))
auto_x=$(( pill_left + 118 + 10 + 59 ))
pill_y=$(( region_bottom + 18 + 20 ))
# Capturing pills are 132x40 with 12 px gaps, index 0 is Done. There are
# three (Done, Back, Cancel), or four with Continue once auto scroll stops at
# the end. Done spans [cx-210, cx-78] with three and [cx-282, cx-150] with
# four, so click the middle of the overlap at cx-180.
done_x=$(( 1280 + region_cx - 180 ))
stitched_tall() { [[ $(cut -dx -f2 <<<"$1") -ge 1625 ]]; }

if [[ "$E2E_SCROLL_MODE" == manual ]]; then
  e2e_caption "click Manual down, then scroll the page with the wheel"
  e2e_pointer glide "$manual_x" "$pill_y" 500 sleep 300 click
  sleep 1
  # Wheel over the live page, through the overlay's input hole: 3 notches
  # (9 lines) a step, with time for omasnap to grab each settled frame.
  for _ in $(seq 12); do
    e2e_pointer move $((1280 + region_cx)) 500 wheel 3 sleep 700
  done
  e2e_still manual-end
  e2e_caption "click Done to stitch"
  e2e_pointer glide "$done_x" "$pill_y" 400 sleep 300 click
  e2e_wait "clipboard offers the stitched image/png" 15 e2e_clipboard_has_png
  size=$(e2e_clipboard_png_size)
  e2e_log "stitched size $size"
  e2e_check "manual stitch is at least 2.5x the 650 px region ($size)" stitched_tall "$size"
else
  e2e_caption "click Auto down"
  e2e_pointer glide "$auto_x" "$pill_y" 500 sleep 300 click
  sleep 3
  e2e_wait "auto scroll stops" 60 e2e_output_still HEADLESS-2 2
  e2e_still auto-end
  e2e_caption "click Done to stitch"
  e2e_pointer glide "$done_x" "$pill_y" 400 sleep 300 click
  e2e_wait "clipboard offers the stitched image/png" 15 e2e_clipboard_has_png
  size=$(e2e_clipboard_png_size)
  e2e_log "stitched size $size"
  e2e_check "auto stitch is at least 2.5x the 650 px region ($size)" stitched_tall "$size"
fi
e2e_pause 3
e2e_still stitched
e2e_stop "$sc"

e2e_end
