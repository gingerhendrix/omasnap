/** @fileoverview Implements the Sway IPC helpers declared in sway-ipc.hpp. */
#include "sway-ipc.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>

namespace {

// Compositor IPC runs on workers. A missing or wedged swaymsg is bounded
// so it never stalls a pin or a visible editor.
constexpr int kSwaymsgTimeoutMs = 500;

QRect jsonRect(const QJsonObject &object) {
  return {object.value(QStringLiteral("x")).toInt(),
          object.value(QStringLiteral("y")).toInt(),
          object.value(QStringLiteral("width")).toInt(),
          object.value(QStringLiteral("height")).toInt()};
}

bool isView(const QJsonObject &node) {
  return !node.value(QStringLiteral("app_id")).toString().isEmpty() ||
         node.value(QStringLiteral("pid")).toInteger() > 0 ||
         !node.value(QStringLiteral("window_properties")).toObject().isEmpty();
}

void collectViews(const QJsonObject &node, bool floating,
                  QVector<SwayWindow> &windows) {
  if (isView(node)) {
    windows.push_back({node.value(QStringLiteral("id")).toInteger(),
                       node.value(QStringLiteral("pid")).toInteger(),
                       node.value(QStringLiteral("app_id")).toString(),
                       node.value(QStringLiteral("name")).toString(),
                       jsonRect(node.value(QStringLiteral("rect")).toObject()),
                       jsonRect(node.value(QStringLiteral("window_rect"))
                                    .toObject())
                           .size(),
                       floating,
                       node.value(QStringLiteral("sticky")).toBool(),
                       node.value(QStringLiteral("focused")).toBool()});
  }
  for (const QJsonValue &child : node.value(QStringLiteral("nodes")).toArray())
    collectViews(child.toObject(), floating, windows);
  for (const QJsonValue &child :
       node.value(QStringLiteral("floating_nodes")).toArray())
    collectViews(child.toObject(), true, windows);
}

} // namespace

QByteArray swaymsgOutput(const QStringList &arguments, bool *ok) {
  if (ok)
    *ok = false;
  if (qEnvironmentVariableIsEmpty("SWAYSOCK"))
    return {};
  QProcess process;
  process.start(QStringLiteral("swaymsg"),
                QStringList{QStringLiteral("-r")} + arguments);
  if (!process.waitForFinished(kSwaymsgTimeoutMs)) {
    process.kill();
    process.waitForFinished(kSwaymsgTimeoutMs);
    return {};
  }
  if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
    return {};
  if (ok)
    *ok = true;
  return process.readAllStandardOutput();
}

bool swayCommandSucceeded(const QByteArray &reply) {
  const QJsonArray results = QJsonDocument::fromJson(reply).array();
  if (results.isEmpty())
    return false;
  for (const QJsonValue &result : results) {
    if (!result.toObject().value(QStringLiteral("success")).toBool())
      return false;
  }
  return true;
}

bool swayCommand(const QString &command) {
  // `--` keeps a command that starts with criteria or a dash from being
  // read as a swaymsg option.
  return swayCommandSucceeded(
      swaymsgOutput({QStringLiteral("--"), command}));
}

QVector<SwayWindow> parseSwayWindows(const QByteArray &tree) {
  QVector<SwayWindow> windows;
  const QJsonDocument document = QJsonDocument::fromJson(tree);
  if (document.isObject())
    collectViews(document.object(), false, windows);
  return windows;
}

QVector<SwayWindow> swayWindows() {
  return parseSwayWindows(swaymsgOutput(
      {QStringLiteral("-t"), QStringLiteral("get_tree")}));
}
