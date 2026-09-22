# Omasnap — Agent Guide

Omasnap is a super fast, native Wayland screenshot and annotation overlay.
This fork is built for Sway on vanilla Arch Linux. It captures region,
window, or full monitor (plus a scrolling-region mode that stitches a taller
page into one image), then copies it and opens a floating compositor preview.
The preview fades after 10 seconds of idle time unless explicitly kept with its
pin button or Ctrl+P. Hovering and in-progress actions pause its countdown.
It opens an annotation editor on demand, with vector layers
(arrows, lines, freehand, highlighter, rectangles, ellipses, numbered
markers, text, OCR). Finished captures go to clipboard,
`~/Pictures/Screenshots`, or a floating capture pinned across workspaces.

## Project principles

Each of these has a longer writeup under `docs/` — read it before making a
change that touches the principle, not just this summary.

- **A specialized tool, not a general app.** Omasnap does one job — capture,
  annotate, output — and does it fast. It is not a drawing program, not a
  file manager, not a general Wayland utility. A feature that isn't in
  service of "screenshot, mark it up, send it somewhere" doesn't belong
  here, however useful it might be on its own.
- **The main thread never blocks.** Capture, paint, and input handling are
  the UI thread's whole job. Disk I/O on a full-resolution image, spawning
  a process, PNG encoding — all of it runs on a worker via
  `QtConcurrent`/`QFutureWatcher`, never inline. See
  [docs/threading.md](docs/threading.md).
- **Every operation is undoable.** The operation log is the source of
  truth; the visible image is rebuilt from it. Rendering for editing is a
  pure, repeatable function of that log — nothing is baked into the working
  image as you draw. Fresh captures copy and show a timed preview by default;
  during editing, output is applied only on **Copy**, **Save**, or both
  (or an explicit pin or a return to its preview),
  which is the one moment a flattened image is produced. Redaction is the
  deliberate, documented exception: it must actually destroy pixels at
  render time so nothing recoverable leaks into an export, while remaining
  a normal, undoable log entry until you export. See
  [docs/editing-model.md](docs/editing-model.md).
- **Minimally configurable — pre-configured to be right.**
  No settings UI, no wizards, no onboarding. The defaults are the product;
  a config key is a narrow escape hatch for a real divergent need (where to
  save, what to name it, preset colors), never a general mechanism. Adding
  a new key needs the same justification the existing ones had, not "this
  would be nice to expose."
- **Speed first.** Instant capture, annotate, copy. No startup bloat.
- **Wayland only, Sway only.** Output/window discovery, pin placement, and
  the windowed editor use Sway IPC through `swaymsg`
  (`src/capture.cpp`, `src/sway-ipc.cpp`). Do not reintroduce `hyprctl`,
  Hyprland Lua rules, or Omarchy tools on any path. Code that also runs on
  another wlroots compositor because it stands on a real Wayland protocol
  is a fine accident, not a target. No X11, no macOS/Windows. See
  [docs/platform-scope.md](docs/platform-scope.md).
- **Lean, learned dependencies.** The dependency set is Qt6 + LayerShellQt +
  wayland-client, plus shelling out to a few existing Arch/Sway tools
  (`swaymsg`, `wl-copy`/`wl-paste`, `tesseract`, `notify-send`)
  instead of linking their equivalents in-process. Know this list before
  proposing an addition to it. See [docs/dependencies.md](docs/dependencies.md).
- **Single small binary.** Everything (capture, editor, pin mode, scroll
  capture) runs from the one `omasnap` executable. Every new dependency or
  vendored asset is weight every install carries.
- **No backwards compatibility.** Break keybindings, CLI flags, file
  formats, or internals whenever it keeps the code simpler or the tool
  faster. Do not add compatibility shims, deprecation aliases, or migration
  code.
- **Minimal aesthetics.** Freedesktop `notify-send` notifications,
  `OMASNAP_OCR_LANGS`, then the legacy `OMARCHY_OCR_LANGS`, for OCR languages,
  minimal vector-drawn icons (no icon-theme dependency), the bundled Neucha
  font. Chrome text uses `chromeFont()`/`chromeMonoFont()`
  (`src/overlay-chrome.cpp`), pinned in code, and `main()` installs
  `chromeDefaultFont()` as the application font; external desktop platform
  themes are deliberately bypassed at startup in favour of Qt's built-in
  `generic` theme (see [docs/dependencies.md](docs/dependencies.md)). Chrome
  must use the pinned fonts and explicit colours; do not derive chrome from
  `QFontDatabase::systemFont`, `QStyle`, or `palette()`.

