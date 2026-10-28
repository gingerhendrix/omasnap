# shellcheck shell=bash
# Shared helpers for the headless Sway e2e scenarios (`make e2e`).
#
# Each scenario sources this file, calls e2e_begin, runs steps and checks,
# and ends with e2e_end. e2e_begin starts a private Sway with the headless
# backend and the pixman renderer on a fresh XDG_RUNTIME_DIR. It never talks
# to a live session: SWAYSOCK, WAYLAND_DISPLAY, DISPLAY and the Hyprland
# signature are unset first, and run.sh starts each scenario on its own
# D-Bus session bus. Teardown signals only processes whose environment holds
# this scenario's runtime folder.
#
# Inputs (run.sh sets them):
#   OMASNAP_BIN        omasnap binary under test
#   OMASNAP_E2E_VPTR   omasnap-e2e-vptr helper
#   E2E_OUT            output root; each scenario writes E2E_OUT/<name>/
#   E2E_RECORD         1 records video.mp4 per scenario (needs wf-recorder
#                      and ffmpeg), 0 skips recording
#   E2E_PACE           seconds to hold the screen after visible steps, so
#                      a person can follow the video (0 for fast runs)

set -uo pipefail

E2E_RECORD="${E2E_RECORD:-1}"
E2E_PACE="${E2E_PACE:-1}"
# Layout: HEADLESS-1 is 1920x1080 at scale 1.5 (1280x720 logical) at 0,0.
# HEADLESS-2 is 1920x1080 at scale 1 to its right.
E2E_LAYOUT_W=3200
E2E_LAYOUT_H=1080

e2e_fails=0
e2e_xfails=0
e2e_checks=0
e2e_tracked=""

# ---- logging and assertions -------------------------------------------------

e2e_log() { printf '%s %s\n' "$(date +%H:%M:%S.%3N)" "$*" | tee -a "$e2e_dir/steps.log" >&2; }

# Show text in the Sway bar (and so in the video), and log it with a time
# offset into timeline.txt for the reviewer.
e2e_caption() {
  printf '%s\n' "$*" >"$e2e_dir/caption.txt"
  printf '%6.1fs  %s\n' "$(e2e_elapsed)" "$*" >>"$e2e_dir/timeline.txt"
  e2e_log "== $*"
}

e2e_elapsed() { echo "$(( $(date +%s%N) - e2e_start_ns ))" | awk '{printf "%.1f", $1/1e9}'; }

e2e_pause() { sleep "${1:-$E2E_PACE}"; }

e2e_record_result() { # <PASS|FAIL|XFAIL|XPASS> <description> [detail]
  local status="$1" description="$2" detail="${3:-}"
  e2e_checks=$((e2e_checks + 1))
  printf '%s\t%s\t%s\n' "$status" "$description" "$detail" >>"$e2e_dir/results.tsv"
  printf '%6.1fs  %s  %s\n' "$(e2e_elapsed)" "$status" "$description" >>"$e2e_dir/timeline.txt"
  e2e_log "$status $description${detail:+ ($detail)}"
  printf '%s %s\n' "$status" "$description" >"$e2e_dir/caption.txt"
}

# Run a command; pass when it exits 0.
e2e_check() { # <description> <command>...
  local description="$1"; shift
  local output
  if output=$("$@" 2>&1); then
    e2e_record_result PASS "$description"
  else
    e2e_fails=$((e2e_fails + 1))
    e2e_record_result FAIL "$description" "$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-300)"
  fi
}

# A check that is known to fail today. It records XFAIL when it fails and
# XPASS when it starts to pass, and never fails the scenario.
e2e_xfail() { # <description> <command>...
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then
    e2e_record_result XPASS "$description" "known gap now passes"
  else
    e2e_xfails=$((e2e_xfails + 1))
    e2e_record_result XFAIL "$description"
  fi
}

e2e_eq() { # <expected> <actual>
  [[ "$1" == "$2" ]] || { echo "expected '$1', got '$2'"; return 1; }
}

# Poll a command until it exits 0, for up to <seconds>.
e2e_until() { # <seconds> <command>...
  local seconds="$1"; shift
  local deadline=$(( $(date +%s%N) + seconds * 1000000000 ))
  while :; do
    "$@" >/dev/null 2>&1 && return 0
    (( $(date +%s%N) >= deadline )) && return 1
    sleep 0.2
  done
}

