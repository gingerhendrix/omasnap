/** @fileoverview Screenshot destination and filename pattern from the user's
 *  INI config. */
#include "output-config.hpp"

#include <QDir>
#include <QSettings>
#include <QStandardPaths>

OutputConfig loadOutputConfig(const QString &filePath) {
  OutputConfig config;
  QSettings settings(filePath, QSettings::IniFormat);
  QString directory =
      settings.value(QStringLiteral("output/directory")).toString().trimmed();
  if (directory == QStringLiteral("~"))
    directory = QDir::homePath();
  else if (directory.startsWith(QStringLiteral("~/")))
    directory = QDir::homePath() + directory.mid(1);
  if (!directory.isEmpty())
    config.directory = directory;
  const QString filename =
      settings.value(QStringLiteral("output/filename")).toString().trimmed();
  if (!filename.isEmpty())
    config.filename = filename;
  return config;
}

QString formatScreenshotFilename(const QString &pattern, const QDateTime &when,
                                 const QString &appSlug) {
  QString name = pattern;
  if (appSlug.isEmpty()) {
    // Drop the token and the separator that introduced it, so the default
    // pattern does not leave a dangling dash on a capture with no app.
    for (const char *joined : {"-{app}", "_{app}", " {app}", "{app}-",
                               "{app}_", "{app} ", "{app}"})
      name.replace(QLatin1String(joined), QString());
  } else {
    name.replace(QStringLiteral("{app}"), appSlug);
  }
  name.replace(QStringLiteral("{date}"),
               when.toString(QStringLiteral("yyyy-MM-dd")));
  name.replace(QStringLiteral("{time}"),
               when.toString(QStringLiteral("HH-mm-ss")));
  // Filenames only: a slash would silently change the destination, and a
  // leading dot hides the file.
  name.replace(QLatin1Char('/'), QLatin1Char('-'));
  while (!name.isEmpty() &&
         QStringLiteral(". -_").contains(name.front()))
    name.remove(0, 1);
  name = name.trimmed();
  if (name.endsWith(QStringLiteral(".png"), Qt::CaseInsensitive))
    name.chop(4);
  if (name.isEmpty())
    name = QStringLiteral("screenshot-") +
           when.toString(QStringLiteral("yyyy-MM-dd_HH-mm-ss"));
  return name + QStringLiteral(".png");
}

bool loadEditorWindowMode(const QString &filePath) {
  QSettings settings(filePath, QSettings::IniFormat);
  return settings.value(QStringLiteral("editor/mode"))
             .toString()
             .trimmed()
             .toLower() == QStringLiteral("window");
}

QString editorFloatCommand(const QString &containerId, const QSize &size,
                           const QString &output) {
  QString command = QStringLiteral("[con_id=%1] floating enable").arg(containerId);
  // Sway maps a new window on the focused workspace. Move it to the output
  // that asked for the editor before centering it there, and keep focus
  // on it. Quotes and backslashes cannot occur in a real output name.
  const bool moveToOutput = !output.isEmpty() &&
                            !output.contains(QLatin1Char('"')) &&
                            !output.contains(QLatin1Char('\\'));
  if (moveToOutput)
    command += QStringLiteral(", move container to output \"%1\"").arg(output);
  command += QStringLiteral(", resize set width %1 px height %2 px, "
                            "move position center")
                 .arg(size.width())
                 .arg(size.height());
  if (moveToOutput)
    command += QStringLiteral(", focus");
  return command;
}

bool loadEditorWindowFloating(const QString &filePath) {
  QSettings settings(filePath, QSettings::IniFormat);
  return settings.value(QStringLiteral("editor/window"))
             .toString()
             .trimmed()
             .toLower() != QStringLiteral("tiled");
}

bool loadEditorWindowBackdropOpaque(const QString &filePath) {
  QSettings settings(filePath, QSettings::IniFormat);
  return settings.value(QStringLiteral("editor/backdrop"))
             .toString()
             .trimmed()
             .toLower() != QStringLiteral("translucent");
}

QString defaultConfigPath() {
  return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
         QStringLiteral("/omasnap/omasnap.conf");
}
