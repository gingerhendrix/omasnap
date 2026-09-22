/** @fileoverview Sway IPC helpers for pinned windows and the windowed editor:
 *  a bounded `swaymsg` runner, command-reply checks, and a flat view list
 *  parsed from `get_tree`. */
#pragma once

#include <QByteArray>
#include <QRect>
#include <QSize>
#include <QString>
#include <QStringList>
#include <QVector>

/// One Sway view (a container that holds a client window).
struct SwayWindow {
  /// Container id, as used by `[con_id=N]` criteria.
  qint64 id = 0;
  qint64 pid = 0;
  QString appId;
  QString title;
  /// Global logical bounds, decorations included.
  QRect rect;
  /// Client content size, decorations excluded (`window_rect`).
  QSize contentSize;
  bool floating = false;
  bool sticky = false;
  bool focused = false;
};

/// Runs `swaymsg -r` with the given arguments and a bounded wait. Returns
/// stdout, or empty when SWAYSOCK is unset, the process times out, or it
/// exits with an error. `ok` reports a clean exit.
[[nodiscard]] QByteArray swaymsgOutput(const QStringList &arguments,
                                       bool *ok = nullptr);

/// True when a command reply is a non-empty array in which every command
/// reports `"success": true`.
[[nodiscard]] bool swayCommandSucceeded(const QByteArray &reply);

/// Runs one Sway command list. True when every command succeeded.
[[nodiscard]] bool swayCommand(const QString &command);

/// Flattens `swaymsg -t get_tree -r` JSON into views, tiled and floating.
[[nodiscard]] QVector<SwayWindow> parseSwayWindows(const QByteArray &tree);

/// Reads the live Sway tree. Empty when Sway cannot be asked.
[[nodiscard]] QVector<SwayWindow> swayWindows();