# e2e_until as a check.
e2e_wait() { # <description> <seconds> <command>...
  local description="$1" seconds="$2"; shift 2
  if e2e_until "$seconds" "$@"; then
    e2e_record_result PASS "$description"
  else
    e2e_fails=$((e2e_fails + 1))
    e2e_record_result FAIL "$description" "timed out after ${seconds}s"
  fi
}

# ---- Sway queries -------------------------------------------------------------

# Every client view with its output, as one JSON array.
e2e_views() {
  swaymsg -r -t get_tree | jq -c '[.nodes[] | select(.type=="output") as $o
    | $o | recurse(.nodes[]?, .floating_nodes[]?) | select(.pid != null)
    | {output: $o.name, id, name, app_id, type, focused, sticky, border, rect}]'
}

# Views whose title matches a jq test() regex.
e2e_views_named() { e2e_views | jq -c --arg re "$1" '[.[] | select((.name // "") | test($re))]'; }

# Pass when at least one view matches the jq filter.
e2e_has_view() { e2e_views | jq -e "[.[] | select($1)] | length > 0" >/dev/null; }

e2e_focused_output() { swaymsg -r -t get_outputs | jq -r '.[] | select(.focused) | .name'; }

# Work area of an output in layout coordinates: "x y width height".
e2e_workarea() {
  swaymsg -r -t get_workspaces | jq -r --arg o "$1" \
    '.[] | select(.output == $o and .visible) | "\(.rect.x) \(.rect.y) \(.rect.width) \(.rect.height)"'
}

# Pass when the view matching <filter> is centred in its output's work area
# within <tolerance> px on both axes.
e2e_centred() { # <jq filter> [tolerance]
  local filter="$1" tolerance="${2:-2}" view
  view=$(e2e_views | jq -c "[.[] | select($filter)][0]")
  [[ "$view" == "null" ]] && { echo "no view for $filter"; return 1; }
  local output wx wy ww wh
  output=$(jq -r .output <<<"$view")
  read -r wx wy ww wh < <(e2e_workarea "$output")
  jq -e --argjson wx "$wx" --argjson wy "$wy" --argjson ww "$ww" --argjson wh "$wh" \
     --argjson t "$tolerance" '
    ((.rect.x + .rect.width / 2) - ($wx + $ww / 2) | fabs) <= $t and
    ((.rect.y + .rect.height / 2) - ($wy + $wh / 2) | fabs) <= $t' <<<"$view" >/dev/null \
    || { echo "view $(jq -c .rect <<<"$view") not centred in $wx,$wy ${ww}x$wh"; return 1; }
}

# Mean luminance of one output, 0..1.
e2e_luminance() { # <output> [file]
  local file="${2:-$e2e_dir/frames/lum-$1-$RANDOM.png}"
  grim -o "$1" "$file" && magick "$file" -colorspace gray -format '%[fx:mean]' info:
}

# Save a still of every output into frames/, for the reviewer.
e2e_still() { # <label>
  local o
  for o in HEADLESS-1 HEADLESS-2; do grim -o "$o" "$e2e_dir/frames/$1-$o.png"; done
}

# Pass when two images differ by more than <fraction> of their pixels.
e2e_images_differ() { # <a.png> <b.png> [fraction]
  local diff
  diff=$(magick compare -metric AE -fuzz 5% "$1" "$2" null: 2>&1 | cut -d' ' -f1)
  awk -v d="$diff" -v f="${3:-0.05}" 'BEGIN { exit !(d / (1920 * 1080) > f) }' \
    || { echo "only $diff pixels differ"; return 1; }
}

# ---- clipboard ------------------------------------------------------------------

e2e_clipboard_types() { wl-paste --list-types 2>/dev/null; }
e2e_clipboard_has_png() { e2e_clipboard_types | grep -qx 'image/png'; }

# Size of the PNG on the clipboard as "WxH".
e2e_clipboard_png_size() {
  wl-paste --type image/png 2>/dev/null >"$e2e_dir/clipboard.png" || return 1
  magick identify -format '%wx%h' "$e2e_dir/clipboard.png"
}

e2e_clipboard_clear() { wl-copy --clear 2>/dev/null || true; }

