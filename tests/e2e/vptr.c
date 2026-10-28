/* omasnap-e2e-vptr: drive a wlr virtual pointer in the e2e compositor.
 *
 * Usage: omasnap-e2e-vptr <layout-width> <layout-height> <step>...
 *
 * Steps run in order on one virtual pointer, so a press, a move and a
 * release form one drag:
 *   move X Y        jump to layout coordinates X,Y
 *   glide X Y MS    move to X,Y in small steps over MS milliseconds
 *   down | up       press or release the left button
 *   click           press and release the left button
 *   wheel N         N discrete wheel notches, positive scrolls down
 *   sleep MS        wait MS milliseconds
 *   hold            keep the pointer until the process is killed
 *
 * The test compositor has no input devices (WLR_LIBINPUT_NO_DEVICES=1), so
 * this pointer is the only one and the cursor it moves shows in recordings.
 * The seat has pointer capability only while a virtual pointer exists, and a
 * client binds wl_pointer only when it sees that capability. lib.sh therefore
 * keeps one `hold` pointer alive for the whole scenario, so clients such as
 * foot have a wl_pointer before any wheel event arrives. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

#define BTN_LEFT 0x110

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct zwlr_virtual_pointer_v1 *pointer;
static unsigned width, height;
static double cur_x, cur_y;

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
  (void)data;
  (void)version;
  if (strcmp(interface, wl_seat_interface.name) == 0)
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
    manager = wl_registry_bind(registry, name,
                               &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void global_remove(void *data, struct wl_registry *registry,
                          uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener listener = {global, global_remove};

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void sleep_ms(long ms) { usleep((useconds_t)(ms * 1000)); }

static void flush(void) {
  zwlr_virtual_pointer_v1_frame(pointer);
  wl_display_roundtrip(display);
}

static void move_to(double x, double y) {
  cur_x = x;
  cur_y = y;
  zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), (uint32_t)x,
                                          (uint32_t)y, width, height);
  flush();
}

static void button(int pressed) {
  zwlr_virtual_pointer_v1_button(pointer, now_ms(), BTN_LEFT,
                                 pressed ? WL_POINTER_BUTTON_STATE_PRESSED
                                         : WL_POINTER_BUTTON_STATE_RELEASED);
  flush();
}

static void wheel(int notches) {
  const int step = notches > 0 ? 1 : -1;
  for (int i = 0; i != notches; i += step) {
    zwlr_virtual_pointer_v1_axis_discrete(pointer, now_ms(),
                                          WL_POINTER_AXIS_VERTICAL_SCROLL,
                                          wl_fixed_from_int(15 * step), step);
    zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
    flush();
    sleep_ms(40);
  }
}

static int need(int argc, int i, int count, const char *step) {
  if (i + count < argc)
    return 1;
  fprintf(stderr, "omasnap-e2e-vptr: %s needs %d argument(s)\n", step, count);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: omasnap-e2e-vptr width height step...\n");
    return 2;
  }
  width = (unsigned)atoi(argv[1]);
  height = (unsigned)atoi(argv[2]);
  display = wl_display_connect(NULL);
  if (!display) {
    fprintf(stderr, "omasnap-e2e-vptr: no Wayland display\n");
    return 1;
  }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &listener, NULL);
  wl_display_roundtrip(display);
  if (!seat || !manager) {
    fprintf(stderr, "omasnap-e2e-vptr: no seat or virtual pointer manager\n");
    return 1;
  }
  pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);

  for (int i = 3; i < argc; ++i) {
    const char *step = argv[i];
    if (strcmp(step, "move") == 0) {
      if (!need(argc, i, 2, step))
        return 2;
      const double x = atof(argv[i + 1]), y = atof(argv[i + 2]);
      /* A 1 px approach first: some clients only see enter after a move. */
      move_to(x > 0 ? x - 1 : x + 1, y);
      sleep_ms(50);
      move_to(x, y);
      i += 2;
    } else if (strcmp(step, "glide") == 0) {
      if (!need(argc, i, 3, step))
        return 2;
      const double x = atof(argv[i + 1]), y = atof(argv[i + 2]);
      const long ms = atol(argv[i + 3]);
      const int steps = ms / 16 > 1 ? (int)(ms / 16) : 1;
      const double x0 = cur_x, y0 = cur_y;
      for (int s = 1; s <= steps; ++s) {
        move_to(x0 + (x - x0) * s / steps, y0 + (y - y0) * s / steps);
        sleep_ms(16);
      }
      i += 3;
    } else if (strcmp(step, "down") == 0) {
      button(1);
    } else if (strcmp(step, "up") == 0) {
      button(0);
    } else if (strcmp(step, "click") == 0) {
      button(1);
      sleep_ms(80);
      button(0);
    } else if (strcmp(step, "wheel") == 0) {
      if (!need(argc, i, 1, step))
        return 2;
      wheel(atoi(argv[i + 1]));
      i += 1;
    } else if (strcmp(step, "sleep") == 0) {
      if (!need(argc, i, 1, step))
        return 2;
      sleep_ms(atol(argv[i + 1]));
      i += 1;
    } else if (strcmp(step, "hold") == 0) {
      while (wl_display_dispatch(display) != -1) {
      }
      return 0;
    } else {
      fprintf(stderr, "omasnap-e2e-vptr: unknown step %s\n", step);
      return 2;
    }
  }
  /* Keep the pointer until the compositor has handled the last event. */
  wl_display_roundtrip(display);
  sleep_ms(100);
  zwlr_virtual_pointer_v1_destroy(pointer);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
