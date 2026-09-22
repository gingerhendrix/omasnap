/** @fileoverview Tests Sway IPC parsing and measured-source crop mapping. */
#include "sway-capture-smoke.hpp"

#include "capture.hpp"

#include <QFile>

namespace {
QByteArray fixture(const QString &name) {
  QFile file(QStringLiteral(OMASNAP_TEST_DATA_DIR) + QLatin1Char('/') + name);
  return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

bool expect(bool condition, const QString &message, QString &error) {
  if (condition)
    return true;
  error = message;
  return false;
}

bool expectInvalidOutput(const QByteArray &json, const QString &detail,
                         QString &error) {
  MonitorInfo monitor;
  QString parseError;
  if (!parseSwayOutputs(json, monitor, parseError) &&
      parseError.contains(detail))
    return true;
  error = QStringLiteral("Incomplete focused output error was: %1")
              .arg(parseError.isEmpty() ? QStringLiteral("<empty>")
                                        : parseError);
  return false;
}
} // namespace

bool runSwayCaptureSmoke(QString &error) {
  MonitorInfo monitor;
  if (!parseSwayOutputs(fixture(QStringLiteral("sway-outputs.json")), monitor,
                        error))
    return false;
  if (!expect(
          monitor.name == QStringLiteral("DP-3") &&
              monitor.geometry == QRect(1920, 0, 3199, 1799) &&
              monitor.pixelSize == QSize(3840, 2160) &&
              monitor.workspace == QStringLiteral("dev:main") &&
              monitor.transform == QStringLiteral("normal"),
          QStringLiteral(
              "Focused fractional-scale Sway output was parsed incorrectly"),
          error))
    return false;

  if (!expectInvalidOutput(
          QByteArrayLiteral(
              R"json([{"focused":true,"rect":{"x":0,"y":0,"width":10,"height":10},"current_mode":{"width":10,"height":10}}])json"),
          QStringLiteral("missing a name"), error) ||
      !expectInvalidOutput(
          QByteArrayLiteral(
              R"json([{"name":"TEST","focused":true,"rect":{"x":0,"y":0,"width":0,"height":10},"current_mode":{"width":10,"height":10}}])json"),
          QStringLiteral("invalid logical geometry"), error) ||
      !expectInvalidOutput(
          QByteArrayLiteral(
              R"json([{"name":"TEST","focused":true,"rect":{"x":0,"y":0,"width":10,"height":10},"current_mode":{}}])json"),
          QStringLiteral("no valid current mode"), error))
    return false;

  const QByteArray rotatedJson = QByteArrayLiteral(R"json([
    {"name":"DP-1","focused":true,
     "rect":{"x":5119,"y":0,"width":1440,"height":2560},
     "current_mode":{"width":3840,"height":2160},
     "scale":1.5,"transform":"flipped-90","current_workspace":"chat"}
  ])json");
  MonitorInfo rotated;
  if (!parseSwayOutputs(rotatedJson, rotated, error))
    return false;
  if (!expect(rotated.pixelSize == QSize(2160, 3840) &&
                  rotated.geometry.size() == QSize(1440, 2560),
              QStringLiteral(
                  "Transformed Sway output dimensions were not normalized"),
              error))
    return false;

  const QVector<WindowTarget> windows =
      parseSwayTree(fixture(QStringLiteral("sway-tree.json")), monitor, error);
  if (!error.isEmpty())
    return false;
  if (!expect(
          windows.size() == 3 &&
              windows.at(0).rect == QRect(80, 100, 600, 400) &&
              windows.at(1).rect == QRect(0, 700, 480, 300) &&
              windows.at(0).appClass == QStringLiteral("dev.editor") &&
              windows.at(1).title == QStringLiteral("LegacyApp") &&
              windows.at(1).appClass == QStringLiteral("LegacyApp") &&
              windows.at(2).rect == QRect(900, 300, 700, 500) &&
              windows.at(2).appClass == QStringLiteral("notes"),
          QStringLiteral("Recursive Sway tree discovery or clipping regressed"),
          error))
    return false;

  struct CropCase {
    QSize source;
    QRect expected;
  };
  const QRectF logical(100, 50, 300, 200);
  for (const CropCase &test : {CropCase{{800, 600}, {100, 50, 300, 200}},
                               CropCase{{1200, 900}, {150, 75, 450, 300}},
                               CropCase{{959, 720}, {119, 60, 361, 240}}}) {
    CaptureData capture;
    capture.source = QImage(test.source, QImage::Format_RGB32);
    capture.source.fill(Qt::cyan);
    capture.previewSize = QSize(800, 600);
    const QSize renderedSize(
        qRound(logical.width() * test.source.width() / 800.0),
        qRound(logical.height() * test.source.height() / 600.0));
    if (!expect(
            sourcePixelRect(capture, logical) == test.expected &&
                renderCapture(capture, logical, {}, BackgroundStyle::None)
                        .size() == renderedSize,
            QStringLiteral("Fractional visible-window crop mapping regressed"),
            error))
      return false;
  }

  CaptureData transformed;
  transformed.source = QImage(2160, 3840, QImage::Format_RGB32);
  transformed.previewSize = rotated.geometry.size();
  return expect(sourcePixelRect(transformed, QRectF(100, 200, 400, 600)) ==
                    QRect(150, 300, 600, 900),
                QStringLiteral("Transformed-output crop mapping regressed"),
                error);
}