# ---- PNG files --------------------------------------------------------------

e2e_png_count() { find "$1" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l; }
e2e_png_size() { magick identify -format '%wx%h' "$1"; }
# omasnap's logical-size text chunk, for example "1280x720".
e2e_png_logical_size() {
  magick identify -verbose "$1" | sed -n 's/^ *Omasnap logical size: *//p' | head -n1
}

# ---- processes and input --------------------------------------------------------

# Start omasnap in the background with the given arguments. Sets e2e_pid.
e2e_omasnap() {
  "$OMASNAP_BIN" "$@" >>"$e2e_dir/clients.log" 2>&1 &
  e2e_pid=$!
  e2e_tracked="$e2e_tracked $e2e_pid"
}

# Start any client in the background. Sets e2e_pid.
e2e_spawn() {
  "$@" >>"$e2e_dir/clients.log" 2>&1 &
  e2e_pid=$!
  e2e_tracked="$e2e_tracked $e2e_pid"
}

e2e_stop() { # <pid>
  kill "$1" 2>/dev/null
  timeout 5 tail --pid="$1" -f /dev/null 2>/dev/null
  kill -9 "$1" 2>/dev/null
  wait "$1" 2>/dev/null
  e2e_tracked="${e2e_tracked// $1/}"
}

# PIDs of every process started inside this scenario (children included),
# found by the private XDG_RUNTIME_DIR in their environment.
e2e_own_pids() {
  local environ pid
  for environ in /proc/[0-9]*/environ; do
    pid="${environ#/proc/}"; pid="${pid%/environ}"
    [[ "$pid" == "$$" || "$pid" == "$e2e_sway_pid" ]] && continue
    tr '\0' '\n' <"$environ" 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" && echo "$pid"
  done
}

# Command lines of this scenario's omasnap processes, runtime folder elided.
e2e_omasnap_argv() {
  local pid
  for pid in $(e2e_own_pids); do
    [[ "$(readlink "/proc/$pid/exe" 2>/dev/null)" == "$(readlink -f "$OMASNAP_BIN")" ]] || continue
    tr '\0' ' ' <"/proc/$pid/cmdline" | sed "s#$XDG_RUNTIME_DIR#\$XDG_RUNTIME_DIR#g"; echo
  done
}

# Virtual pointer steps in layout coordinates, see tests/e2e/vptr.c.
e2e_pointer() { "$OMASNAP_E2E_VPTR" "$E2E_LAYOUT_W" "$E2E_LAYOUT_H" "$@"; }

# Type keys with wtype until <condition> holds. A new wtype virtual keyboard
# can lose its first events to a layer-shell surface in headless Sway, so a
# single press is not reliable. Retry only keys that are safe to repeat.
e2e_keys_until() { # <attempts> <wait-seconds> <condition> -- <wtype args>...
  local attempts="$1" wait="$2" condition="$3"; shift 4
  local attempt
  for attempt in $(seq "$attempts"); do
    wtype -d 60 "$@" 2>>"$e2e_dir/clients.log"
    if e2e_until "$wait" eval "$condition"; then
      e2e_log "keys '$*' took effect on attempt $attempt"
      return 0
    fi
  done
  return 1
}

# ---- recording ----------------------------------------------------------------

e2e_record_start() {
  e2e_recorders=""
  [[ "$E2E_RECORD" == 1 ]] || return 0
  if ! command -v wf-recorder >/dev/null || ! command -v ffmpeg >/dev/null; then
    e2e_log "recording skipped: wf-recorder or ffmpeg missing"
    return 0
  fi
  local o
  for o in HEADLESS-1 HEADLESS-2; do
    wf-recorder --output "$o" --file "$e2e_dir/rec-$o.mkv" --codec libx264 \
      --framerate 15 --codec-param preset=veryfast --codec-param crf=30 \
      >>"$e2e_dir/recorder.log" 2>&1 </dev/null &
    e2e_recorders="$e2e_recorders $!"
  done
  sleep 0.5
}

