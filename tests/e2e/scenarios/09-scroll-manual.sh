#!/usr/bin/env bash
# Manual scroll capture: the test scrolls the page, omasnap grabs and stitches.
E2E_SCROLL_MODE=manual
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
e2e_begin 09-scroll-manual "Scroll capture, Manual: wheel the page, Done stitches"
source "$(dirname -- "${BASH_SOURCE[0]}")/../scroll-capture.sh"
