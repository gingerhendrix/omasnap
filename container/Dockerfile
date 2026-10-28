# Build and test image for the Sway fork. `make docker-check` uses it locally
# and .github/workflows/build-linux.yml uses it in CI, so both run the same
# packages. The build context is this folder only, so the image holds no
# source: the Makefile bind-mounts the checkout at /src.

# Build stage: what `make check` needs, the same list CI installed before.
FROM archlinux:latest AS build
RUN pacman -Syu --noconfirm --needed \
        base-devel cmake ninja pkgconf qt6-base layer-shell-qt \
        wayland wayland-protocols libdeflate wl-clipboard \
        tesseract tesseract-data-eng clang \
    && pacman -Scc --noconfirm
# The Makefile runs the container as the caller's uid, which has no passwd
# entry or home folder here. Give it a writable home.
ENV HOME=/tmp/home
RUN install -d -m 1777 /tmp/home
WORKDIR /src

# Headless compositor stage for compositor tests (`make e2e`): a private Sway
# with the pixman renderer and no input devices, plus the tools that drive and
# inspect it. wf-recorder and ffmpeg record each scenario for human review.
# mako and dbus give notify-send a real notification daemon. foot shows known
# text for OCR and a long scrollback for scroll capture, with software
# rendering. ttf-dejavu gives
# swaybar, foot and Qt a font. swaybg paints the background and
# adwaita-cursors makes the pointer visible in recordings.
FROM build AS e2e
RUN pacman -S --noconfirm --needed \
        sway swaybg grim wtype jq imagemagick file libnotify xdg-utils \
        wf-recorder ffmpeg mako dbus foot ttf-dejavu adwaita-cursors \
    && pacman -Scc --noconfirm \
    && setcap -r /usr/bin/sway
# Arch ships sway with cap_sys_nice=ep for realtime scheduling. Docker's
# default bounding set lacks CAP_SYS_NICE, so exec of a binary with that file
# capability fails with EPERM. A headless test does not need it.
ENV WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
# dbus-daemon needs a passwd entry for the caller's uid. The entrypoint adds
# one, so /etc/passwd is writable in this test-only stage.
COPY e2e-entrypoint /usr/local/bin/e2e-entrypoint
RUN chmod a+w /etc/passwd
ENTRYPOINT ["/usr/local/bin/e2e-entrypoint"]