# Stop the recorders and join both outputs side by side into video.mp4
# (2560x720: each 1920x1080 output scaled to 1280x720).
e2e_record_stop() {
  [[ -n "$e2e_recorders" ]] || return 0
  local pid
  for pid in $e2e_recorders; do kill -INT "$pid" 2>/dev/null; done
  # No `wait` here: in an EXIT trap, bash can block on it after the
  # recorder has exited. tail --pid returns once the process is gone.
  for pid in $e2e_recorders; do timeout 10 tail --pid="$pid" -f /dev/null; done
  e2e_recorders=""
  local a="$e2e_dir/rec-HEADLESS-1.mkv" b="$e2e_dir/rec-HEADLESS-2.mkv"
  if [[ -s "$a" && -s "$b" ]] && ffmpeg -nostdin -loglevel error -y -i "$a" -i "$b" -filter_complex \
      '[0:v]fps=15,scale=1280:720,setpts=PTS-STARTPTS[l];[1:v]fps=15,scale=1280:720,setpts=PTS-STARTPTS[r];[l][r]hstack=inputs=2,format=yuv420p[v]' \
      -map '[v]' -c:v libx264 -preset veryfast -crf 28 -movflags +faststart \
      "$e2e_dir/video.mp4" 2>>"$e2e_dir/recorder.log"; then
    rm -f "$a" "$b"
  else
    e2e_log "could not join recordings; per-output files kept"
  fi
}

# ---- scenario lifecycle -------------------------------------------------------

# Write the scenario's Sway config. The bar shows caption.txt, which is how
# each step's name gets into the recording.
e2e_write_sway_config() {
  cat >"$e2e_dir/caption.sh" <<EOF
#!/bin/sh
while :; do printf '%s\n' "\$(cat '$e2e_dir/caption.txt' 2>/dev/null)"; sleep 0.25; done
EOF
  chmod +x "$e2e_dir/caption.sh"
  cat >"$e2e_dir/sway.conf" <<EOF
output HEADLESS-1 resolution 1920x1080 position 0 0 scale 1.5
output * bg #336699 solid_color
seat seat0 fallback true
seat * xcursor_theme Adwaita 32
focus_follows_mouse no
font pango:DejaVu Sans 11
bar {
  position top
  font pango:DejaVu Sans Bold 12
  status_command $e2e_dir/caption.sh
  colors {
    background #1d2021
    statusline #fabd2f
  }
}
EOF
  if command -v mako >/dev/null && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    printf 'exec mako --default-timeout 0\n' >>"$e2e_dir/sway.conf"
  fi
}

e2e_begin() { # <scenario-name> <title>
  e2e_name="$1"
  e2e_dir="$E2E_OUT/$1"
  rm -rf "$e2e_dir"
  mkdir -p "$e2e_dir/cfg/omasnap" "$e2e_dir/shots" "$e2e_dir/recent" \
    "$e2e_dir/state" "$e2e_dir/home" "$e2e_dir/frames"
  : >"$e2e_dir/results.tsv"
  : >"$e2e_dir/timeline.txt"
  printf '%s\n' "$2" >"$e2e_dir/title.txt"
  e2e_start_ns=$(date +%s%N)
  e2e_set_config "[output]
directory = $e2e_dir/shots"

  unset SWAYSOCK WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
  XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omasnap-e2e.XXXXXX")"
  chmod 700 "$XDG_RUNTIME_DIR"
  export XDG_RUNTIME_DIR
  export HOME="$e2e_dir/home" XDG_CONFIG_HOME="$e2e_dir/cfg" XDG_STATE_HOME="$e2e_dir/state"
  export OMASNAP_RECENT_DIR="$e2e_dir/recent"
  export QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1
  export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
  export XCURSOR_THEME=Adwaita XCURSOR_SIZE=32

  e2e_write_sway_config
  printf '%s\n' "$2" >"$e2e_dir/caption.txt"
  sway -c "$e2e_dir/sway.conf" >"$e2e_dir/sway.log" 2>&1 &
  e2e_sway_pid=$!
  trap e2e_cleanup EXIT

  local sock="" _
  for _ in $(seq 100); do
    sock=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1)
    [[ -n "$sock" ]] && break
    sleep 0.1
  done
  if [[ -z "$sock" ]]; then
    e2e_log "Sway did not start; see sway.log"
    e2e_fails=$((e2e_fails + 1))
    e2e_record_result FAIL "headless Sway starts"
    exit 1
  fi
  export SWAYSOCK="$sock"
  WAYLAND_DISPLAY="$(cd "$XDG_RUNTIME_DIR" && ls wayland-* | grep -v lock | head -n1)"
  export WAYLAND_DISPLAY
  swaymsg create_output >/dev/null
  swaymsg 'output HEADLESS-2 resolution 1920x1080 position 1280 0 scale 1' >/dev/null
  swaymsg 'focus output HEADLESS-1' >/dev/null
  e2e_until 5 bash -c '[[ $(swaymsg -r -t get_outputs | jq length) == 2 ]]'
  # Keep one virtual pointer for the whole scenario (see hold in vptr.c).
  # It parks the cursor in the middle of HEADLESS-1.
  e2e_pointer move 640 400 hold >>"$e2e_dir/clients.log" 2>&1 &
  e2e_tracked="$e2e_tracked $!"
  sleep 0.5
  e2e_record_start
  e2e_caption "$2"
  e2e_pause
}

