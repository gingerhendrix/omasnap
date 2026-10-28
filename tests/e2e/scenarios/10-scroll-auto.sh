#!/usr/bin/env bash
# Auto scroll capture: omasnap scrolls the page through the wlr virtual
# pointer, then stitches.
E2E_SCROLL_MODE=auto
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 10-scroll-auto "Scroll capture, Auto: omasnap scrolls through the virtual pointer"
source "$(dirname -- "${BASH_SOURCE[0]}")/../scroll-capture.sh"
