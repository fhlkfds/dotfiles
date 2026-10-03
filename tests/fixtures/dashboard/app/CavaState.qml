pragma Singleton
import QtQuick
QtObject {
  readonly property int barCount: 25
  property bool available: true
  property var levels: [0.55,0.8,0.95,0.7,0.6,0.75,0.5,0.62,0.4,0.55,0.35,0.45,0.3,0.42,0.28,0.36,0.22,0.3,0.18,0.25,0.15,0.2,0.12,0.16,0.1]
}