# Replace omasnap.conf for the following launches.
e2e_set_config() { printf '%s\n' "$1" >"$e2e_dir/cfg/omasnap/omasnap.conf"; }

e2e_end() {
  # Every scenario also checks that no Hyprland or Omarchy tool was called.
  e2e_check "no hyprctl or omarchy- tool in client logs" \
    bash -c "! grep -i 'hyprctl\|omarchy-' '$e2e_dir/clients.log'"
  local verdict="PASS"
  (( e2e_fails > 0 )) && verdict="FAIL"
  e2e_caption "$verdict: $e2e_name ($((e2e_checks - e2e_fails - e2e_xfails)) passed, $e2e_fails failed, $e2e_xfails known gaps)"
  e2e_pause 1.5
  printf '%s\n' "$verdict" >"$e2e_dir/verdict.txt"
  exit $(( e2e_fails > 0 ? 1 : 0 ))
}

e2e_cleanup() {
  local pid
  for pid in $e2e_tracked; do kill "$pid" 2>/dev/null; done
  for pid in $(e2e_own_pids); do
    [[ " $e2e_recorders " == *" $pid "* ]] || kill "$pid" 2>/dev/null
  done
  sleep 0.5
  e2e_record_stop
  swaymsg exit >/dev/null 2>&1
  timeout 5 tail --pid="$e2e_sway_pid" -f /dev/null
  kill "$e2e_sway_pid" 2>/dev/null
  for pid in $(e2e_own_pids); do kill -9 "$pid" 2>/dev/null; done
  rm -rf "$XDG_RUNTIME_DIR"
}

# ---- fixtures -------------------------------------------------------------------

# A 1600x900 test card with large text, so editors and pins show something a
# reviewer can recognise in the video.
e2e_fixture() { # <path>
  # ImageMagick has no default font in the image, so name a file.
  local font
  font=$(fc-match -f '%{file}' 'DejaVu Sans:bold' 2>/dev/null)
  magick -size 1600x900 gradient:'#f4a261-#2a9d8f' -font "$font" \
    -fill '#264653' -draw 'rectangle 80,80 1520,820' \
    -fill white -pointsize 110 -gravity center -annotate +0-120 'OMASNAP E2E' \
    -pointsize 60 -annotate +0+60 'test card 4217' "$1"
}

# Pass when more than <fraction> (default 2%) of <output>'s pixels differ
# from the baseline still <png>. A layer-shell overlay has no entry in the
# Sway tree, so pixels are the only evidence. The capture overlay shows the
# frozen screen plus its chrome (shortcut card, size label), so only a few
# percent of the pixels change.
e2e_output_changed() { # <output> <baseline.png> [fraction]
  grim -o "$1" "$e2e_dir/frames/now-$1.png" && e2e_images_differ "$2" "$e2e_dir/frames/now-$1.png" "${3:-0.02}"
}

# Pass when <output> shows the same pixels twice, <seconds> apart.
e2e_output_still() { # <output> [seconds]
  grim -o "$1" "$e2e_dir/frames/still-a.png"; sleep "${2:-1.5}"
  grim -o "$1" "$e2e_dir/frames/still-b.png"
  # Any changed pixel counts: a scrolled terminal changes well under 1%.
  ! e2e_images_differ "$e2e_dir/frames/still-a.png" "$e2e_dir/frames/still-b.png" 0 >/dev/null
}
