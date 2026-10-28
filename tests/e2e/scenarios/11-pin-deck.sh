#!/usr/bin/env bash
# Three pins form a deck in the lower right of HEADLESS-1, each card 12 px
# above the one in front. Hovering the deck fans the cards out, moving the
# pointer away folds them back, and dragging a card body moves that pin out
# of the deck, which then closes the gap.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 11-pin-deck "Pin deck: fan out, fold back, drag a pin away"
card="$e2e_dir/card.png"; e2e_fixture "$card"
pin='(.name | startswith("omasnap-pin"))'

pin_count() { e2e_views | jq "[.[] | select($pin)] | length"; }
# Pin rects, top to bottom.
pin_rects() { e2e_views | jq -c "[.[] | select($pin) | .rect] | sort_by(.y)"; }
# Vertical steps between neighbouring pins of the deck (x > 640, the right
# half of HEADLESS-1), top to bottom, as "a b".
deck_steps() {
  pin_rects | jq -r '[.[] | select(.x > 640)] | [range(1; length) as $i | .[$i].y - .[$i-1].y] | map(tostring) | join(" ")'
}
deck_is() { e2e_eq "$1" "$(deck_steps)"; }
# Every step is at least one card tall: no card covers another.
deck_fanned() {
  pin_rects | jq -e '[.[] | select(.x > 640)] | length == 3 and
    ([range(1; length) as $i | .[$i].y - .[$i-1].y >= .[$i-1].height] | all)' >/dev/null
}

swaymsg 'focus output HEADLESS-1' >/dev/null
e2e_caption "pin the card three times"
pids=""
for n in 1 2 3; do
  e2e_omasnap --pin "$card"; pids="$pids $e2e_pid"
  e2e_wait "pin $n maps" 10 bash -c "[[ \$(swaymsg -r -t get_tree | jq '[recurse(.nodes[]?, .floating_nodes[]?) | select(.name? // \"\" | startswith(\"omasnap-pin\"))] | length') == $n ]]"
  sleep 0.5
done
e2e_wait "the idle deck stacks 12 px apart" 5 deck_is "12 12"
pin_rects >"$e2e_dir/rects-idle.json"
e2e_pause 2
e2e_still deck-idle

# The front card is the lowest one.
read -r fx fy fw fh < <(jq -r 'last | "\(.x) \(.y) \(.width) \(.height)"' "$e2e_dir/rects-idle.json")
e2e_caption "hover the front card: the deck fans out"
# Each e2e_pointer call is a new pointer that starts with a move from where
# the previous one left the cursor.
e2e_pointer move 640 400 glide "$((fx + fw / 2))" "$((fy + fh - 20))" 600
e2e_wait "hovering fans the deck out, no card covers another" 5 deck_fanned
pin_rects >"$e2e_dir/rects-fanned.json"
e2e_check "the front card stays anchored while fanned" e2e_eq "$fy" \
  "$(jq 'last | .y' "$e2e_dir/rects-fanned.json")"
e2e_pause 2
e2e_still deck-fanned

e2e_caption "move the pointer away: the deck folds back"
e2e_pointer move "$((fx + fw / 2))" "$((fy + fh - 20))" glide 300 300 600
e2e_wait "the deck folds back to the 12 px lip" 5 deck_is "12 12"
e2e_pause 2
e2e_still deck-folded

# Press on the card body, below the action row and right of the corner
# controls (pinControlRect), so the press starts a compositor move.
read -r fx fy fw fh < <(pin_rects | jq -r 'last | "\(.x) \(.y) \(.width) \(.height)"')
e2e_caption "drag the front card to the upper left"
e2e_pointer move 300 300 glide "$((fx + 60))" "$((fy + fh - 14))" 500 sleep 300 \
  down glide 300 200 900 sleep 400 up
moved() { pin_rects | jq -e '[.[] | select(.x < 640)] | length == 1' >/dev/null; }
e2e_wait "the dragged pin leaves the deck" 5 moved
e2e_wait "the two remaining cards close the gap, 12 px apart" 5 deck_is "12"
sleep 1.5
dropped() { pin_rects | jq -e '[.[] | select(.x < 400 and .y < 400)] | length == 1' >/dev/null; }
e2e_check "the dragged pin stays where it was dropped" dropped
e2e_check "every pin is still floating and sticky" e2e_eq 3 \
  "$(e2e_views | jq "[.[] | select($pin and .type == \"floating_con\" and .sticky)] | length")"
e2e_check "three pins remain" e2e_eq 3 "$(pin_count)"
e2e_pause 2
e2e_still deck-after-drag

for p in $pids; do e2e_stop "$p"; done
e2e_end
