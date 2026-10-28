#!/usr/bin/env bash
# Run the headless Sway e2e scenarios: tests/e2e/run.sh [scenario ...]
#
# With no names, every tests/e2e/scenarios/*.sh runs in order. A name may omit
# the number prefix and the .sh suffix. Each scenario runs in its own private
# headless Sway on its own D-Bus session bus and writes E2E_OUT/<scenario>/:
# results.tsv, timeline.txt, steps.log, clients.log, sway.log, frames/ and,
# when recording, video.mp4. E2E_OUT/summary.md lists every scenario.
#
# Environment: OMASNAP_BIN, OMASNAP_E2E_VPTR, E2E_OUT, E2E_RECORD, E2E_PACE
# (see lib.sh). `make e2e` sets the first three.
set -uo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${OMASNAP_BIN:?set OMASNAP_BIN to the omasnap binary}"
: "${OMASNAP_E2E_VPTR:?set OMASNAP_E2E_VPTR to the omasnap-e2e-vptr helper}"
: "${E2E_OUT:?set E2E_OUT to an output folder}"
OMASNAP_BIN="$(readlink -f "$OMASNAP_BIN")"
OMASNAP_E2E_VPTR="$(readlink -f "$OMASNAP_E2E_VPTR")"
mkdir -p "$E2E_OUT"
E2E_OUT="$(readlink -f "$E2E_OUT")"
export OMASNAP_BIN OMASNAP_E2E_VPTR E2E_OUT

missing=""
for tool in sway swaymsg grim wtype jq magick wl-copy wl-paste dbus-run-session; do
  command -v "$tool" >/dev/null || missing="$missing $tool"
done
if [[ -n "$missing" ]]; then
  echo "e2e: missing tools:$missing (use make docker-e2e)" >&2
  exit 2
fi

scenarios=()
if (( $# == 0 )); then
  scenarios=("$here"/scenarios/*.sh)
else
  for name in "$@"; do
    match=$(ls "$here"/scenarios/*.sh | grep -E "/([0-9]+-)?${name%.sh}\.sh$" | head -n1)
    [[ -n "$match" ]] || { echo "e2e: no scenario $name" >&2; exit 2; }
    scenarios+=("$match")
  done
fi

summary="$E2E_OUT/summary.md"
{
  echo "# Omasnap e2e results"
  echo
  echo "$(QT_QPA_PLATFORM=offscreen "$OMASNAP_BIN" --version 2>/dev/null), $(sway --version), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "| Scenario | Verdict | Pass | Fail | Known gaps | Video |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >"$summary"

failed=0
for scenario in "${scenarios[@]}"; do
  name="$(basename "$scenario" .sh)"
  echo "e2e: $name" >&2
  # A private bus per scenario keeps notify-send off any live desktop.
  timeout --kill-after=10 300 env -u DBUS_SESSION_BUS_ADDRESS \
    dbus-run-session -- bash "$scenario"
  status=$?
  dir="$E2E_OUT/$name"
  verdict="$(cat "$dir/verdict.txt" 2>/dev/null || echo "FAIL (exit $status)")"
  (( status != 0 )) && [[ "$verdict" == PASS ]] && verdict="FAIL (exit $status)"
  [[ "$verdict" == PASS ]] || failed=$((failed + 1))
  pass=$(grep -c '^PASS' "$dir/results.tsv" 2>/dev/null)
  fail=$(grep -c '^FAIL' "$dir/results.tsv" 2>/dev/null)
  xfail=$(grep -c '^XFAIL' "$dir/results.tsv" 2>/dev/null)
  video="-"
  [[ -s "$dir/video.mp4" ]] && video="[$name/video.mp4]($name/video.mp4)"
  echo "| $name | $verdict | ${pass:-0} | ${fail:-0} | ${xfail:-0} | $video |" >>"$summary"
done

{
  echo
  echo "Each scenario folder holds results.tsv (one line per check), timeline.txt"
  echo "(check times as offsets into the video), steps.log, client and Sway logs,"
  echo "and stills in frames/."
} >>"$summary"

cat "$summary"
(( failed == 0 ))
