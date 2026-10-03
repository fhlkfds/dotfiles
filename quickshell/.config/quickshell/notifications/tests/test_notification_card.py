"""Offscreen Qt layout checks; optional PySide6, no desktop services or state.

The card/vinyl/stack are production QML. Only Quickshell, theme/config and media
singletons are fixtures. This does not test compositor input-region delivery.
"""
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

try:
    from PySide6.QtCore import QPointF, QUrl, Qt
    from PySide6.QtGui import QGuiApplication
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
                     "NotificationStack.qml", "NotificationLogic.js"):
            shutil.copy(SOURCE / name, root / "notifications" / name)
        (root / "Quickshell/qmldir").write_text(
            "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\nRegion 1.0 Region.qml\n")
        (root / "Quickshell/Quickshell.qml").write_text('''pragma Singleton
import QtQuick
QtObject { function iconPath(name, fallback) { return "" } }
''')
        (root / "Quickshell/Region.qml").write_text(
            'import QtQuick\nQtObject { property Item item }\n')
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
            + ''.join(f'property int {k}: {v}\n' for k, v in config.items() if type(v) is int) + '}')
        (root / "notifications/NotificationService.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property ListModel popupModel: ListModel { dynamicRoles: true }
  function screenFor(name) { return name }
  function durationFor(urgency, requested) { return 0 }
}
''')
        (root / "fixture.qml").write_text('''import QtQuick
import "notifications"
Item {
  width: 1200; height: 1200
  property Item cardItem: card
  property Item stackItem: stack
  function resizeCard(width, scale) { NotificationConfig.cardWidth = width; Theme.fontScale = scale }
  function addEntry(key, screen) {
    NotificationService.popupModel.append({key: key, app: "Fixture", desktopEntry: "", appIcon: "",
      summary: "Fixture", body: "", image: "", actionsJson: "[]", glyph: "", urgency: 2,
      expireTimeout: 0, timestamp: Date.now(), screenName: screen, deadline: 0, replay: false,
      restored: false, closing: false, closeReason: ""})
  }
  function removeEntry() { NotificationService.popupModel.remove(0) }
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


if __name__ == "__main__":
    unittest.main()
