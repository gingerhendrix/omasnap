#!/usr/bin/env bash
# Notifications go through notify-send to the session's notification daemon
# (mako here). A plain saved capture announces itself for 4.5 s. --notify
# gives a 7 s notification with the image hint, as v1.24.0 times it, and
# Edit and Open actions. Invoking Edit through mako reopens the capture in
# the editor. No omarchy-notification-send is involved.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 07-notifications "Notifications: notify-send to a real daemon, --notify timing"
monitor="$e2e_dir/notify-calls.txt"
dbus-monitor --session "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" \
  >"$monitor" 2>&1 &
e2e_tracked="$e2e_tracked $!"
e2e_check "mako owns org.freedesktop.Notifications" \
  e2e_until 5 busctl --user status org.freedesktop.Notifications
sleep 0.5

# Each Notify call in the monitor log as one line, so checks can grep a call.
notify_calls() { awk '/member=Notify/ { if (call) print call; call = "" } { call = call " " $0 } END { if (call) print call }' "$monitor" | grep 'member=Notify'; }
notify_count() { notify_calls | wc -l; }
last_call_has() { notify_calls | tail -n1 | grep -qF -- "$1"; }

swaymsg 'focus output HEADLESS-1' >/dev/null
e2e_caption "omasnap --capture-fullscreen --save"
"$OMASNAP_BIN" --capture-fullscreen --save >>"$e2e_dir/clients.log" 2>&1
e2e_wait "one Notify call" 5 bash -c "[[ \$(grep -c member=Notify '$monitor') == 1 ]]"
e2e_check "app name is omasnap" last_call_has 'string "omasnap"'
e2e_check "plain save notification expires after 4500 ms" last_call_has 'int32 4500'
e2e_check "a click on the plain save notification edits it (default action)" \
  last_call_has 'string "default"'
e2e_pause 2
e2e_still notify-save

e2e_caption "omasnap --capture-fullscreen --save --notify"
"$OMASNAP_BIN" --capture-fullscreen --save --notify >>"$e2e_dir/clients.log" 2>&1
e2e_wait "a second Notify call" 5 bash -c "[[ \$(grep -c member=Notify '$monitor') == 2 ]]"
shot=$(ls -t "$e2e_dir"/shots/*.png | head -n1)
e2e_check "--notify notification expires after 7000 ms" last_call_has 'int32 7000'
e2e_check "--notify carries the image-path hint for the saved PNG" last_call_has "$shot"
e2e_check "--notify offers an Edit action" last_call_has 'string "edit"'
e2e_check "--notify offers an Open action" last_call_has 'string "open"'
e2e_check "mako shows two Omasnap notifications" bash -c "[[ \$(makoctl list -j 2>/dev/null | jq '[.. | objects | select(.summary? == \"Omasnap\" or .summary?.data? == \"Omasnap\")] | length') -ge 2 ]] || [[ \$(makoctl list 2>/dev/null | grep -c Omasnap) -ge 2 ]]"
e2e_pause 2
e2e_still notify-notify

# makoctl invoke acts on the newest notification, the --notify one. The
# action waiter then runs omasnap --recent <id> -- <saved PNG>.
e2e_caption "makoctl invoke edit on the --notify notification"
base="$e2e_dir/frames/before-invoke-HEADLESS-1.png"; grim -o HEADLESS-1 "$base"
makoctl invoke edit >>"$e2e_dir/clients.log" 2>&1
edit_started() { e2e_omasnap_argv | grep -qF -- "--recent"; }
e2e_wait "Edit starts omasnap --recent with the saved PNG" 5 edit_started
e2e_omasnap_argv >"$e2e_dir/argv-after-invoke.txt"
e2e_check "the editor gets the saved path as one word after --" \
  grep -qF -- "-- $shot" "$e2e_dir/argv-after-invoke.txt"
e2e_wait "the editor overlay appears on HEADLESS-1" 10 e2e_output_changed HEADLESS-1 "$base"
e2e_pause 2
e2e_still notify-edit

e2e_end
