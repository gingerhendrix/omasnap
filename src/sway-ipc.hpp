/** @fileoverview Sway IPC helpers for pinned windows, the windowed editor, and
 *  the Save As chooser: a bounded `swaymsg` runner, command-reply checks,
 *  once-per-session rule registration, and a flat view list parsed from
 *  `get_tree`. */
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

/// Registers rules once per Sway instance. Sway rules have no names and
/// cannot be withdrawn, so each call would add another copy. A stamp file
/// `sway-<name>-<hash of SWAYSOCK>` in runtimeDirectory records that this
/// instance already has them, so a new Sway session registers again. A
/// `swaymsg reload` drops the rules and keeps the stamp; see
/// reregisterSwayRules. False
/// when SWAYSOCK or runtimeDirectory is empty, or when a command fails.
[[nodiscard]] bool registerSwayRulesOnce(const QString &name,
                                         const QStringList &commands,
                                         const QString &runtimeDirectory);

/// Registers rules again after the caller saw a view map without them.
/// `swaymsg reload` drops runtime rules but leaves the stamp, and no omasnap
/// process is resident to hear the reload event, so the first view that maps
/// after a reload is the only evidence. Removes the stamp, then behaves like
/// registerSwayRulesOnce. Each call adds one copy of the rules, so call it
/// only when a view proves the rules are missing.
[[nodiscard]] bool reregisterSwayRules(const QString &name,
                                       const QStringList &commands,
                                       const QString &runtimeDirectory);

/// The rule that floats and centers the Save As chooser. The overlay editor
/// is a layer surface, so the chooser has no xdg-shell parent and would tile.
[[nodiscard]] QStringList swaySaveAsRuleCommands();
