"""Offscreen Qt layout checks; optional PySide6, no desktop services or state.

The service/card/vinyl/stack are production QML. Quickshell, theme/config,
media, native server and persistence are fixtures. No D-Bus or disk state is used.
This does not test compositor input-region delivery.
"""
import json
import os
from pathlib import Path
import shutil
import tempfile
import time
import unittest

try:
    from PySide6.QtCore import QPointF, QUrl, Qt
    from PySide6.QtGui import QGuiApplication, QImage
    from PySide6.QtQuick import QQuickItem, QQuickView
    from PySide6.QtTest import QTest
except ImportError:
    QGuiApplication = None

SOURCE = Path(__file__).resolve().parents[1]


@unittest.skipIf(QGuiApplication is None, "optional PySide6 is not installed")
class NotificationCardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["QT_QPA_PLATFORM"] = "offscreen"
        os.environ["QT_QUICK_BACKEND"] = "software"
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="notification-card-test-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        (root / "notifications").mkdir()
        (root / "Quickshell").mkdir()
        for name in ("NotificationCard.qml", "NotificationVinyl.qml",
                     "NotificationStack.qml", "NotificationLogic.js", "NotificationService.qml"):
            shutil.copy(SOURCE / name, root / "notifications" / name)
        (root / "Quickshell/qmldir").write_text(
            "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n"
            "Region 1.0 Region.qml\nSingleton 1.0 Singleton.qml\n")
        (root / "Quickshell/Quickshell.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var screens: [{name: "test"}, {name: "other"}]
  property int activeWrites: 0
  function env(name) { return "" }
  function iconPath(name, fallback) { return "" }
}
''')
        (root / "Quickshell/Singleton.qml").write_text(
            'import QtQuick\nQtObject { default property list<QtObject> children }\n')
        (root / "Quickshell/Region.qml").write_text(
            'import QtQuick\nQtObject { property Item item }\n')
        (root / "Quickshell/Hyprland").mkdir()
        (root / "Quickshell/Hyprland/qmldir").write_text(
            'module Quickshell.Hyprland\nsingleton Hyprland 1.0 Hyprland.qml\n')
        (root / "Quickshell/Hyprland/Hyprland.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property var focusedMonitor: ({name: "test"}) }
''')
        (root / "Quickshell/Io").mkdir()
        (root / "Quickshell/Io/qmldir").write_text(
            'module Quickshell.Io\nFileView 1.0 FileView.qml\nIpcHandler 1.0 IpcHandler.qml\n')
        (root / "Quickshell/Io/FileView.qml").write_text('''import QtQuick
QtObject {
  property string path
  property bool atomicWrites
  property bool watchChanges
  property bool printErrors
  signal loaded()
  signal loadFailed()
  function text() { return "{}" }
  function setText(value) {}
}
''')
        (root / "Quickshell/Io/IpcHandler.qml").write_text(
            'import QtQuick\nQtObject { property string target }\n')
        (root / "notifications/NotificationPersistence.qml").write_text('''import QtQuick
import Quickshell
QtObject {
  signal operationFailed(string operation, string detail)
  function initialize(callback) {}
  function writeActive(entry) { Quickshell.activeWrites++ }
  function writeHistory(entry) {}
}
''')
        (root / "notifications/NotificationActions.qml").write_text('''import QtQuick
QtObject { signal focusFailed(string app) }
''')
        (root / "notifications/NotificationServer.qml").write_text(
            'import QtQuick\nQtObject { property var service }\n')
        (root / "qmldir").write_text(
            "singleton Theme 1.0 Theme.qml\nsingleton MediaState 1.0 MediaState.qml\n")
        colors = dict(notificationSurface="#24283b", notificationShadow="#000000",
                      notificationBackground="#1a1b26", notificationText="#c0caf5",
                      notificationBodyText="#a9b1d6", notificationClose="#565f89",
                      notificationCountdown="#7aa2f7", critical="#f7768e",
                      accent="#7aa2f7", surfaceAlt="#414868",
                      notificationActionText="#1a1b26", notificationCriticalActionText="#1a1b26")
        (root / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {\n'
            + ''.join(f'property color {k}: "{v}"\n' for k, v in colors.items()) + '''
property real shadowOpacity: 0.4
property int notificationRadius: 12
property real fontScale: 1
property string uiFamily: "sans-serif"
property string glyphFamily: "sans-serif"
function fs(n) { return Math.round(n * fontScale) }
}''')
        (root / "MediaState.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property bool isPlaying: false; property bool hasTrack: true; property real progress: 0.5 }
''')
        config = json.loads((SOURCE / "config.json").read_text())
        (root / "notifications/qmldir").write_text(
            "singleton NotificationConfig 1.0 NotificationConfig.qml\n"
            "singleton NotificationService 1.0 NotificationService.qml\n")
        (root / "notifications/NotificationConfig.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject {\n'
            + ''.join(f'property var {k}: {json.dumps(v)}\n' for k, v in config.items()) + '}')
        (root / "fixture.qml").write_text('''import QtQuick
import Quickshell
import "notifications"
Item {
  width: 1200; height: 1200
  property Item cardItem: card
  property Item stackItem: stack
  property var nativeEntry
  property int activeWrites: Quickshell.activeWrites
  signal nativeHintsChanged()
  signal nativeBodyChanged()
  function imageFailed(item) { return item.status === Image.Error }
  function resizeCard(width, scale) { NotificationConfig.cardWidth = width; Theme.fontScale = scale }
  function addEntry(key, screen) {
    NotificationService.popupModel.append({key: key, app: "Fixture", desktopEntry: "", appIcon: "",
      summary: "Fixture", body: "", image: "", actionsJson: "[]", glyph: "", urgency: 2,
      expireTimeout: 0, timestamp: Date.now(), screenName: screen, deadline: 0, replay: false,
      restored: false, closing: false, closeReason: ""})
  }
  function addArt(key, app, image, useAppIcon) {
    addEntry(key, "test")
    NotificationService.popupModel.setProperty(NotificationService.popupModel.count - 1, "app", app)
    NotificationService.popupModel.setProperty(NotificationService.popupModel.count - 1,
      useAppIcon ? "appIcon" : "image", image)
    NotificationService.popupModel.setProperty(NotificationService.popupModel.count - 1, "body", "Track\\nArtist")
  }
  function receiveArt(app, image, useAppIcon) {
    nativeEntry = {id: 7, appName: app, summary: "Now Playing", body: "First track",
      image: useAppIcon ? "" : image, appIcon: useAppIcon ? image : "", urgency: 2,
      hints: {revision: 0}, hintsChanged: nativeHintsChanged, bodyChanged: nativeBodyChanged,
      closed: {connect: function(callback) {}}}
    NotificationService.receive(nativeEntry)
  }
  function replaceArt(body) {
    const bodyChanged = nativeEntry.body !== body
    nativeEntry.body = body
    nativeEntry.hints = {revision: nativeEntry.hints.revision + 1}
    if (bodyChanged) nativeBodyChanged()
    nativeHintsChanged()
  }
  function replaceArtSource(image, useAppIcon) {
    nativeEntry[useAppIcon ? "appIcon" : "image"] = image
    replaceArt(nativeEntry.body)
  }
  function removeEntry() { NotificationService.popupModel.remove(0) }
  function moveEntry(screen) { NotificationService.popupModel.setProperty(0, "screenName", screen) }
  NotificationCard { id: card; x: 50; y: 50 }
  NotificationStack { id: stack; x: 500; y: 50; ownerScreen: "test" }
}''')
        self.view = QQuickView()
        self.view.engine().addImportPath(str(root))
        self.view.setSource(QUrl.fromLocalFile(str(root / "fixture.qml")))
        self.assertEqual(self.view.status(), QQuickView.Ready, self.view.errors())
        self.view.show()
        self.addCleanup(self.view.close)
        self.root = self.view.rootObject()
        self.card = self.root.property("cardItem")
        QTest.qWait(50)

    def items(self, root=None):
        for child in (root or self.card).childItems():
            yield child
            yield from self.items(child)

    def test_layout_and_actions(self):
        chosen = []
        clicked = []
        self.card.actionRequested.connect(chosen.append)
        self.card.cardClicked.connect(lambda: clicked.append(True))
        self.card.setProperty("app", "Very long application name " * 8)
        self.card.setProperty("summary", "Long summary " * 100)
        self.card.setProperty("body", "Long body " * 100)
        for width, scale, count in [(380, 1, 2), (380, 1, 10), (240, 1, 4), (380, 1.5, 4)]:
            with self.subTest(width=width, scale=scale, count=count):
                self.root.resizeCard(width, scale)
                self.card.setProperty("actionsJson", json.dumps([
                    dict(identifier=str(i), text="Long action label " * 5) for i in range(count)]))
                QTest.qWait(50)
                buttons = [i for i in self.items() if i.objectName().startswith("notificationAction-")]
                self.assertEqual(len(buttons), count)
                for button in buttons:
                    pos = button.mapToItem(self.card, QPointF(0, 0))
                    self.assertGreaterEqual(button.width(), 96 * scale)
                    self.assertLessEqual(pos.x() + button.width(), self.card.width())
                    self.assertLess(pos.y() + button.height(), self.card.height())
                    center = button.mapToScene(QPointF(button.width() / 2, button.height() / 2))
                    QTest.mouseClick(self.view, Qt.LeftButton, Qt.NoModifier, center.toPoint())
                    self.assertEqual(chosen[-1], button.objectName().removeprefix("notificationAction-"))
                label = next(i for i in self.items() if i.property("text") == self.card.property("app").upper())
                pos = label.mapToItem(self.card, QPointF(0, 0))
                self.assertLessEqual(pos.x() + label.width(), self.card.width() - 26 * scale)
        self.assertEqual(clicked, [], "action clicks must not trigger the card default action")
        for value in ["null", "{}", "invalid", "[]"]:
            self.card.setProperty("actionsJson", value)
            QTest.qWait(10)
            self.assertFalse(any(i.objectName().startswith("notificationAction-") for i in self.items()))

    def test_replay_fallback_and_vinyl(self):
        self.card.setProperty("app", "Unknown app")
        self.card.setProperty("appIcon", "nonexistent-icon")
        QTest.qWait(30)
        self.assertTrue(any(i.isVisible() and i.property("text") == "󰂚" for i in self.items()))
        self.card.setProperty("replay", True)
        self.card.setProperty("timestamp", self.card.property("nowMs") - 5 * 60 * 1000)
        QTest.qWait(30)
        self.assertTrue(any(i.isVisible() and i.property("text") == "5m" for i in self.items()))
        self.card.setProperty("replay", False)
        QTest.qWait(30)
        self.assertFalse(any(i.isVisible() and i.property("text") == "5m" for i in self.items()))
        self.card.setProperty("app", "Spotify")
        self.card.setProperty("image", QUrl.fromLocalFile(str(Path(self.temp.name) / "missing-art.png")).toString())
        self.card.setProperty("body", "Track title\nArtist · Album")
        QTest.qWait(30)
        self.assertTrue(self.card.property("vinyl"))
        self.assertTrue(any(i.isVisible() and i.property("text") == "Track title" for i in self.items()))

    def test_stack_regions_follow_visible_cards(self):
        stack = self.root.property("stackItem")
        self.assertEqual(stack.property("inputRegions").toVariant(), [])
        self.root.addEntry("1", "test")
        self.root.addEntry("2", "test")
        self.root.addEntry("3", "other")
        QTest.qWait(50)
        regions = stack.property("inputRegions").toVariant()
        self.assertEqual(len(regions), 3)
        cards = [r.property("item") for r in regions if r.property("item") is not None]
        self.assertEqual(len(cards), 2)
        cards.sort(key=lambda card: card.y())
        self.assertLess(cards[0].y() + cards[0].height(), cards[1].y())
        self.root.removeEntry()
        QTest.qWait(30)
        self.assertEqual(len(stack.property("inputRegions").toVariant()), 2)

    def save_art(self, path, color):
        image = QImage(2048, 2048, QImage.Format_RGB32)
        image.fill(color)
        self.assertTrue(image.save(str(path)))

    def art_images(self, card, app):
        name = "notificationSleeveImage" if app == "Spotify" else "notificationBadgeImage"
        image = next(item for item in self.items(card) if item.objectName() == name)
        if app == "Spotify":
            label = next(item for item in self.items(card)
                         if item.objectName() == "notificationLabelEffect")
            self.assertEqual(label.property("source"), image)
        return [image]

    def wait_until(self, predicate):
        deadline = time.monotonic() + 2
        while not predicate():
            self.assertLess(time.monotonic(), deadline, "timed out waiting for artwork")
            QTest.qWait(10)

    def art_color(self, image):
        result = image.grabToImage()
        self.wait_until(lambda: not result.image().isNull())
        pixels = result.image()
        return pixels.pixelColor(pixels.width() // 2, pixels.height() // 2).rgba()

    def assert_art_color(self, card, app, color):
        image = self.art_images(card, app)[0]
        self.wait_until(lambda: image.property("progress") == 1 and self.art_color(image) == color)
        size = image.property("sourceSize")
        self.assertLessEqual(size.width(), image.width() * self.view.devicePixelRatio() + 1)
        self.assertLessEqual(size.height(), image.height() * self.view.devicePixelRatio() + 1)
        loaded = [item for item in self.items(card) if item.property("sourceSize") is not None
                  and item.property("source") != QUrl()]
        self.assertEqual(loaded, [image], "inactive layouts must not load art")

    def stack_cards(self):
        stack = self.root.property("stackItem")
        return [item for item in self.items(stack) if item.property("iconSource") is not None]

    def test_reused_image_path_shows_current_file(self):
        # Senders may rewrite one file for every notification. Each new card
        # must show what is in the file now, not what an older card loaded.
        art = Path(self.temp.name) / "art.png"
        url = QUrl.fromLocalFile(str(art)).toString()
        for app in ("Spotify", "Fixture"):
            for use_app_icon in (False, True):
                with self.subTest(app=app, use_app_icon=use_app_icon):
                    self.save_art(art, 0xffff0000)
                    self.root.addArt(app + "1", app, url, use_app_icon)
                    first = self.stack_cards()[0]
                    self.assert_art_color(first, app, 0xffff0000)
                    self.save_art(art, 0xff0000ff)
                    self.root.addArt(app + "2", app, url, use_app_icon)
                    second = self.stack_cards()[1]
                    self.assert_art_color(second, app, 0xff0000ff)
                    self.assert_art_color(first, app, 0xffff0000)
                    self.root.removeEntry()
                    self.root.removeEntry()

    def test_replacement_reloads_reused_image_path(self):
        art = Path(self.temp.name) / "replacement.png"
        url = QUrl.fromLocalFile(str(art)).toString()
        for app in ("Spotify", "Fixture"):
            for use_app_icon in (False, True):
                with self.subTest(app=app, use_app_icon=use_app_icon):
                    self.save_art(art, 0xffff0000)
                    self.root.receiveArt(app, url, use_app_icon)
                    card = self.stack_cards()[0]
                    self.assert_art_color(card, app, 0xffff0000)
                    # A native hints change can refresh identical displayed text.
                    for color, body in ((0xff0000ff, "Second track"), (0xffff0000, "Second track")):
                        self.save_art(art, color)
                        writes = self.root.property("activeWrites")
                        self.root.replaceArt(body)
                        self.assertIs(self.stack_cards()[0], card)
                        self.assert_art_color(card, app, color)
                        self.assertEqual(self.root.property("activeWrites"), writes + 1)
                    # Reloading must preserve the binding for a later, new URL.
                    other_art = Path(self.temp.name) / "other.png"
                    self.save_art(other_art, 0xff0000ff)
                    self.root.replaceArtSource(QUrl.fromLocalFile(str(other_art)).toString(), use_app_icon)
                    self.assert_art_color(card, app, 0xff0000ff)
                    self.root.removeEntry()

    def test_hidden_cards_do_not_load_art(self):
        art = Path(self.temp.name) / "hidden.png"
        self.save_art(art, 0xffff0000)
        for app in ("Spotify", "Fixture"):
            with self.subTest(app=app):
                self.root.addArt("hidden", app, QUrl.fromLocalFile(str(art)).toString(), False)
                card = self.stack_cards()[0]
                self.assert_art_color(card, app, 0xffff0000)
                self.root.moveEntry("other")
                self.wait_until(lambda: all(item.property("source") == QUrl()
                                for item in self.items(card) if item.property("sourceSize") is not None))
                self.root.moveEntry("test")
                self.assert_art_color(card, app, 0xffff0000)
                self.root.removeEntry()

    def test_replacement_recovers_missing_image(self):
        art = Path(self.temp.name) / "initially-missing.png"
        url = QUrl.fromLocalFile(str(art)).toString()
        self.root.receiveArt("Fixture", url, False)
        card = self.stack_cards()[0]
        image = next(iter(self.art_images(card, "Fixture")))
        deadline = time.monotonic() + 2
        while not self.root.imageFailed(image) and time.monotonic() < deadline:
            QTest.qWait(10)
        self.assertTrue(self.root.imageFailed(image), "missing file must fail before recovery")
        self.save_art(art, 0xff0000ff)
        self.root.replaceArt("First track")
        self.assert_art_color(card, "Fixture", 0xff0000ff)


if __name__ == "__main__":
    unittest.main()