## Repository layout

| Path | Purpose |
|---|---|
| `src/main.cpp` | CLI parsing, single-instance lock, mode dispatch |
| `src/instance-lock.cpp/.hpp` | Single-instance handover: cancel a running overlay, or stop it and take over for `--file` |
| `src/capture.cpp/.hpp` | Capture, render pipeline, output (clipboard/save/notify), source+JSON operation-log persistence, config loading glue |
| `src/editor.cpp/.hpp` | Annotation editor: tools, vector layers, operation-log undo/redo, the select↔edit phase machine, export |
| `src/overlay-chrome.cpp/.hpp` | Shared chrome every overlay wears: the capture-kind tab strip, hotkey legend, status pill |
| `src/scroll-capture.cpp/.hpp` | The scroll-capture panel: region-live page, manual/auto mode, grips, stitched result |
| `src/scroll-inject.cpp/.hpp` | Auto-scroll wheel injection (uinput / `zwlr_virtual_pointer_v1`) |
| `src/auto-capture.cpp/.hpp`, `src/stitch.cpp/.hpp` | Pure, offline-testable frame classification and stitching |
| `src/stitch-replay.cpp` | Standalone tool: replay a dumped frame directory through the stitcher with no compositor |
| `src/surface-capture.cpp` | In-process output capture via `ext-image-copy-capture` |
| `src/cut.cpp/.hpp` | Cut-band tool: remove a strip and collapse the gap |
| `src/recent-snaps.cpp/.hpp` | The recents shelf: shelving/reopening working documents |
| `src/output-config.cpp/.hpp`, `src/palette-config.cpp/.hpp` | The optional `omasnap.conf` INI: output destination/filename, color presets |
| `src/pin.cpp/.hpp`, `src/pin-file.cpp/.hpp`, `src/pin-layout.cpp/.hpp` | Floating pinned captures, their files, and compositor placement |
| `src/sway-ipc.cpp/.hpp` | Bounded `swaymsg` runner, command-reply checks, and the flat Sway view list used by pins and the windowed editor |
| `src/pin-expiry.cpp/.hpp` | Preview countdown, interaction pauses, and fade |
| `src/icons.cpp/.hpp` | Vector icon renderer for toolbar and pin controls |
| `src/cli-path.cpp/.hpp` | Command-line image target resolution |
| `src/eyedropper.cpp/.hpp` | Display-to-source color sampling |
| `tests/*-smoke.cpp/.hpp` | Headless Qt Test coverage: offscreen region clicks, async capture, single-instance handover, stitching fixtures |
| `docs/` | Longer writeups of the principles above — read before changing behavior they cover |
| `install-arch` | Arch/Sway dependency-checking installer (installs to `~/.local`) |
| `CMakeLists.txt` | Build definition; **the version lives here** (`project(omasnap VERSION ...)`) |

## Build and verify

```bash
make check
```

`make check` configures and builds the project, runs the complete headless
offscreen Qt smoke suite (including simulated region clicks and asynchronous
capture), runs `clang-tidy`, and runs `clazy-standalone`/`qmllint` when those
tools and source types are available. Use `make build` for a build-only pass,
`make smoke` for the behavioral smoke suite, and `make install` to install to
`~/.local`.

Always run `make check` after behavioral changes. CI
(`.github/workflows/build-linux.yml`) runs the same build and smoke on every
push and PR.

Dependencies (Arch): `base-devel cmake ninja pkgconf qt6-base layer-shell-qt
wayland wayland-protocols sway wl-clipboard libnotify tesseract
tesseract-data-eng`. See
[docs/dependencies.md](docs/dependencies.md) before adding to this list.

## Release process

1. Bump `project(omasnap VERSION ...)` in `CMakeLists.txt`.
   Move the `Unreleased` entries in `CHANGELOG.md` into that version's
   section, add its comparison link, and start a fresh `Unreleased` section.
   Update the Unreleased comparison link to compare the new tag with `main`.
2. Build and run the smoke test (above).
3. Commit, tag `v<version>`, push main and the tag. The GitHub workflow
   attaches the build artifact to the release automatically.
   Copy the new changelog section into the GitHub release notes so users
   can read the changes alongside the download.

Fork syncs rebuild the Sway line on an upstream tag by adapting behaviour,
not by replaying old patches.

See `README.md` for user-facing features, keybindings, and install
instructions — keep it in sync when behavior changes.
